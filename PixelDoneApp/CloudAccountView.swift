import SwiftUI

struct CloudAccountView: View {
    @Bindable var store: PixelDoneStore
    @State private var email = ""
    @State private var password = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var registerMode = false
    @State private var changingPassword = false
    @State private var reviewingConflicts = false

    var body: some View {
        Group {
            if !store.cloud.isConfigured {
                Text("cloud_local_only_detail")
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if let session = store.cloud.session {
                LabeledContent(
                    "account",
                    value: session.email ?? session.userID
                )
                Button(
                    "sync_now",
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    Task { await store.synchronizeCloud() }
                }
                .disabled(store.isWorking)

                if !store.cloud.conflicts.isEmpty {
                    Button {
                        reviewingConflicts = true
                    } label: {
                        Label(
                            "review",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                    .tint(.orange)
                }

                Button("change_password") {
                    changingPassword = true
                }
                Button("sign_out", role: .destructive) {
                    Task { await store.cloud.signOut() }
                }
            } else {
                Picker("cloud", selection: $registerMode) {
                    Text("sign_in").tag(false)
                    Text("sign_up").tag(true)
                }
                .pickerStyle(.segmented)

                TextField("email", text: $email)
                SecureField("password", text: $password)

                if registerMode {
                    Button("sign_up") {
                        authenticate()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.pixelDoneClay)
                } else {
                    Button("sign_in") {
                        authenticate()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.pixelDoneClay)
                }
            }

            if let error = store.cloud.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $changingPassword) {
            VStack(alignment: .leading, spacing: 16) {
                Text("change_password")
                    .font(.title2.bold())
                SecureField(
                    "current_password",
                    text: $currentPassword
                )
                SecureField("new_password", text: $newPassword)
                HStack {
                    Spacer()
                    Button("cancel") {
                        changingPassword = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("change") {
                        changePassword()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.pixelDoneClay)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        currentPassword.isEmpty || newPassword.isEmpty
                    )
                }
            }
            .padding(24)
            .frame(width: 420)
        }
        .sheet(isPresented: $reviewingConflicts) {
            ConflictReviewView(
                store: store,
                isPresented: $reviewingConflicts
            )
        }
    }

    private func authenticate() {
        Task {
            if registerMode {
                await store.cloud.register(email: email, password: password)
            } else {
                await store.cloud.signIn(email: email, password: password)
            }
            password = ""
        }
    }

    private func changePassword() {
        let current = currentPassword
        let new = newPassword
        currentPassword = ""
        newPassword = ""
        changingPassword = false
        Task {
            await store.cloud.changePassword(
                currentPassword: current,
                newPassword: new
            )
        }
    }
}

private struct ConflictReviewView: View {
    @Bindable var store: PixelDoneStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("sync_conflicts")
                    .font(.title2.bold())
                Spacer()
                Button("close", systemImage: "xmark") {
                    isPresented = false
                }
                .labelStyle(.iconOnly)
            }

            List(store.cloud.conflicts) { conflict in
                VStack(alignment: .leading, spacing: 6) {
                    Text(conflict.recordType.uppercased())
                        .font(.caption.weight(.black))
                        .foregroundStyle(.orange)
                    Text(conflict.localID)
                        .font(.body.monospaced())
                    Text(conflict.message.replacingOccurrences(
                        of: "_",
                        with: " "
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            GlassEffectContainer {
                HStack {
                    Spacer()
                    Button("keep_cloud") {
                        resolve(keepingDevice: false)
                    }
                    .buttonStyle(.glass)
                    Button("keep_local") {
                        resolve(keepingDevice: true)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.pixelDoneClay)
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 440)
    }

    private func resolve(keepingDevice: Bool) {
        Task {
            await store.resolveCloudConflicts(
                keepingDevice: keepingDevice
            )
            if store.cloud.conflicts.isEmpty {
                isPresented = false
            }
        }
    }
}
