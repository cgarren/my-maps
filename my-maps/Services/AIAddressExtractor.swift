import Foundation

struct AIAddressExtractor {
    static var isSupported: Bool {
        if #available(iOS 18, macOS 15, *) { return true }
        return false
    }

    struct Result {
        let addresses: [ExtractedAddress]
        let usedPCC: Bool
    }

    // Preferred entry: pass raw HTML so we can parse JSON-LD if available
    static func extractAddresses(fromHTML html: String, allowPCC: Bool) async -> Result {
        // 1) Try JSON-LD (schema.org PostalAddress)
        let jsonLDAddresses = extractFromJSONLD(html: html)
        if !jsonLDAddresses.isEmpty {
            return Result(addresses: jsonLDAddresses, usedPCC: false)
        }

        // 2) Fallback to plain text extraction
        let text = decodeHTMLEntities(stripHTML(html))
        return await extractAddresses(from: text, allowPCC: allowPCC)
    }

    // Back-compat entry for plain text
    static func extractAddresses(from text: String, allowPCC: Bool) async -> Result {
        // 0) Heuristic structured parsing for Deloitte-style lists
        var found: [ExtractedAddress] = parseStructuredBlocks(from: text)

        // 1) Fallback to NSDataDetector for any additional matches
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
        detector?.enumerateMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) { result, _, _ in
            guard let result, let components = result.addressComponents else { return }
            let raw = (text as NSString).substring(with: result.range)
            let normalized = normalize(components: components)
            found.append(ExtractedAddress(rawText: raw, normalizedText: normalized, displayName: nil))
        }

