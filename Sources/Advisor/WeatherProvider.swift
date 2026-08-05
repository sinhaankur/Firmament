import Foundation
import CoreLocation

/// Fetches current sky-relevant weather for the observer. Uses Open-Meteo — a
/// free, keyless, no-account API — so there's nothing to sign up for and no
/// tracking token. Only the coarse lat/lon is sent, and only when the user is in
/// Capture mode; it's an optional enhancement, not required for the app to work.
///
/// If the network is unavailable the advisor simply runs on the astronomical
/// facts it already has (Moon, darkness) — it never blocks capture.
///
/// © Ankur Sinha. Custom code, no third-party dependencies.
struct WeatherProvider {

    struct Reading {
        let cloudCover: Double?     // 0…1
        let humidity: Double?       // 0…1
        let windSpeed: Double?      // m/s
        let temperatureC: Double?
    }

    /// Fetch current conditions. Returns nil on any failure (advisor degrades).
    func fetch(for coordinate: CLLocationCoordinate2D) async -> Reading? {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(coordinate.latitude)),
            .init(name: "longitude", value: String(coordinate.longitude)),
            .init(name: "current", value: "cloud_cover,relative_humidity_2m,wind_speed_10m,temperature_2m"),
            .init(name: "wind_speed_unit", value: "ms"),
        ]
        guard let url = comps.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let c = decoded.current
            return Reading(
                cloudCover: c.cloud_cover.map { $0 / 100.0 },
                humidity: c.relative_humidity_2m.map { $0 / 100.0 },
                windSpeed: c.wind_speed_10m,
                temperatureC: c.temperature_2m
            )
        } catch {
            return nil
        }
    }

    private struct OpenMeteoResponse: Decodable {
        let current: Current
        struct Current: Decodable {
            let cloud_cover: Double?
            let relative_humidity_2m: Double?
            let wind_speed_10m: Double?
            let temperature_2m: Double?
        }
    }
}
