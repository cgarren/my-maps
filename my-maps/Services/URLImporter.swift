import Foundation
import Combine
import CoreLocation
import MapKit
import Contacts

enum ImportStage: Equatable {
    case idle
    case fetching
    case extracting(usePCC: Bool)
    case geocoding(done: Int, total: Int)
    case reviewing
    case completed
    case failed(String)
}

final class URLImporter: ObservableObject {
    @Published private(set) var stage: ImportStage = .idle
    @Published private(set) var candidates: [ExtractedAddress] = []
    @Published private(set) var usedPCC: Bool = false
    @Published private(set) var usedLLM: Bool = false
    @Published private(set) var debugLogs: [UUID: [String]] = [:]

    private var tasks = Set<AnyCancellable>()
    private var geocoder = CLGeocoder()
    private var currentTask: Task<Void, Never>? = nil

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        if geocoder.isGeocoding { geocoder.cancelGeocode() }
        DispatchQueue.main.async { [weak self] in
            self?.stage = .idle
            self?.candidates = []
            self?.usedPCC = false
            self?.usedLLM = false
            self?.debugLogs = [:]
        }
    }

    func start(urlString: String, allowPCC: Bool) {
        guard let url = URL(string: urlString) else {
            stage = .failed("Invalid URL")
            return
        }
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.run(url: url, pastedText: nil, allowPCC: allowPCC)
        }
    }

    func startFromText(_ text: String, allowPCC: Bool) {
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.run(url: nil, pastedText: text, allowPCC: allowPCC)
        }
    }

    func startFromTemplate(_ addresses: [ExtractedAddress]) {
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.runFromTemplate(addresses: addresses)
        }
    }

    // MARK: - Pipeline
    private func runFromTemplate(addresses: [ExtractedAddress]) async {
        await setCandidates(addresses)
        await setUsedPCC(false)
        await setUsedLLM(false)
        
        guard !Task.isCancelled else { return }
        await geocode()
        await setStage(.reviewing)
    }
    
    private func run(url: URL?, pastedText: String?, allowPCC: Bool) async {
        await setStage(.fetching)
        do {
            let content: String
            if let pastedText {
                content = pastedText
            } else if let url {
                content = try await fetchContent(from: url)
            } else {
                await setStage(.failed("No input provided"))
                return
            }

            // Heuristic for JS-heavy pages
            if content.trimmingCharacters(in: .whitespacesAndNewlines).count < 200,
               content.contains("<script") {
                await setStage(.failed("This page appears script-rendered. Try copy/paste."))
                return
            }

        await setStage(.extracting(usePCC: false))
        let extraction = await AIAddressExtractor.extractAddresses(fromHTML: content, allowPCC: allowPCC)
        await setUsedPCC(extraction.usedPCC)
        await setUsedLLM(extraction.usedLLM)
        let unique = dedupe(extraction.addresses)
        await setCandidates(unique)

        guard !Task.isCancelled else { return }
        await geocode()
        await setStage(.reviewing)
        } catch {
            await setStage(.failed(error.localizedDescription))
        }
    }

    private func fetchContent(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let text = String(data: data, encoding: .utf8) { return stripHTML(text) }
        // Fallback decoding to UTF-8 without strict validation
        let fallback = String(decoding: data, as: UTF8.self)
        return stripHTML(fallback)
    }

    private func stripHTML(_ html: String) -> String {
        // Very light tag removal for v1; FM will handle noisy text.
        return html.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
    }

    private func dedupe(_ list: [ExtractedAddress]) -> [ExtractedAddress] {
        var seen = Set<String>()
        var result: [ExtractedAddress] = []
        for a in list {
            let key = a.normalizedText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.insert(key).inserted { result.append(a) }
        }
        return result
    }

    private func geocode() async {
        let total = candidates.count
        var done = 0
        await setStage(.geocoding(done: 0, total: total))
        for idx in candidates.indices {
            guard !Task.isCancelled else { return }
            await geocodeOne(index: idx, snapshot: candidates[idx])
            done += 1
            await setStage(.geocoding(done: done, total: total))
            // Rate limiting: delay between addresses to avoid overwhelming the geocoding service
            if idx < candidates.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms between addresses
            }
        }
    }

    // Retry geocoding for a single candidate id
    func retry(candidateId: UUID) {
        guard let idx = candidates.firstIndex(where: { $0.id == candidateId }) else { return }
        let snap = candidates[idx]
        Task { [weak self] in
            await self?.geocodeOne(index: idx, snapshot: snap)
        }
    }

    private func log(_ id: UUID, _ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.debugLogs[id, default: []].append(message)
        }
    }

    @MainActor private func geocodeOne(index: Int, snapshot: ExtractedAddress) async {
        setItemStatus(index: index, status: .resolving)
        let id = snapshot.id
        log(id, "Preparing queries for: \(snapshot.normalizedText.replacingOccurrences(of: "\n", with: ", "))")
        do {
            let input = buildGeocodeInputs(for: snapshot)
            if let p = input.postal {
                let formatted = "\(p.street), \(p.city), \(p.state) \(p.postalCode)"
                log(id, "Try postal: \(formatted)")
            }
            for q in input.queries { log(id, "Try q: \(q)") }
            let coord = try await resolveCoordinate(forAnyOf: input.queries, postalAddress: input.postal)
            await setItemCoordinate(index: index, coord: coord)
            setItemStatus(index: index, status: .resolved)
            log(id, String(format: "Resolved: %.5f, %.5f", coord.latitude, coord.longitude))
        } catch let error as CLError where error.code == .network {
            setItemStatus(index: index, status: .failed)
            log(id, "Rate limit exceeded - try again in a few minutes or select fewer addresses")
        } catch {
            setItemStatus(index: index, status: .failed)
            log(id, "Failed: \(error.localizedDescription)")
        }
    }

    private func resolveCoordinate(forAnyOf queries: [String], postalAddress: CNPostalAddress?) async throws -> CLLocationCoordinate2D {
        var lastError: Error = URLError(.badURL)
        
        // Try structured postal address first if available
        if let postalAddress {
            do {
                let coord = try await withCheckedThrowingContinuation({ (cont: CheckedContinuation<CLLocationCoordinate2D, Error>) in
                    geocoder.geocodePostalAddress(postalAddress) { placemarks, error in
                        if let error { cont.resume(throwing: error); return }
                        if let c = placemarks?.first?.location?.coordinate { cont.resume(returning: c); return }
                        cont.resume(throwing: URLError(.cannotFindHost))
                    }
                })
                return coord
            } catch let error as CLError where error.code == .network {
                // Rate limit error - wait longer before trying string queries
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second for rate limit
                lastError = error
            } catch {
                lastError = error
            }
        }
        
        // Try string-based geocoding with region hint
        for (i, q) in queries.enumerated() {
            do {
                let coord: CLLocationCoordinate2D = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D, Error>) in
                    let usCenter = CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795)
                    let region = CLCircularRegion(center: usCenter, radius: 3_000_000, identifier: "US")
                    geocoder.geocodeAddressString(q, in: region) { placemarks, error in
                        if let loc = placemarks?.first?.location?.coordinate {
                            cont.resume(returning: loc)
                        } else if let error = error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume(throwing: URLError(.cannotFindHost))
                        }
                    }
                }
                return coord
            } catch let error as CLError where error.code == .network {
                // Rate limit - exponential backoff
                let backoffMs = min(2000, 500 * (i + 1)) // 500ms, 1s, 1.5s, 2s max
                try? await Task.sleep(nanoseconds: UInt64(backoffMs * 1_000_000))
                lastError = error
                // On rate limit, try MKLocalSearch as fallback (different service)
                if let coord = try? await searchCoordinate(q) { return coord }
            } catch {
                lastError = error
                // Small delay between query variations
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            }
        }
        
        throw lastError
    }

    private func buildGeocodeInputs(for item: ExtractedAddress) -> (queries: [String], postal: CNPostalAddress?) {
        func clean(_ s: String) -> String {
            var t = s
            // Normalize newlines to commas for base variants
            t = t.replacingOccurrences(of: "\n", with: ", ")
            let patterns = [
                "(?i)United States",
                "(?i)Phone[:]?\\s*[^,;]+",
                "(?i)Building \\d+",
                "(?i)Diamond View",
                "(?i)Floors? \\d+(,\\s*\\d+)*",
                "(?i)Suite[s]? \\d+[A-Za-z-]*",
                "#\\d+"
            ]
            for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: .regularExpression) }
            t = t.replacingOccurrences(of: "(\\d{5})-\\d{4}", with: "$1", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            t = t.replacingOccurrences(of: ",,", with: ", ")
            return t.trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespacesAndNewlines))
        }

        // Try to parse parts from multi-line address
        let lines = item.normalizedText
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let street = lines.first ?? ""
        // Common city/state/zip line like: "Birmingham, AL, 35203" or "Birmingham, AL 35203"
        let cszLine = lines.dropFirst().first(where: { $0.range(of: "[A-Za-z]+,?\\s*[A-Z]{2}\\s*,?\\s*\\d{5}(-\\d{4})?", options: .regularExpression) != nil })
        var city = "", state = "", zip = ""
        if let csz = cszLine {
            let pattern = "^\\s*([A-Za-z .'-]+),?\\s*([A-Z]{2})\\s*,?\\s*(\\d{5}(?:-\\d{4})?)?"
            if let r = try? NSRegularExpression(pattern: pattern),
               let m = r.firstMatch(in: csz, options: [], range: NSRange(location: 0, length: (csz as NSString).length)),
               m.numberOfRanges >= 3 {
                city = (csz as NSString).substring(with: m.range(at: 1))
                state = (csz as NSString).substring(with: m.range(at: 2))
                if m.numberOfRanges >= 4 {
                    zip = m.range(at: 3).location != NSNotFound ? (csz as NSString).substring(with: m.range(at: 3)) : ""
                }
            }
        }

        let oneLineNorm = clean(item.normalizedText)
        let oneLineRaw = clean(item.rawText)
        var variants: [String] = []
        func add(_ s: String) { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { variants.append(t) } }

        // Specific structured variants first
        let compCity = item.city?.isEmpty == false ? item.city! : city
        let compState = item.state?.isEmpty == false ? item.state! : state
        var compZip = item.postalCode?.isEmpty == false ? item.postalCode! : zip
        // Normalize ZIP+4 to 5 digits
        if let m = compZip.range(of: "^\\d{5}", options: .regularExpression) { compZip = String(compZip[m]) }
        if !street.isEmpty && !compCity.isEmpty && !compState.isEmpty && !compZip.isEmpty { add("\(street), \(compCity), \(compState) \(compZip)") }
        if !street.isEmpty && !compCity.isEmpty && !compState.isEmpty { add("\(street), \(compCity), \(compState)") }
        if !street.isEmpty && !compZip.isEmpty { add("\(street) \(compZip)") }
        if !compCity.isEmpty && !compState.isEmpty && !compZip.isEmpty { add("\(compCity), \(compState) \(compZip)") }

        // Base variants
        add(oneLineNorm.replacingOccurrences(of: "(?i),?\\s*United States$", with: "", options: .regularExpression))
        add(oneLineNorm)
        add(oneLineRaw)

        // Deduplicate preserving order
        var seen = Set<String>()
        var out: [String] = []
        for q in variants {
            let key = q.lowercased()
            if seen.insert(key).inserted { out.append(q) }
        }
        // Build CNPostalAddress if we have components
        var postal: CNPostalAddress? = nil
        if !street.isEmpty || !(compCity.isEmpty && compState.isEmpty && compZip.isEmpty) {
            let m = CNMutablePostalAddress()
            m.street = street
            if !compCity.isEmpty { m.city = compCity }
            if !compState.isEmpty { m.state = compState }
            if !compZip.isEmpty { m.postalCode = compZip }
            m.country = "United States"
            postal = m.copy() as? CNPostalAddress
        }
        return (out, postal)
    }

    private func searchCoordinate(_ query: String) async throws -> CLLocationCoordinate2D {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // Focus search roughly over the continental US to improve relevance
        let center = CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795)
        request.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60))
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        if let coord = response.mapItems.first?.placemark.coordinate { return coord }
        throw URLError(.cannotFindHost)
    }

    // MARK: - Main-thread state updates
    @MainActor private func setStage(_ stage: ImportStage) { self.stage = stage }
    @MainActor private func setCandidates(_ c: [ExtractedAddress]) { self.candidates = c }
    @MainActor private func setUsedPCC(_ used: Bool) { self.usedPCC = used }
    @MainActor private func setUsedLLM(_ used: Bool) { self.usedLLM = used }
    @MainActor private func setItemStatus(index: Int, status: GeocodeStatus) {
        guard candidates.indices.contains(index) else { return }
        var copy = candidates
        copy[index].geocodeStatus = status
        candidates = copy
    }
    @MainActor private func setItemCoordinate(index: Int, coord: CLLocationCoordinate2D) {
        guard candidates.indices.contains(index) else { return }
        var copy = candidates
        copy[index].latitude = coord.latitude
        copy[index].longitude = coord.longitude
        candidates = copy
    }
}