        // Filter out items that don't look like mailable addresses
        found = found.filter { isAddressLike($0.normalizedText) }
        // Heuristic: if nothing found and PCC allowed, signal PCC usage for disclosure
        let usedPCC = found.isEmpty && allowPCC
        return Result(addresses: found, usedPCC: usedPCC)
    }

    private static func normalize(components: [NSTextCheckingKey: String]) -> String {
        let street = components[.street] ?? ""
        let city = components[.city] ?? ""
        let state = components[.state] ?? ""
        let zip = components[.zip] ?? ""
        let country = components[.country] ?? ""

        var parts: [String] = []
        if !street.isEmpty { parts.append(street) }
        var cityStateZip: [String] = []
        if !city.isEmpty { cityStateZip.append(city) }
        if !state.isEmpty { cityStateZip.append(state) }
        if !zip.isEmpty { cityStateZip.append(zip) }
        if !cityStateZip.isEmpty { parts.append(cityStateZip.joined(separator: ", ")) }
        if !country.isEmpty { parts.append(country) }
        return parts.joined(separator: "\n")
    }

    // MARK: - JSON-LD parsing helpers
    private static func extractFromJSONLD(html: String) -> [ExtractedAddress] {
        var results: [ExtractedAddress] = []
        // Capture <script type="application/ld+json"> ... </script>
        let pattern = "<script[^>]*type=\\\"application/ld\\+json\\\"[^>]*>([\\s\\S]*?)</script>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let ns = html as NSString
        let matches = regex?.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) ?? []
        for m in matches {
            guard m.numberOfRanges > 1 else { continue }
            let jsonFragment = ns.substring(with: m.range(at: 1))
            // Some pages embed multiple JSON objects; try to parse loosely
            if let data = jsonFragment.data(using: .utf8) {
                if let obj = try? JSONSerialization.jsonObject(with: data) {
                    results.append(contentsOf: collectAddresses(json: obj))
                }
            }
        }
        // De-dupe by normalized text
        var seen = Set<String>()
        var unique: [ExtractedAddress] = []
        for a in results {
            let key = a.normalizedText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.insert(key).inserted { unique.append(a) }
        }
        return unique
    }

    private static func collectAddresses(json: Any) -> [ExtractedAddress] {
        var out: [ExtractedAddress] = []
        if let dict = json as? [String: Any] {
            // PostalAddress object
            if let type = dict["@type"] as? String, type.caseInsensitiveCompare("PostalAddress") == .orderedSame {
                if let addr = normalizedFromSchema(dict: dict, name: dict["name"] as? String) {
                    out.append(addr)
                }
            }
            // Place/Organization with address field
            if let addrDict = dict["address"] as? [String: Any] {
                let name = dict["name"] as? String
                if let addr = normalizedFromSchema(dict: addrDict, name: name) { out.append(addr) }
            }
            // Recurse into arrays/dicts
            for (_, v) in dict {
                out.append(contentsOf: collectAddresses(json: v))
            }
        } else if let arr = json as? [Any] {
            for v in arr { out.append(contentsOf: collectAddresses(json: v)) }
        }
        return out
    }

    private static func normalizedFromSchema(dict: [String: Any], name: String?) -> ExtractedAddress? {
        let street = dict["streetAddress"] as? String ?? ""
        let city = dict["addressLocality"] as? String ?? ""
        let state = dict["addressRegion"] as? String ?? ""
        let zip = dict["postalCode"] as? String ?? ""
        var country: String = ""
        if let c = dict["addressCountry"] as? String { country = c }
        else if let cdict = dict["addressCountry"] as? [String: Any] { country = (cdict["name"] as? String) ?? "" }

        var parts: [String] = []
        if !street.isEmpty { parts.append(street) }
        let csz = [city, state, zip].filter { !$0.isEmpty }.joined(separator: ", ")
        if !csz.isEmpty { parts.append(csz) }
        if !country.isEmpty { parts.append(country) }
        guard !parts.isEmpty else { return nil }
        let normalized = parts.joined(separator: "\n")
        return ExtractedAddress(rawText: normalized, normalizedText: normalized, displayName: name)
    }

    private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
    }

    // MARK: - Structured block parsing (handles lines like City -> Street -> Suite -> City, ST -> ZIP)
    private static func parseStructuredBlocks(from text: String) -> [ExtractedAddress] {
        // Normalize
        let cleaned = text
            .replacingOccurrences(of: "\u{200B}", with: "") // zero-width
            .replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "\r", with: "")

        var lines = cleaned
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Remove obvious noise
        let noiseEquals: [String] = [
            "United States", "View map", "Office details", "Offices in the U.S.", "Our Offices",
        ]
        lines.removeAll { ln in
            if noiseEquals.contains(where: { ln.caseInsensitiveCompare($0) == .orderedSame }) { return true }
            if ln.range(of: "(?i)^Phone[:]", options: .regularExpression) != nil { return true }
            if ln.range(of: "(?i)^Search$", options: .regularExpression) != nil { return true }
            return false
        }

        func isLikelyStreet(_ s: String) -> Bool {
            if s.range(of: "\\d", options: .regularExpression) == nil { return false }
            let tokens = ["street","st","road","rd","avenue","ave","boulevard","blvd","court","ct","parkway","pkwy","drive","dr","place","pl","way","lane","ln","highway","hwy","mall"]
            return tokens.contains { s.lowercased().contains($0) }
        }

        func isSuiteOrFloor(_ s: String) -> Bool {
            // Match common secondary unit/floor indicators; keep ASCII-only for safety
            let p = "(?i)^(suite|ste\\.|floor|fl|building|bldg|unit|level|apt|apartment|room|rm|2nd|3rd|4th|5th)"
            return s.range(of: p, options: .regularExpression) != nil || s.lowercased().hasPrefix("suite ")
        }

        func parseCityStateZip(_ s: String) -> (city: String, state: String, zip: String?)? {
            let pattern = "^\\s*([A-Za-z .'()&-]+),\\s*([A-Z]{2})(?:\\s*,?\\s*(\\d{5}(?:-\\d{4})?))?\\s*$"
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            let ns = s as NSString
            guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
            let city = ns.substring(with: m.range(at: 1))
            let state = ns.substring(with: m.range(at: 2))
            let zip = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : nil
            return (city, state, zip)
        }

        var i = 0
        var results: [ExtractedAddress] = []
        while i < lines.count {
            let line = lines[i]
            // Candidate city header: letters/spaces only, no digits, not a keyword
            let isCityHeader = line.range(of: "^[A-Za-z .'()&-]+$", options: .regularExpression) != nil && !isLikelyStreet(line)
            if isCityHeader && i + 1 < lines.count {
                // Expect a street next
                let next = lines[i + 1]
                if isLikelyStreet(next) {
                    var addrLines: [String] = [next]
                    var j = i + 2
                    if j < lines.count, isSuiteOrFloor(lines[j]) { addrLines.append(lines[j]); j += 1 }
                    var city = "", state = "", zip: String? = nil
                    if j < lines.count, let csz = parseCityStateZip(lines[j]) {
                        city = csz.city; state = csz.state; zip = csz.zip; j += 1
                    } else if j + 1 < lines.count,
                              let csz = parseCityStateZip(lines[j]),
                              lines[j + 1].range(of: "^\\d{5}(-\\d{4})?$", options: .regularExpression) != nil {
                        city = csz.city; state = csz.state; zip = lines[j + 1]; j += 2
                    }

                    var parts = addrLines
                    if !city.isEmpty {
                        let cszJoin = [city, state, zip ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
                        if !cszJoin.isEmpty { parts.append(cszJoin) }
                    }
                    let normalized = parts.joined(separator: "\n")
                    let raw = (addrLines + [line]).joined(separator: "\n")
                    results.append(ExtractedAddress(rawText: raw, normalizedText: normalized, displayName: line, city: city, state: state, postalCode: zip))
                    i = j
                    continue
                }
            }
            i += 1
        }

        // De-dupe by normalized text
        var seen = Set<String>()
        var unique: [ExtractedAddress] = []
        for a in results {
            let key = a.normalizedText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.insert(key).inserted { unique.append(a) }
        }
        return unique
    }

    // MARK: - Address heuristics & utilities
    private static func isAddressLike(_ text: String) -> Bool {
        let oneLine = text.replacingOccurrences(of: "\n", with: ", ")
        let hasStreetNum = oneLine.range(of: "(?i)\\b\\d{1,6}\\s+[A-Za-z0-9'.-]+\\s+(street|st|road|rd|avenue|ave|boulevard|blvd|court|ct|parkway|pkwy|drive|dr|place|pl|way|lane|ln|highway|hwy|mall)\\b", options: .regularExpression) != nil
        let hasCityState = oneLine.range(of: "(?i)[A-Za-z .'-]+,\\s*[A-Z]{2}\\b", options: .regularExpression) != nil
        let hasZip = oneLine.range(of: "\\b\\d{5}(?:-\\d{4})?\\b", options: .regularExpression) != nil
        return hasStreetNum || (hasCityState && hasZip)
    }

    private static func decodeHTMLEntities(_ s: String) -> String {
        var t = s
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#34;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ]
        for (e, r) in entities { t = t.replacingOccurrences(of: e, with: r) }
        return t
    }
}


