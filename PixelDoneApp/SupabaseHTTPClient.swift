import Foundation
import PixelDoneSyncContract

enum SupabaseClientError: LocalizedError, Equatable {
    case invalidResponse
    case requestFailed(status: Int)
    case schemaUpdateRequired(String)
    case attachmentTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The cloud returned an invalid response."
        case let .requestFailed(status):
            "The cloud request failed (HTTP \(status))."
        case let .schemaUpdateRequired(version):
            "PixelDone \(version) or newer is required for this cloud."
        case .attachmentTooLarge:
            "The attachment exceeds the 10 MiB limit."
        }
    }
}

nonisolated private struct SupabaseAuthResponse: Decodable {
    nonisolated struct User: Decodable {
        let id: String
        let email: String?
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: Double
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }

    var session: SupabaseSession {
        SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userID: user.id,
            email: user.email
        )
    }
}

actor SupabaseHTTPClient {
    private let configuration: SupabaseConfiguration
    private let session: URLSession
    private var realtimeTask: URLSessionWebSocketTask?

    init(
        configuration: SupabaseConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func signIn(email: String, password: String) async throws
        -> SupabaseSession {
        let body = ["email": email, "password": password]
        let response: SupabaseAuthResponse = try await send(
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "password")],
            method: "POST",
            body: body,
            accessToken: nil
        )
        return response.session
    }

    func signUp(email: String, password: String) async throws
        -> SupabaseSession {
        let body = ["email": email, "password": password]
        let response: SupabaseAuthResponse = try await send(
            path: "auth/v1/signup",
            method: "POST",
            body: body,
            accessToken: nil
        )
        return response.session
    }

    func refresh(_ refreshToken: String) async throws -> SupabaseSession {
        let response: SupabaseAuthResponse = try await send(
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            body: ["refresh_token": refreshToken],
            accessToken: nil
        )
        return response.session
    }

    func changePassword(
        to newPassword: String,
        session currentSession: SupabaseSession
    ) async throws {
        let _: EmptyResponse = try await send(
            path: "auth/v1/user",
            method: "PUT",
            body: ["password": newPassword],
            accessToken: currentSession.accessToken
        )
    }

    func signOutGlobally(session currentSession: SupabaseSession) async throws {
        let _: EmptyResponse = try await send(
            path: "auth/v1/logout",
            query: [URLQueryItem(name: "scope", value: "global")],
            method: "POST",
            body: EmptyBody(),
            accessToken: currentSession.accessToken
        )
    }

    func pull(
        sinceVersion: Int64,
        session currentSession: SupabaseSession
    ) async throws -> PullChangesResponse {
        let response: PullChangesResponse = try await send(
            path: "rest/v1/rpc/\(PixelDoneSyncContractVersion.pullRPC)",
            method: "POST",
            body: PullChangesParameters(sinceVersion: sinceVersion),
            accessToken: currentSession.accessToken
        )
        try validateSchema(response.schemaVersion)
        return response
    }

    func apply(
        _ mutation: SyncMutation,
        session currentSession: SupabaseSession
    ) async throws -> ApplyMutationResponse {
        let response: ApplyMutationResponse = try await send(
            path: "rest/v1/rpc/\(PixelDoneSyncContractVersion.mutationRPC)",
            method: "POST",
            body: ApplyMutationParameters(mutation: mutation),
            accessToken: currentSession.accessToken
        )
        try validateSchema(response.schemaVersion)
        return response
    }

    func uploadAttachment(
        _ data: Data,
        objectPath: String,
        contentType: String,
        session currentSession: SupabaseSession
    ) async throws {
        guard data.count
                <= PixelDoneSyncContractVersion.attachmentMaximumBytes else {
            throw SupabaseClientError.attachmentTooLarge
        }
        let _: EmptyResponse = try await sendData(
            path:
                "storage/v1/object/\(PixelDoneSyncContractVersion.attachmentBucket)/\(objectPath)",
            method: "POST",
            data: data,
            contentType: contentType,
            accessToken: currentSession.accessToken,
            extraHeaders: ["x-upsert": "true"]
        )
    }

    func downloadAttachment(
        objectPath: String,
        session currentSession: SupabaseSession
    ) async throws -> Data {
        try await sendRaw(
            path:
                "storage/v1/object/authenticated/\(PixelDoneSyncContractVersion.attachmentBucket)/\(objectPath)",
            method: "GET",
            accessToken: currentSession.accessToken
        )
    }

    func deleteAttachment(
        objectPath: String,
        session currentSession: SupabaseSession
    ) async throws {
        let _: EmptyResponse = try await sendData(
            path:
                "storage/v1/object/\(PixelDoneSyncContractVersion.attachmentBucket)/\(objectPath)",
            method: "DELETE",
            data: Data(),
            contentType: "application/octet-stream",
            accessToken: currentSession.accessToken
        )
    }

    func realtimeInvalidations(
        session currentSession: SupabaseSession
    ) -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard var components = configuration.realtimeURL.flatMap({
                        URLComponents(
                            url: $0,
                            resolvingAgainstBaseURL: false
                        )
                    }) else {
                        throw SupabaseClientError.invalidResponse
                    }
                    components.queryItems = [
                        URLQueryItem(
                            name: "apikey",
                            value: configuration.publishableKey
                        ),
                        URLQueryItem(name: "vsn", value: "1.0.0"),
                    ]
                    guard let url = components.url else {
                        throw SupabaseClientError.invalidResponse
                    }
                    var request = URLRequest(url: url)
                    request.setValue(
                        "Bearer \(currentSession.accessToken)",
                        forHTTPHeaderField: "Authorization"
                    )
                    let socket = session.webSocketTask(with: request)
                    realtimeTask = socket
                    socket.resume()

                    let join: [String: Any] = [
                        "topic": "realtime:public:*",
                        "event": "phx_join",
                        "payload": [
                            "config": [
                                "postgres_changes": [[
                                    "event": "*",
                                    "schema": "public",
                                ]],
                            ],
                        ],
                        "ref": "1",
                    ]
                    let joinData = try JSONSerialization.data(
                        withJSONObject: join
                    )
                    try await socket.send(
                        .string(String(decoding: joinData, as: UTF8.self))
                    )

                    while !Task.isCancelled {
                        _ = try await socket.receive()
                        continuation.yield(())
                    }
                    socket.cancel(with: .goingAway, reason: nil)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func stopRealtime() {
        realtimeTask?.cancel(with: .goingAway, reason: nil)
        realtimeTask = nil
    }

    private func validateSchema(_ version: String) throws {
        if case let .updateClient(requiredVersion) =
            SchemaNegotiationResult.evaluate(serverVersion: version) {
            throw SupabaseClientError.schemaUpdateRequired(requiredVersion)
        }
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Body,
        accessToken: String?
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        let responseData = try await sendRaw(
            path: path,
            query: query,
            method: method,
            data: data,
            contentType: "application/json",
            accessToken: accessToken
        )
        if Response.self == EmptyResponse.self, responseData.isEmpty {
            return EmptyResponse() as! Response
        }
        return try JSONDecoder().decode(Response.self, from: responseData)
    }

    private func sendData<Response: Decodable>(
        path: String,
        method: String,
        data: Data,
        contentType: String,
        accessToken: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> Response {
        let responseData = try await sendRaw(
            path: path,
            method: method,
            data: data,
            contentType: contentType,
            accessToken: accessToken,
            extraHeaders: extraHeaders
        )
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        return try JSONDecoder().decode(Response.self, from: responseData)
    }

    private func sendRaw(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        data: Data? = nil,
        contentType: String? = nil,
        accessToken: String?,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else {
            throw SupabaseClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = data
        request.setValue(
            configuration.publishableKey,
            forHTTPHeaderField: "apikey"
        )
        if let accessToken {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (responseData, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SupabaseClientError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SupabaseClientError.requestFailed(
                status: response.statusCode
            )
        }
        return responseData
    }
}

nonisolated private struct EmptyBody: Encodable {}
nonisolated private struct EmptyResponse: Decodable {}
