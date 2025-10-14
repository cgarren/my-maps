import Foundation

struct TemplatePlace: Codable {
    let name: String
    let streetAddress1: String
    let streetAddress2: String?
    let city: String
    let state: String?
    let postalCode: String?
    let country: String?
}

struct MapTemplate: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let displayName: String
    let fileName: String
}

