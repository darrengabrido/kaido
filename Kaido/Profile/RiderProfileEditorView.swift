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
    @State private var ridePurpose: RidePurpose?
    @State private var selectedInterestTags: Set<InterestTag>
    @State private var photoImage: UIImage?
    @State private var photoChanged = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var imageBeingCropped: UIImage?
    @State private var isShowingPhotoOptions = false
    @State private var isPresentingPhotoPicker = false
    @State private var saveError: String?

    private static let avatarSize: CGFloat = 88
    private static let workingImageDimension: CGFloat = 1024
    private static let jpegQuality: CGFloat = 0.85

    init(profile: RiderProfile) {
        self.profile = profile
        _displayName = State(initialValue: profile.displayName)
        _homeCity = State(initialValue: profile.homeCity)
        _bio = State(initialValue: profile.bio)
        _experienceLevel = State(initialValue: profile.experienceLevel)
        _ridePurpose = State(initialValue: profile.ridePurpose)
        _selectedInterestTags = State(initialValue: Set(profile.interestTags))
        _photoImage = State(initialValue: profile.photoData.flatMap(UIImage.init(data:)))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                youCard
                ridingStyleCard
            }
            .padding()
        }
        .background(Color.kaidoMidnight)
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
                let decoded = await Task.detached(priority: .userInitiated) {
                    Self.downsampledImage(from: data, maxDimensionInPixels: Self.workingImageDimension)
                }.value
                guard let decoded else { return }
                imageBeingCropped = decoded
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { imageBeingCropped != nil },
                set: { if !$0 { imageBeingCropped = nil } }
            )
        ) {
            if let imageBeingCropped {
                AvatarCropView(
                    image: imageBeingCropped,
                    onCancel: {
                        self.imageBeingCropped = nil
                        selectedPhotoItem = nil
                    },
                    onConfirm: { cropped in
                        photoImage = cropped
                        photoChanged = true
                        self.imageBeingCropped = nil
                        selectedPhotoItem = nil
                    }
                )
            }
        }
    }

    // MARK: - Cards

    private var youCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("You", systemImage: "person.crop.circle")
                .font(.headline)
                .foregroundStyle(Color.kaidoInk)

            VStack(spacing: 10) {
                photoPicker
                if photoImage != nil {
                    Button("Remove Photo", role: .destructive) {
                        photoImage = nil
                        selectedPhotoItem = nil
                        photoChanged = true
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity)

            field("Display name") {
                TextField("", text: $displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .onChange(of: displayName) { _, value in
                        displayName = String(value.prefix(50))
                    }
            }

            field("Home city") {
                TextField("", text: $homeCity)
                    .textContentType(.addressCity)
                    .textInputAutocapitalization(.words)
                    .onChange(of: homeCity) { _, value in
                        homeCity = String(value.prefix(80))
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                field("About your riding") {
                    TextField("", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.sentences)
                        .onChange(of: bio) { _, value in
                            bio = String(value.prefix(180))
                        }
                }
                HStack {
                    Spacer()
                    Text("\(bio.count)/180")
                        .font(.caption2)
                        .foregroundStyle(Color.kaidoDim)
                }
            }
        }
        .profileCard()
    }

    private var ridingStyleCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Riding style", systemImage: "bicycle")
                .font(.headline)
                .foregroundStyle(Color.kaidoInk)

            VStack(alignment: .leading, spacing: 8) {
                Text("Experience")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.kaidoDim)
                FlowLayout(spacing: 8) {
                    ForEach(RiderExperienceLevel.allCases) { level in
                        SelectableChip(
                            title: level.title,
                            systemImage: level.systemImage,
                            isSelected: experienceLevel == level
                        ) {
                            experienceLevel = level
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Ride purpose")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.kaidoDim)
                FlowLayout(spacing: 8) {
                    SelectableChip(
                        title: "Not set",
                        systemImage: "circle.dashed",
                        isSelected: ridePurpose == nil
                    ) {
                        ridePurpose = nil
                    }
                    ForEach(RidePurpose.allCases) { purpose in
                        SelectableChip(
                            title: purpose.title,
                            systemImage: purpose.systemImage,
                            isSelected: ridePurpose == purpose
                        ) {
                            ridePurpose = purpose
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What are you into?")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.kaidoDim)
                FlowLayout(spacing: 8) {
                    ForEach(InterestTag.allCases) { tag in
                        SelectableChip(
                            title: tag.title,
                            systemImage: tag.systemImage,
                            isSelected: selectedInterestTags.contains(tag)
                        ) {
                            if selectedInterestTags.contains(tag) {
                                selectedInterestTags.remove(tag)
                            } else {
                                selectedInterestTags.insert(tag)
                            }
                        }
                    }
                }
                Text("Helps tailor the stops Discover suggests during free rides.")
                    .font(.caption2)
                    .foregroundStyle(Color.kaidoDim)
            }
        }
        .profileCard()
    }

    private var photoPicker: some View {
        Button {
            if photoImage != nil {
                isShowingPhotoOptions = true
            } else {
                isPresentingPhotoPicker = true
            }
        } label: {
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
        .accessibilityHint(photoImage == nil ? "Opens your photo library" : "Edit or replace your profile photo")
        .confirmationDialog("Profile Photo", isPresented: $isShowingPhotoOptions, titleVisibility: .visible) {
            Button("Edit Photo") {
                imageBeingCropped = photoImage
            }
            Button("Choose New Photo") {
                isPresentingPhotoPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $isPresentingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
    }

    /// A labeled field container matching the app's capsule/card token set — outside `Form`,
    /// text fields otherwise have no visual container of their own.
    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.kaidoDim)
            content()
                .foregroundStyle(Color.kaidoInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.kaidoInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
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
        profile.ridePurpose = ridePurpose
        profile.interestTags = InterestTag.allCases.filter { selectedInterestTags.contains($0) }
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

/// A single tappable pill used for both single-select (experience, ride purpose) and multi-select
/// (interest tags) choices. Content-hugging by design — never `.frame(maxWidth: .infinity)` — so
/// it always renders as a true capsule regardless of label length; wrap it in `FlowLayout` to let
/// variable-width chips wrap onto new rows instead of stretching or clipping.
private struct SelectableChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : Color.kaidoInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.kaidoViolet : Color.kaidoInk.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Wraps content onto new rows instead of stretching or truncating it, for rows of
/// variable-width, content-hugging chips (`SelectableChip`) where a fixed-column grid would
/// distort labels of different lengths.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + (x > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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
