//
//  my_mapsApp.swift
//  my-maps
//
//  Created by Cooper Garren on 10/13/25.
//

import SwiftUI
import SwiftData

@main
struct my_mapsApp: App {
    var body: some Scene {
        WindowGroup {
            MapsListView()
        }
        .modelContainer(for: [MapCollection.self, Place.self])
    }
}
