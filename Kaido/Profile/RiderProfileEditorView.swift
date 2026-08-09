import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct RiderProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let profile: RiderProfile

    @State private var displayName: String
    @State private var homeCity: String
    @State private var bio: String
    @State private var experienceLevel: RiderExperienceLevel
    @State private var photoImage: UIImage?
    @State private var photoChanged = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var saveError: String?

    private static let avatarSize: CGFloat = 88
    private static let maxPhotoDimension: CGFloat = 320
    private static let jpegQuality: CGFloat = 0.85

    init(profile: RiderProfile) {
        self.profile = profile
        _displayName = State(initialValue: profile.displayName)
        _homeCity = State(initialValue: profile.homeCity)
        _bio = State(initialValue: profile.bio)
        _experienceLevel = State(initialValue: profile.experienceLevel)
        _photoImage = State(initialValue: profile.photoData.flatMap(UIImage.init(data:)))
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    photoPicker
                    Spacer()
                }
                .listRowBackground(Color.clear)

                if photoImage != nil {
                    HStack {
                        Spacer()
                        Button("Remove Photo", role: .destructive) {
                            photoImage = nil
                            selectedPhotoItem = nil
                            photoChanged = true
                        }
                        .font(.subheadline)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
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
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            isLoadingPhoto = true
            Task {
                defer { isLoadingPhoto = false }
                guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                let resized = await Task.detached(priority: .userInitiated) {
                    Self.downsampledImage(from: data, maxDimensionInPixels: Self.maxPhotoDimension)
                }.value
                guard let resized else { return }
                photoImage = resized
                photoChanged = true
            }
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                RiderAvatarView(displayName: displayName, photoImage: photoImage, size: Self.avatarSize)
                if isLoadingPhoto {
                    ProgressView()
                        .tint(.white)
                        .frame(width: Self.avatarSize, height: Self.avatarSize)
                        .background { Circle().fill(Color.black.opacity(0.35)) }
                } else {
                    editBadge
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoadingPhoto)
        .accessibilityLabel(photoImage == nil ? "Add profile photo" : "Change profile photo")
        .accessibilityHint("Opens your photo library")
    }

    private var editBadge: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background { Circle().fill(Color.kaidoViolet) }
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        profile.displayName = trimmedDisplayName
        profile.homeCity = homeCity.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.experienceLevel = experienceLevel
        if photoChanged {
            profile.photoData = photoImage?.jpegData(compressionQuality: Self.jpegQuality)
        }
        profile.updatedAt = Date()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Decodes straight to a small thumbnail via ImageIO instead of materializing the picked
    /// photo's full-resolution bitmap first — a library photo can be dozens of megapixels, and this
    /// keeps a one-time, user-initiated pick cheap regardless of the original's size. A plain
    /// `static func` (no `self`) so it's safe to call from `Task.detached` off the main actor
    /// without capturing the view.
    private static func downsampledImage(from data: Data, maxDimensionInPixels: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}

struct RiderAvatarView: View {
    let displayName: String
    var photoImage: UIImage? = nil
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            if let photoImage {
                Image(uiImage: photoImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.kaidoViolet.gradient)
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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
