import Foundation

/// Seed content for the Routes tab's "Community" section: a handful of well-known, real bike
/// routes bundled directly into the app so the feed is never empty even before any rider has
/// published one of their own (see `CompositeCommunityRouteService`, which merges this catalog
/// with whatever's been published to Supabase).
///
/// Every route below corresponds to an actual, named public trail. Distance and elevation gain
/// are taken from a single official or GPS-tracked source per route (cited above each entry)
/// rather than guessed, and every waypoint is the real coordinate of a landmark that sits on or
/// right next to the trail (parks, bridges, beaches — verified against official park-department
/// pages, Wikipedia, or other public coordinate references). What's still simplified: the
/// waypoints are a handful of landmarks strung together, not a turn-by-turn surveyed GPS track,
/// so the drawn line is a reasonable approximation of the route's shape rather than an exact
/// path. That's good enough to preview on the map and to hand to Mapbox Directions (which snaps
/// to real roads) once a rider taps "Add to My Routes" and then "Start Navigation".
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
        // Distance/elevation: AllTrails "Golden Gate Park Loop" (GPS-tracked, 1,900+ reviews),
        // 6.8 mi / 360 ft gain. Waypoints: McLaren Lodge (park HQ, east entrance), the
        // Conservatory of Flowers, Stow Lake, and the Dutch Windmill at the park's western edge —
        // all real SF Rec & Park / Wikipedia-verified landmarks on the loop.
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000001",
            name: "Golden Gate Park Loop",
            description: "San Francisco, CA — a rolling loop through the park past McLaren Lodge, "
                + "the Conservatory of Flowers, and Stow Lake, out to the Dutch Windmill at the "
                + "western edge near Ocean Beach.",
            distanceMeters: 10_944,
            elevationGainMeters: 110,
            waypoints: [
                (37.7717, -122.4547),
                (37.77259, -122.46022),
                (37.76766, -122.47462),
                (37.770732, -122.509403)
            ]
        ),
        // Distance: Central Park Conservancy's official bike/running map — "Loop is 6.02 mi /
        // 9.68 km". Elevation: ~285 ft, consistent across cycling sources (Ride with GPS's
        // "Central Park Full Loop" route, NYCC cue sheets). Waypoints trace the required
        // counterclockwise direction starting at Engineers Gate (90th St & 5th Ave), up past
        // Duke Ellington Circle (110th & 5th), down the west side at Strawberry Fields (72nd St),
        // across the south at Columbus Circle and Grand Army Plaza, and back.
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000002",
            name: "Central Park Full Loop",
            description: "New York, NY — the park's official 6.02-mile counterclockwise loop, "
                + "from Engineers Gate past the Harlem Meer, Strawberry Fields, Columbus Circle, "
                + "and Grand Army Plaza.",
            distanceMeters: 9_680,
            elevationGainMeters: 87,
            waypoints: [
                (40.78410, -73.95861),
                (40.796872, -73.949236),
                (40.77556, -73.97500),
                (40.7681, -73.9819),
                (40.7644, -73.9730)
            ]
        ),
        // Distance/elevation: Komoot's "Lakefront Trail: North Avenue Beach to Navy Pier" route,
        // 6.6 mi (10.6 km) / ~20 m gain — matches the trail's well-documented flat profile.
        // Waypoints: North Avenue Beach, Oak Street Beach (the trail's famous S-curve), and Navy
        // Pier, all real, independently verified landmark coordinates.
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000003",
            name: "Lakefront Trail: North Ave Beach to Navy Pier",
            description: "Chicago, IL — a flat, breezy ride down the Lake Michigan shoreline from "
                + "North Avenue Beach past Oak Street Beach's S-curve to Navy Pier.",
            distanceMeters: 10_600,
            elevationGainMeters: 20,
            waypoints: [
                (41.9142, -87.6245),
                (41.9030, -87.6230),
                (41.8927, -87.6102)
            ]
        ),
        // Distance/elevation: LA County Parks & Recreation's official "Quick Guide" for the
        // Ballona Creek Bike Path — 6.7 mi / 68 ft gain (matches the trail's near-flat, former
        // flood-control-channel profile). Waypoints: Syd Kronenthal Park in Culver City (the
        // trail's eastern trailhead) and Fisherman's Village in Marina del Rey (its western end),
        // the two access points the county guide itself calls out first and last.
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000004",
            name: "Ballona Creek Bike Path",
            description: "Los Angeles, CA — a flat, car-free creek path from Syd Kronenthal Park "
                + "in Culver City down to the Marina del Rey harbor at Fisherman's Village.",
            distanceMeters: 10_783,
            elevationGainMeters: 21,
            waypoints: [
                (34.0280, -118.3780),
                (33.9718, -118.4463)
            ]
        ),
        // Distance: TrailLink's official route guide notes Fremont (at Lake Union) sits "5 miles
        // from Golden Gardens Park" along the Burke-Gilman Trail. Elevation is nominal — every
        // source describing this stretch calls it flat/nearly level (it's a former rail
        // right-of-way). Waypoints: Gas Works Park in Fremont, the Ballard (Hiram M. Chittenden)
        // Locks partway along, and Golden Gardens Park at the Puget Sound end.
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000005",
            name: "Burke-Gilman Trail: Fremont to Golden Gardens",
            description: "Seattle, WA — a flat trail from Gas Works Park in Fremont past the "
                + "Ballard Locks, ending at sunset-worthy Golden Gardens Park on Puget Sound.",
            distanceMeters: 8_047,
            elevationGainMeters: 15,
            waypoints: [
                (47.6456, -122.3344),
                (47.66556, -122.39722),
                (47.692379, -122.403359)
            ]
        ),
        // Distance/elevation: AllTrails' GPS-tracked "Ann and Roy Butler Hike-and-Bike Trail"
        // loop, 9.8 mi / 249 ft gain (city sources round this to "the 10-mile Butler Trail loop").
        // Waypoints: Auditorium Shores, the Ann W. Richards Congress Ave Bridge (the bat-colony
        // bridge), Festival Beach, and Lou Neff Point — all real landmarks around the loop.
        makeRoute(
            id: "3F2B9C10-6E4A-4B8E-9C2D-000000000006",
            name: "Ann and Roy Butler Hike-and-Bike Trail Loop",
            description: "Austin, TX — the full loop around Lady Bird Lake, from Auditorium "
                + "Shores across the Congress Ave bat bridge to Festival Beach and Lou Neff Point.",
            distanceMeters: 15_772,
            elevationGainMeters: 76,
            waypoints: [
                (30.2616, -97.7540),
                (30.26126, -97.74531),
                (30.2488, -97.7281),
                (30.26722, -97.76167)
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
