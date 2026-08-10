import Foundation

/// A first, non-backend-driven pass at the "Community" section: a handful of well-known bike
/// routes hand-picked by the Kaido team, bundled directly into the app.
///
/// Waypoint coordinates below are approximate landmarks along each route, not surveyed GPS
/// tracks — good enough to preview on the map and to hand to Mapbox Directions (which snaps to
/// real roads) once a rider taps "Add to My Routes" and then "Start Navigation". Distance/
/// elevation figures are similarly approximate, for display only.
///
/// This is deliberately just a static array behind `CommunityRouteService` — see that file for
/// how a backend-driven catalog would replace it later without touching any UI.
enum CuratedCommunityRoutes {
    static let all: [CommunityRoute] = [
        CommunityRoute(
            id: UUID(uuidString: "3F2B9C10-6E4A-4B8E-9C2D-000000000001")!,
            name: "Golden Gate Park Loop",
            description: "A rolling loop through Golden Gate Park's meadows and lakes, past the "
                + "Conservatory of Flowers and out to the old Dutch windmills.",
            areaName: "San Francisco, CA",
            curatorName: "Kaido",
            distanceMeters: 11_200,
            elevationGainMeters: 55,
            waypoints: [
                .init(latitude: 37.7716, longitude: -122.4605, order: 0),
                .init(latitude: 37.7699, longitude: -122.4763, order: 1),
                .init(latitude: 37.7690, longitude: -122.5024, order: 2),
                .init(latitude: 37.7739, longitude: -122.4568, order: 3)
            ]
        ),
        CommunityRoute(
            id: UUID(uuidString: "3F2B9C10-6E4A-4B8E-9C2D-000000000002")!,
            name: "Central Park Full Loop",
            description: "The classic six-mile park drive loop — rolling hills, and mostly free of "
                + "car traffic outside rush hour.",
            areaName: "New York, NY",
            curatorName: "Kaido",
            distanceMeters: 10_200,
            elevationGainMeters: 95,
            waypoints: [
                .init(latitude: 40.7681, longitude: -73.9819, order: 0),
                .init(latitude: 40.7859, longitude: -73.9585, order: 1),
                .init(latitude: 40.7968, longitude: -73.9515, order: 2),
                .init(latitude: 40.7743, longitude: -73.9740, order: 3)
            ]
        ),
        CommunityRoute(
            id: UUID(uuidString: "3F2B9C10-6E4A-4B8E-9C2D-000000000003")!,
            name: "Lakefront Trail: Museum Campus to North Ave",
            description: "A flat, breezy ride along Lake Michigan from the Museum Campus up past "
                + "Navy Pier to North Avenue Beach.",
            areaName: "Chicago, IL",
            curatorName: "Kaido",
            distanceMeters: 8_300,
            elevationGainMeters: 10,
            waypoints: [
                .init(latitude: 41.8663, longitude: -87.6169, order: 0),
                .init(latitude: 41.8917, longitude: -87.6086, order: 1),
                .init(latitude: 41.9119, longitude: -87.6255, order: 2)
            ]
        ),
        CommunityRoute(
            id: UUID(uuidString: "3F2B9C10-6E4A-4B8E-9C2D-000000000004")!,
            name: "Ballona Creek Bike Path",
            description: "A flat, car-free creek path from Culver City down to the Marina del Rey "
                + "harbor.",
            areaName: "Los Angeles, CA",
            curatorName: "Kaido",
            distanceMeters: 10_500,
            elevationGainMeters: 8,
            waypoints: [
                .init(latitude: 34.0211, longitude: -118.4079, order: 0),
                .init(latitude: 33.9890, longitude: -118.4370, order: 1),
                .init(latitude: 33.9803, longitude: -118.4517, order: 2)
            ]
        ),
        CommunityRoute(
            id: UUID(uuidString: "3F2B9C10-6E4A-4B8E-9C2D-000000000005")!,
            name: "Burke-Gilman Trail: Fremont to Golden Gardens",
            description: "A wooded trail from Fremont past the Ballard Locks, ending at a "
                + "sunset-worthy beach.",
            areaName: "Seattle, WA",
            curatorName: "Kaido",
            distanceMeters: 9_600,
            elevationGainMeters: 35,
            waypoints: [
                .init(latitude: 47.6478, longitude: -122.3495, order: 0),
                .init(latitude: 47.6650, longitude: -122.3963, order: 1),
                .init(latitude: 47.6900, longitude: -122.4056, order: 2)
            ]
        ),
        CommunityRoute(
            id: UUID(uuidString: "3F2B9C10-6E4A-4B8E-9C2D-000000000006")!,
            name: "Lady Bird Lake Hike-and-Bike Loop",
            description: "A scenic slice of the full loop around the lake, past downtown skyline "
                + "views and the Congress Ave bat bridge.",
            areaName: "Austin, TX",
            curatorName: "Kaido",
            distanceMeters: 6_800,
            elevationGainMeters: 20,
            waypoints: [
                .init(latitude: 30.2610, longitude: -97.7446, order: 0),
                .init(latitude: 30.2635, longitude: -97.7658, order: 1),
                .init(latitude: 30.2687, longitude: -97.7508, order: 2),
                .init(latitude: 30.2605, longitude: -97.7440, order: 3)
            ]
        )
    ]
}
