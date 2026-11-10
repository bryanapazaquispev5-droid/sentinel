import Foundation

enum APIClientError: LocalizedError {
    case invalidURL
    case cancelled
    case unauthorized(String)
    case server(String)
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "La URL de la API no es válida."
        case .cancelled: return nil
        case .unauthorized(let message): return message
        case .server(let message): return message
        case .invalidResponse: return "La respuesta de la API no es válida."
        case .network: return "No se pudo conectar con el servidor."
        }
    }
}

struct APIClient {
    // Para el simulador. En producción usa HTTPS y una URL de despliegue.
    static let baseURL = URL(string: "http://127.0.0.1:3000/api/v1/")!

    func request<Response: Decodable, Body: Encodable>(_ path: String, method: String = "GET", body: Body? = nil, token: String? = nil) async throws -> Response {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIClientError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data).error) ?? "Error de servidor"
                if http.statusCode == 401 { throw APIClientError.unauthorized(message) }
                throw APIClientError.server(message)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Response.self, from: data)
        } catch let error as APIClientError { throw error }
        catch let error as URLError where error.code == .cancelled { throw APIClientError.cancelled }
        catch { throw APIClientError.network(error) }
    }

    func request<Response: Decodable>(_ path: String, method: String = "GET", token: String? = nil) async throws -> Response {
        try await request(path, method: method, body: Optional<String>.none, token: token)
    }

    func requestVoid<Body: Encodable>(_ path: String, method: String = "POST", body: Body? = nil, token: String? = nil) async throws {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIClientError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data).error) ?? "Error de servidor"
                if http.statusCode == 401 { throw APIClientError.unauthorized(message) }
                throw APIClientError.server(message)
            }
        } catch let error as APIClientError { throw error }
        catch let error as URLError where error.code == .cancelled { throw APIClientError.cancelled }
        catch { throw APIClientError.network(error) }
    }
}
