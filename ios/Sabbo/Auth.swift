import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum Vault {
  static let service = (Bundle.main.bundleIdentifier ?? "dev.crosscourt.sabbo.example") + ".session"
  static func save(_ data: Data) throws {
    clear()
    let result = SecItemAdd(
      [
        kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "session",
        kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      ] as CFDictionary, nil)
    if result != errSecSuccess { throw NSError(domain: "Keychain", code: Int(result)) }
  }
  static func read() -> Data? {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(
      [
        kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "session",
        kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
      ] as CFDictionary, &result)
    return status == errSecSuccess ? result as? Data : nil
  }
  static func clear() {
    SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary)
  }
}
struct Session: Codable {
  let token: String
  let user_id: String
}
@MainActor final class SignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
  var session: ASWebAuthenticationSession?
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
      .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
  }
  static func random() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw NSError(domain: "Sabbo", code: 1)
    }
    return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
  func login(api: API) async throws -> Session {
    let config: AuthConfig = try await api.get("/auth/config")
    let verifier = try Self.random()
    let state = try Self.random()
    let nonce = try Self.random()
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    var parts = URLComponents(string: config.authorization_endpoint)!
    parts.queryItems = [
      "client_id": config.client_id, "redirect_uri": config.redirect_uri, "response_type": "code",
      "scope": "openid profile", "state": state, "nonce": nonce, "code_challenge": challenge,
      "code_challenge_method": "S256",
    ].map { URLQueryItem(name: $0.key, value: $0.value) }
    let callback: URL = try await withCheckedThrowingContinuation { continuation in
      session = ASWebAuthenticationSession(url: parts.url!, callbackURLScheme: Bundle.main.bundleIdentifier) {
        url, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let url {
          continuation.resume(returning: url)
        } else {
          continuation.resume(throwing: URLError(.badServerResponse))
        }
      }
      session?.presentationContextProvider = self
      session?.prefersEphemeralWebBrowserSession = false
      if session?.start() != true {
        continuation.resume(throwing: URLError(.cannotLoadFromNetwork))
      }
    }
    let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard callback.scheme == Bundle.main.bundleIdentifier, callback.path == "/oauth/callback",
      query.first(where: { $0.name == "state" })?.value == state,
      let code = query.first(where: { $0.name == "code" })?.value
    else { throw URLError(.userAuthenticationRequired) }
    let result: AuthResult = try await api.send(
      "/auth/exchange", body: ["code": code, "verifier": verifier, "nonce": nonce])
    let saved = Session(token: result.token, user_id: result.user_id)
    try Vault.save(JSONEncoder().encode(saved))
    return saved
  }
}
struct API {
  let base: URL
  var token: String?
  var transport = URLSession.shared
  init(base: URL, token: String?, transport: URLSession) {
    self.base = base; self.token = token; self.transport = transport
  }
  init(token: String? = nil) {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "SabboAPIURL") as? String,
      let url = URL(string: raw), url.scheme == "https", url.host != nil
    else { fatalError("SabboAPIURL must be an HTTPS URL") }
    base = url
    self.token = token
  }
  func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil)
    async throws -> T
  {
    guard let url = URL(string: path, relativeTo: base)?.absoluteURL,
      url.host == base.host, url.scheme == base.scheme else { throw URLError(.badURL) }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = method
    if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await transport.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    if http.statusCode == 401 { throw URLError(.userAuthenticationRequired) }
    guard (200..<300).contains(http.statusCode) else {
      let detail =
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
      throw NSError(
        domain: "Sabbo", code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: detail ?? "Kunne ikke lagre. Prøv igjen."])
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
  func get<T: Decodable>(_ path: String) async throws -> T { try await request(path) }
  func send<T: Decodable>(_ path: String, method: String = "POST", body: [String: Any]) async throws
    -> T
  { try await request(path, method: method, body: body) }
}
