import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !isWorking
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                    Text("GymApp").font(.largeTitle.bold())
                    Text(isSignUp ? "Create an account to save your training to the cloud."
                                  : "Log in to pick up where you left off.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                SignInWithAppleButton(isSignUp ? .signUp : .signIn) { request in
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await auth.handleAppleResult(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)

                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    Text("or").font(.footnote).foregroundStyle(.secondary)
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                }

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(isSignUp ? "Password (6+ characters)" : "Password", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                }
                .padding(14)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    Task {
                        isWorking = true
                        if isSignUp { await auth.signUp(email: email, password: password) }
                        else { await auth.signIn(email: email, password: password) }
                        isWorking = false
                    }
                } label: {
                    Group {
                        if isWorking { ProgressView() } else { Text(isSignUp ? "Create account" : "Log in") }
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                if let error = auth.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                if let info = auth.infoMessage {
                    Text(info).font(.footnote).foregroundStyle(.green).multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button(isSignUp ? "Already have an account? Log in" : "New here? Create an account") {
                        isSignUp.toggle()
                        auth.errorMessage = nil
                        auth.infoMessage = nil
                    }
                    if !isSignUp {
                        Button("Forgot password?") { Task { await auth.resetPassword(email: email) } }
                            .disabled(!email.contains("@"))
                    }
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
