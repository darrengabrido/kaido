import Foundation

/// Seed content for the Routes tab's "Community" section: a handful of well-known bike routes
/// hand-picked by the Kaido team, bundled directly into the app so the feed is never empty even
/// before any rider has published one of their own (see `CompositeCommunityRouteService`, which
/// merges this catalog with whatever's been published to Supabase).
///
/// Waypoint coordinates below are approximate landmarks along each route, not surveyed GPS
/// tracks — good enough to preview on the map and to hand to Mapbox Directions (which snaps to
/// real roads) once a rider taps "Add to My Routes" and then "Start Navigation". Distance/
/// elevation figures are similarly approximate, for display only.
///
/// These are shaped as ordinary `CommunityRoute` values so they flow through the exact same
/// model/UI as a real published row, but they don't correspond to any row in `community_routes` —
/// `authorUserId` is a fixed sentinel that will never match a real `auth.uid()`, so
/// `CommunityRoutesViewModel.isMine` (and therefore the "Remove from Community" action) correctly
/// never treats one of these as removable.
enum CuratedCommunityRoutes {
    /// Never a real Supabase user id — just needs to be stable and never collide with `auth.uid()`.
    static let curatorUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// A fixed, arbitrary timestamp (matching the "generic fixed test date" already used in
    /// `GroupRideLocationThrottlePolicyTests`) rather than `Date()` — keeps every launch's catalog
    /// byte-for-byte `Equatable`, which the Codable round-trip test relies on.
    private static let seededAt = Date(timeIntervalSince1970: 1_700_000_000)

    static let all: [CommunityRoute] = [
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000001",
            name: "Golden Gate Park Loop",
            description: "San Francisco, CA — a rolling loop through Golden Gate Park's meadows "
                + "and lakes, past the Conservatory of Flowers and out to the old Dutch windmills.",
            distanceMeters: 11_200,
            elevationGainMeters: 55,
            waypoints: [
                (37.7716, -122.4605),
                (37.7699, -122.4763),
                (37.7690, -122.5024),
                (37.7739, -122.4568)
            ]
        ),
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000002",
            name: "Central Park Full Loop",
            description: "New York, NY — the classic six-mile park drive loop, rolling hills and "
                + "mostly free of car traffic outside rush hour.",
            distanceMeters: 10_200,
            elevationGainMeters: 95,
            waypoints: [
                (40.7681, -73.9819),
                (40.7859, -73.9585),
                (40.7968, -73.9515),
                (40.7743, -73.9740)
            ]
        ),
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000003",
            name: "Lakefront Trail: Museum Campus to North Ave",
            description: "Chicago, IL — a flat, breezy ride along Lake Michigan from the Museum "
                + "Campus up past Navy Pier to North Avenue Beach.",
            distanceMeters: 8_300,
            elevationGainMeters: 10,
            waypoints: [
                (41.8663, -87.6169),
                (41.8917, -87.6086),
                (41.9119, -87.6255)
            ]
        ),
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000004",
            name: "Ballona Creek Bike Path",
            description: "Los Angeles, CA — a flat, car-free creek path from Culver City down to "
                + "the Marina del Rey harbor.",
            distanceMeters: 10_500,
            elevationGainMeters: 8,
            waypoints: [
                (34.0211, -118.4079),
                (33.9890, -118.4370),
                (33.9803, -118.4517)
            ]
        ),
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000005",
            name: "Burke-Gilman Trail: Fremont to Golden Gardens",
            description: "Seattle, WA — a wooded trail from Fremont past the Ballard Locks, "
                + "ending at a sunset-worthy beach.",
            distanceMeters: 9_600,
            elevationGainMeters: 35,
            waypoints: [
                (47.6478, -122.3495),
                (47.6650, -122.3963),
                (47.6900, -122.4056)
            ]
        ),
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000006",
            name: "Lady Bird Lake Hike-and-Bike Loop",
            description: "Austin, TX — a scenic slice of the full loop around the lake, past "
                + "downtown skyline views and the Congress Ave bat bridge.",
            distanceMeters: 6_800,
            elevationGainMeters: 20,
            waypoints: [
                (30.2610, -97.7446),
                (30.2635, -97.7658),
                (30.2687, -97.7508),
                (30.2605, -97.7440)
            ]
        )
    ]

    private static func makeRoute(
        id: String,
        name: String,
        description: String,
        distanceMeters: Double,
        elevationGainMeters: Double,
        waypoints: [(Double, Double)]
    ) -> CommunityRoute {
        let orderedWaypoints = waypoints.enumerated().map { index, coordinate in
            CommunityRoute.Waypoint(latitude: coordinate.0, longitude: coordinate.1, order: index)
        }
        let start = orderedWaypoints[0]
        return CommunityRoute(
            id: UUID(uuidString: id)!,
            authorUserId: curatorUserId,
            authorDisplayName: "Kaido",
            name: name,
            description: description,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            waypoints: orderedWaypoints,
            startLatitude: start.latitude,
            startLongitude: start.longitude,
            status: .published,
            createdAt: seededAt,
            updatedAt: seededAt
        )
    }
}
