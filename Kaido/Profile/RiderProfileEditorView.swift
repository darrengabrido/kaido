import SwiftData
import SwiftUI

struct RiderProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let profile: RiderProfile

    @State private var displayName: String
    @State private var homeCity: String
    @State private var bio: String
    @State private var experienceLevel: RiderExperienceLevel
    @State private var saveError: String?

    init(profile: RiderProfile) {
        self.profile = profile
        _displayName = State(initialValue: profile.displayName)
        _homeCity = State(initialValue: profile.homeCity)
        _bio = State(initialValue: profile.bio)
        _experienceLevel = State(initialValue: profile.experienceLevel)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    RiderAvatarView(displayName: displayName, size: 88)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("About you") {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .onChange(of: displayName) { _, value in
                        displayName = String(value.prefix(50))
                    }

                TextField("Home city", text: $homeCity)
                    .textContentType(.addressCity)
                    .textInputAutocapitalization(.words)
                    .onChange(of: homeCity) { _, value in
                        homeCity = String(value.prefix(80))
                    }

                TextField("A little about your riding", text: $bio, axis: .vertical)
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.sentences)
                    .onChange(of: bio) { _, value in
                        bio = String(value.prefix(180))
                    }

                HStack {
                    Spacer()
                    Text("\(bio.count)/180")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Riding experience") {
                Picker("Experience", selection: $experienceLevel) {
                    ForEach(RiderExperienceLevel.allCases) { level in
                        Label(level.title, systemImage: level.systemImage)
                            .tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle(profile.displayName.isEmpty ? "Add Profile" : "Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(trimmedDisplayName.isEmpty)
            }
        }
        .alert(
            "Couldn't Save Profile",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        profile.displayName = trimmedDisplayName
        profile.homeCity = homeCity.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.experienceLevel = experienceLevel
        profile.updatedAt = Date()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

struct RiderAvatarView: View {
    let displayName: String
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.kaidoViolet.gradient)
            Text(initials)
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayName.isEmpty ? "Profile avatar" : "\(displayName) profile avatar")
    }

    private var initials: String {
        let words = displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined().uppercased()
        return value.isEmpty ? "K" : value
    }
}
