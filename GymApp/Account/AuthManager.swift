import Foundation
import Observation
import Supabase
import AuthenticationServices
import CryptoKit

@MainActor
@Observable
final class AuthManager {
    private let client = SupabaseConfig.client
    private(set) var session: Session?
    private(set) var isLoading = true
    var errorMessage: String?
    var infoMessage: String?

    var userID: UUID? { session?.user.id }
    var email: String? { session?.user.email }

    /// Listens for sign-in / sign-out for the lifetime of the app.
    func start() async {
        for await (_, session) in client.auth.authStateChanges {
            self.session = session
            isLoading = false
        }
    }

    func signUp(email: String, password: String) async {
        await run {
            let response = try await self.client.auth.signUp(email: email, password: password)
            if response.session == nil {
                self.infoMessage = "Check your email for a link to confirm your account, then log in."
            }
        }
    }

    func signIn(email: String, password: String) async {
        await run { try await self.client.auth.signIn(email: email, password: password) }
    }

    func resetPassword(email: String) async {
        await run {
            try await self.client.auth.resetPasswordForEmail(email)
            self.infoMessage = "If an account exists for \(email), a reset link is on its way."
        }
    }

    // MARK: Sign in with Apple

    private var currentNonce: String?

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = error.localizedDescription }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "Apple sign-in didn't return a valid token."
                return
            }
            await run {
                try await self.client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
            }
        }
    }

    // MARK: Account

    func signOut() async {
        try? await client.auth.signOut()
        session = nil
    }

    /// Permanently deletes the account and all cloud data (via the delete_user SQL function).
    func deleteAccount() async -> Bool {
        do {
            try await client.rpc("delete_user").execute()
            try? await client.auth.signOut(scope: .local)
            session = nil
            return true
        } catch {
            errorMessage = "Couldn't delete account: \(error.localizedDescription)"
            return false
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        errorMessage = nil
        infoMessage = nil
        do { try await work() } catch { errorMessage = error.localizedDescription }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }
}
