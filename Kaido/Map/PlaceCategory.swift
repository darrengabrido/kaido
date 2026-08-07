import Foundation

/// Coarse grouping of Mapbox's raw "maki" POI categories, used to power category filter pills
/// in the search results card and to bucket which map pins a pill shows/hides.
enum PlaceCategory: String, CaseIterable, Identifiable, Hashable {
    case coffee, food, drinks, shopping, fuel, lodging, cycling
    case finance, health, park, education, fitness, entertainment
    case parking, transit, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coffee: "Coffee"
        case .food: "Food"
        case .drinks: "Drinks"
        case .shopping: "Shops"
        case .fuel: "Fuel"
        case .lodging: "Lodging"
        case .cycling: "Cycling"
        case .finance: "Banking"
        case .health: "Health"
        case .park: "Parks"
        case .education: "Education"
        case .fitness: "Fitness"
        case .entertainment: "Entertainment"
        case .parking: "Parking"
        case .transit: "Transit"
        case .other: "Other"
        }
    }

    /// Representative icon for a whole bucket — used by category pills. Individual result rows
    /// use their own finer-grained icon from `categorize(maki:isPOI:)` instead, since a bucket
    /// like `.transit` spans several distinct maki values (airport, rail, bus).
    var iconName: String {
        switch self {
        case .coffee: "cup.and.saucer.fill"
        case .food: "fork.knife"
        case .drinks: "wineglass.fill"
        case .shopping: "cart.fill"
        case .fuel: "fuelpump.fill"
        case .lodging: "bed.double.fill"
        case .cycling: "bicycle"
        case .finance: "banknote.fill"
        case .health: "cross.fill"
        case .park: "tree.fill"
        case .education: "graduationcap.fill"
        case .fitness: "figure.run"
        case .entertainment: "film.fill"
        case .parking: "parkingsign"
        case .transit: "tram.fill"
        case .other: "mappin.circle.fill"
        }
    }

    /// Single source of truth for turning a Mapbox "maki" icon identifier into both the
    /// fine-grained SF Symbol a result row displays and the coarse category it buckets into.
    static func categorize(maki: String?, isPOI: Bool) -> (iconName: String, category: PlaceCategory) {
        guard let maki else {
            return (isPOI ? "mappin.circle.fill" : "location.circle.fill", .other)
        }
        switch maki {
        case "cafe", "coffee": return ("cup.and.saucer.fill", .coffee)
        case "restaurant", "restaurant-pizza", "fast-food": return ("fork.knife", .food)
        case "bar", "beer", "alcohol-shop": return ("wineglass.fill", .drinks)
        case "grocery", "shop": return ("cart.fill", .shopping)
        case "fuel", "charging-station": return ("fuelpump.fill", .fuel)
        case "lodging": return ("bed.double.fill", .lodging)
        case "bicycle", "bicycle-share": return ("bicycle", .cycling)
        case "bank": return ("banknote.fill", .finance)
        case "hospital", "pharmacy", "doctor": return ("cross.fill", .health)
        case "park", "garden": return ("tree.fill", .park)
        case "school", "college": return ("graduationcap.fill", .education)
        case "fitness-centre", "gym": return ("figure.run", .fitness)
        case "cinema", "theatre": return ("film.fill", .entertainment)
        case "parking": return ("parkingsign", .parking)
        case "airport", "airfield": return ("airplane", .transit)
        case "rail", "rail-metro", "bus": return ("tram.fill", .transit)
        default: return (isPOI ? "mappin.circle.fill" : "location.circle.fill", .other)
        }
    }

    /// Fallback for call sites that only kept the resolved icon (`POIRecommendation`,
    /// `SavedPlace`) rather than the original maki value.
    init(iconName: String) {
        switch iconName {
        case "cup.and.saucer.fill": self = .coffee
        case "fork.knife": self = .food
        case "wineglass.fill": self = .drinks
        case "cart.fill": self = .shopping
        case "fuelpump.fill": self = .fuel
        case "bed.double.fill": self = .lodging
        case "bicycle": self = .cycling
        case "banknote.fill": self = .finance
        case "cross.fill": self = .health
        case "tree.fill": self = .park
        case "graduationcap.fill": self = .education
        case "figure.run": self = .fitness
        case "film.fill": self = .entertainment
        case "parkingsign": self = .parking
        case "airplane", "tram.fill": self = .transit
        default: self = .other
        }
    }
}

/// How many current results fall into a category — the data behind a single category pill.
struct PlaceCategoryTally: Identifiable, Hashable {
    let category: PlaceCategory
    let count: Int
    var id: PlaceCategory { category }
}
