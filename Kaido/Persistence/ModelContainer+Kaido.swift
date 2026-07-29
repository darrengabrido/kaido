import Foundation
import SwiftData

enum KaidoModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Route.self,
            Waypoint.self,
            Ride.self,
            BikeProfile.self,
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
