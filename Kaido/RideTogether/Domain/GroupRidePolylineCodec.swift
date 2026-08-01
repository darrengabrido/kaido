import CoreLocation

/// Google/Mapbox-compatible encoded polyline (precision 1e5), used only to compactly store
/// `GroupRideRouteSnapshot.encodedPolyline` — never to parse or retain a live Mapbox SDK object.
enum GroupRidePolylineCodec {
    static func encode(_ coordinates: [CLLocationCoordinate2D], precision: Double = 1e5) -> String {
        var lastLat = 0
        var lastLng = 0
        var bytes: [UInt8] = []
        for coordinate in coordinates {
            let lat = Int((coordinate.latitude * precision).rounded())
            let lng = Int((coordinate.longitude * precision).rounded())
            bytes += encodeValue(lat - lastLat)
            bytes += encodeValue(lng - lastLng)
            lastLat = lat
            lastLng = lng
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func decode(_ polyline: String, precision: Double = 1e5) -> [CLLocationCoordinate2D] {
        let bytes = Array(polyline.utf8)
        var coordinates: [CLLocationCoordinate2D] = []
        var index = 0
        var lat = 0
        var lng = 0
        while index < bytes.count {
            guard let latDelta = decodeValue(bytes, &index) else { break }
            guard let lngDelta = decodeValue(bytes, &index) else { break }
            lat += latDelta
            lng += lngDelta
            coordinates.append(
                CLLocationCoordinate2D(latitude: Double(lat) / precision, longitude: Double(lng) / precision)
            )
        }
        return coordinates
    }

    private static func encodeValue(_ value: Int) -> [UInt8] {
        var v = value << 1
        if value < 0 { v = ~v }
        var bytes: [UInt8] = []
        while v >= 0x20 {
            bytes.append(UInt8((0x20 | (v & 0x1f)) + 63))
            v >>= 5
        }
        bytes.append(UInt8(v + 63))
        return bytes
    }

    private static func decodeValue(_ bytes: [UInt8], _ index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        while index < bytes.count {
            let byte = Int(bytes[index]) - 63
            index += 1
            result |= (byte & 0x1f) << shift
            shift += 5
            if byte < 0x20 {
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
        }
        return nil
    }
}
