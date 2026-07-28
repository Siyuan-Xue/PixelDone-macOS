@testable import PixelDone
import Foundation
import PixelDoneSyncContract
import Testing

@Suite("Native Supabase transport")
struct SupabaseHTTPClientTests {
    @Test("Image normalization produces a bounded JPEG and SHA-256")
    func attachmentNormalizationFixture() async throws {
        let source = try #require(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        let normalized = try await PixelDoneAttachmentService().normalize(
            source
        )

        #expect(normalized.contentType == "image/jpeg")
        #expect(normalized.byteSize == Int64(normalized.data.count))
        #expect(normalized.contentSHA256.count == 64)
        #expect(
            normalized.data.count
                <= PixelDoneSyncContractVersion.attachmentMaximumBytes
        )
    }

    @Test("HTTP derives ws, decodes Auth, and sends the flat 3.2 RPC")
    func signInFixture() async throws {
        let configuration = try #require(
            SupabaseConfiguration(
                baseURLString: "http://127.0.0.1:54321",
                publishableKey: "fixture-key"
            )
        )
        #expect(configuration.realtimeURL?.scheme == "ws")

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: sessionConfiguration)
        URLProtocolStub.handler = { request in
            #expect(request.url?.path == "/auth/v1/token")
            #expect(
                URLComponents(
                    url: try #require(request.url),
                    resolvingAgainstBaseURL: false
                )?.queryItems?.contains(
                    URLQueryItem(name: "grant_type", value: "password")
                ) == true
            )
            let data = Data(
                """
                {
                  "access_token": "fixture-access",
                  "refresh_token": "fixture-refresh",
                  "expires_in": 3600,
                  "user": {
                    "id": "00000000-0000-0000-0000-000000000001",
                    "email": "fixture@example.com"
                  }
                }
                """.utf8
            )
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                data
            )
        }

        let client = SupabaseHTTPClient(
            configuration: configuration,
            session: session
        )
        let auth = try await client.signIn(
            email: "fixture@example.com",
            password: "fixture-password"
        )
        #expect(auth.userID == "00000000-0000-0000-0000-000000000001")
        #expect(auth.email == "fixture@example.com")

        URLProtocolStub.handler = { request in
            #expect(
                request.url?.path
                    == "/rest/v1/rpc/pixeldone_apply_mutation"
            )
            let body = try request.fixtureBodyData()
            let object = try #require(
                JSONSerialization.jsonObject(with: body)
                    as? [String: Any]
            )
            #expect(object["p_client_schema_version"] as? String == "3.2")
            #expect(object["p_mutation_uuid"] as? String == "fixture-mutation")
            #expect(object["p_mutation"] == nil)
            let data = Data(
                """
                {
                  "schema_version": "3.2",
                  "accepted": {
                    "checklists": [],
                    "items": [],
                    "attachments": []
                  },
                  "settings": null,
                  "tombstones": [],
                  "conflicts": [],
                  "server_version": 1,
                  "image_cleanup_paths": []
                }
                """.utf8
            )
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                data
            )
        }
        let response = try await client.apply(
            SyncMutation(
                mutationUUID: "fixture-mutation",
                snapshot: RemoteSnapshot(
                    checklists: [],
                    items: [],
                    attachments: []
                )
            ),
            session: auth
        )
        #expect(response.serverVersion == 1)
    }
}

nonisolated private final class URLProtocolStub:
    URLProtocol,
    @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

nonisolated private extension URLRequest {
    func fixtureBodyData() throws -> Data {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            throw URLError(.cannotDecodeContentData)
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: bufferSize
        )
        defer { buffer.deallocate() }

        while true {
            let count = httpBodyStream.read(
                buffer,
                maxLength: bufferSize
            )
            if count < 0 {
                throw httpBodyStream.streamError
                    ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
