import Foundation
import NaturalLanguage

struct AIAddressExtractor {
    static var isSupported: Bool {
        // Natural Language framework is available on iOS 13+
        if #available(iOS 13, macOS 10.15, *) { return true }
        return false
    }

    struct Result {
        let addresses: [ExtractedAddress]
        let usedPCC: Bool
        let usedLLM: Bool
    }

    // Preferred entry: pass raw HTML so we can parse JSON-LD if available
    static func extractAddresses(fromHTML html: String, allowPCC: Bool) async -> Result {
        // 1) Try JSON-LD (schema.org PostalAddress)
        let jsonLDAddresses = extractFromJSONLD(html: html)
        if !jsonLDAddresses.isEmpty {
            return Result(addresses: jsonLDAddresses, usedPCC: false, usedLLM: false)
        }

        // 2) Fallback to plain text extraction
        let text = decodeHTMLEntities(stripHTML(html))
        return await extractAddresses(from: text, allowPCC: allowPCC)
    }

    // Back-compat entry for plain text
    static func extractAddresses(from text: String, allowPCC: Bool) async -> Result {
        var found: [ExtractedAddress] = []
        var usedLLM = false
        
        // 0) Try Foundation Models LLM extraction (iOS 26+)
        if LLMAddressExtractor.isSupported {
            print(">>> Trying Foundation Models for address extraction")
            if let llmResults = try? await LLMAddressExtractor.extractAddresses(from: text) {
                found.append(contentsOf: llmResults)
                usedLLM = true
            }
        }
        
        // 1) Try Natural Language framework for AI-powered entity extraction (iOS 13+)
        // Only use if LLM didn't work or found nothing
        if !usedLLM || found.isEmpty {
            print(">>> Using Natural Language for address extraction")
            found.append(contentsOf: extractUsingNaturalLanguage(from: text))
        }
        
        // 2) Heuristic structured parsing for Deloitte-style lists
        found.append(contentsOf: parseStructuredBlocks(from: text))

        // 3) Fallback to NSDataDetector for any additional matches
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
        detector?.enumerateMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) { result, _, _ in
            guard let result, let components = result.addressComponents else { return }
            let raw = (text as NSString).substring(with: result.range)
            let normalized = normalize(components: components)
            found.append(ExtractedAddress(rawText: raw, normalizedText: normalized, displayName: nil))
        }

        // Filter out items that don't look like mailable addresses
        found = found.filter { isAddressLike($0.normalizedText) }
        
        // De-duplicate addresses
        var seen = Set<String>()
        var unique: [ExtractedAddress] = []
        for a in found {
            let key = a.normalizedText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.insert(key).inserted { unique.append(a) }
        }
        
        // Heuristic: if nothing found and PCC allowed, signal PCC usage for disclosure
        let usedPCC = unique.isEmpty && allowPCC
        print(">>> Extracted \(unique.count) addresses")
        print(">>> Results: \(unique)")
        return Result(addresses: unique, usedPCC: usedPCC, usedLLM: usedLLM)
    }

    // MARK: - Natural Language AI Extraction
    private static func extractUsingNaturalLanguage(from text: String) -> [ExtractedAddress] {
        var results: [ExtractedAddress] = []
        
        // Use NLTagger to identify location entities and place names
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        // Options for better accuracy
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        let tags: [NLTag] = [.placeName, .organizationName] // Organizations often have addresses
        
        // Find all location/place entities
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            guard let tag = tag, tags.contains(tag) else { return true }
            
            let entity = String(text[range])
            
            // Try to extract address context around this entity
            if let address = extractAddressContext(from: text, around: range, entityName: entity) {
                results.append(address)
            }
            
            return true
        }
        
        return results
    }
    
    // Extract full address from context around a detected entity
    private static func extractAddressContext(from text: String, around range: Range<String.Index>, entityName: String) -> ExtractedAddress? {
        // Expand the range to capture surrounding lines (up to 5 lines before and after)
        let lines = text.components(separatedBy: .newlines)
        guard let nsRange = Range(NSRange(range, in: text), in: text) else { return nil }
        
        // Find which line contains our entity
        var currentPos = text.startIndex
        var lineIndex = 0
        for (idx, line) in lines.enumerated() {
            let lineEnd = text.index(currentPos, offsetBy: line.count, limitedBy: text.endIndex) ?? text.endIndex
            if nsRange.lowerBound >= currentPos && nsRange.lowerBound < lineEnd {
                lineIndex = idx
                break
            }
            // Account for newline character
            currentPos = text.index(lineEnd, offsetBy: 1, limitedBy: text.endIndex) ?? text.endIndex
        }
        
        // Extract 5 lines before and after the entity
        let startLine = max(0, lineIndex - 5)
        let endLine = min(lines.count - 1, lineIndex + 5)
        let contextLines = Array(lines[startLine...endLine])
        let context = contextLines.joined(separator: "\n")
        
        // Try to find address-like patterns in this context
        let addressPattern = """
        (?x)                                        # Enable verbose mode
        (?:                                          # Start non-capturing group
            \\d+\\s+[A-Za-z0-9\\s,.'#-]+?           # Street address (123 Main St)
            (?:Suite|Ste\\.?|Floor|Fl\\.?|#)?\\s*\\d*[A-Za-z]?  # Optional suite/floor
            \\s*[,\\n]\\s*                           # Separator
            [A-Za-z\\s.'()-]+,\\s*                   # City
            [A-Z]{2}\\s*                             # State (2 letters)
            ,?\\s*\\d{5}(?:-\\d{4})?                # ZIP code
        )
        """
        
        guard let regex = try? NSRegularExpression(pattern: addressPattern, options: []) else { return nil }
        let nsContext = context as NSString
        
        if let match = regex.firstMatch(in: context, options: [], range: NSRange(location: 0, length: nsContext.length)) {
            let addressText = nsContext.substring(with: match.range)
            let normalized = addressText
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            return ExtractedAddress(
                rawText: addressText,
                normalizedText: normalized,
                displayName: entityName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        
        return nil
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


