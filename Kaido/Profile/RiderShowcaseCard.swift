import SwiftUI
import UIKit

/// The Profile tab's hero card — mirrors ``BikeShowcaseCard``'s treatment (28pt gradient card,
/// hairline violet stroke) for the rider's own identity rather than the bike's. There's no
/// illustration and only one action (edit), so this stays a single discrete affordance rather
/// than a segmented action row.
struct RiderShowcaseCard: View {
    let profile: RiderProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                RiderAvatarView(
                    displayName: profile.displayName,
                    photoImage: profile.photoData.flatMap(UIImage.init(data:)),
                    size: 64
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName.isEmpty ? "Add your profile" : profile.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.kaidoInk)
                        .lineLimit(1)

                    if profile.displayName.isEmpty {
                        Text("Tell Kaido a little about you")
                            .font(.subheadline)
                            .foregroundStyle(Color.kaidoDim)
                            .lineLimit(1)
                    } else {
                        Label(subtitleText, systemImage: profile.experienceLevel.systemImage)
                            .font(.subheadline)
                            .foregroundStyle(Color.kaidoDim)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                editLink
            }

            Text("Your profile works whether you sign in or continue as a guest.")
                .font(.caption2)
                .foregroundStyle(Color.kaidoDim)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.kaidoIndigo.opacity(0.58),
                            Color.kaidoMidnight.opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.kaidoViolet.opacity(0.2), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            profile.displayName.isEmpty
                ? "Rider profile, not set up yet"
                : "\(profile.displayName), \(subtitleText)"
        )
    }

    private var subtitleText: String {
        profile.homeCity.isEmpty
            ? profile.experienceLevel.title
            : "\(profile.homeCity) · \(profile.experienceLevel.title)"
    }

    private var editLink: some View {
        NavigationLink {
            RiderProfileEditorView(profile: profile)
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.kaidoInk)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.displayName.isEmpty ? "Add profile" : "Edit profile")
    }
}
