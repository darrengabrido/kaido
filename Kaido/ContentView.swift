import SwiftUI
import SwiftData
import ImageIO
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RideTogetherDeepLinkRouter.self) private var rideTogetherDeepLinkRouter
    @State private var locationManager = LocationManager()
    @Query private var riderProfiles: [RiderProfile]

    private static let tabIconDiameter: CGFloat = 26

    var body: some View {
        TabView {
            // No .ignoresSafeArea() here — MapboxMapView applies it to the map itself so the
            // tiles run full-bleed, while its overlay controls stay inside the safe area.
            MapboxMapView(locationManager: locationManager)
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            RoutesListView()
                .tabItem {
                    Label("Routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }

            BikeConnectionView()
                .tabItem {
                    Label("Bike", systemImage: "bicycle")
                }

            ProfileView()
                .tabItem {
                    if let photoData = riderProfiles.first?.photoData,
                       let icon = Self.circularTabIcon(from: photoData, diameter: Self.tabIconDiameter) {
                        Label {
                            Text("Profile")
                        } icon: {
                            Image(uiImage: icon)
                                .renderingMode(.original)
                        }
                    } else {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                }
        }
        .task {
            locationManager.requestWhenInUseAuthorization()
            BikeProfileStore.ensureActiveProfile(in: modelContext)
            RiderProfileStore.ensureProfile(in: modelContext)
        }
        .fullScreenCover(isPresented: pendingInviteBinding) {
            if let link = rideTogetherDeepLinkRouter.pendingInvite {
                GroupRideJoinPreviewView(
                    link: link,
                    onJoined: { rideTogetherDeepLinkRouter.clearPendingInvite() },
                    onDismiss: { rideTogetherDeepLinkRouter.clearPendingInvite() }
                )
            }
        }
    }

    private var pendingInviteBinding: Binding<Bool> {
        Binding(
            get: { rideTogetherDeepLinkRouter.pendingInvite != nil },
            set: { isPresented in
                if !isPresented { rideTogetherDeepLinkRouter.clearPendingInvite() }
            }
        )
    }

    /// Tab bar images render as a template mask by default (so the system can tint them for
    /// selection state) — a `.renderingMode(.original)` photo needs to already be exactly the
    /// right size, since a tab item doesn't apply `.resizable()`/`.frame()` the way an inline
    /// `Image` would. `photoData` is already a clean, correctly-framed 320pt square (see
    /// `AvatarCropView`), so this just needs to shrink and circle-clip it, not re-derive any
    /// fill/center-crop math.
    private static func circularTabIcon(from photoData: Data, diameter: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(photoData as CFData, sourceOptions) else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: diameter
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let circularImage = renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: diameter, height: diameter)).addClip()
            UIImage(cgImage: thumbnail).draw(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        }

        // SwiftUI's `.renderingMode(.original)` on the Image view doesn't reliably survive the
        // bridge to UITabBarItem.image — the tab bar still template-renders it (a flat
        // tint-colored circle) unless the UIImage itself is marked always-original at this,
        // more authoritative, UIKit level.
        return circularImage.withRenderingMode(.alwaysOriginal)
    }
}

#Preview {
    ContentView()
        .modelContainer(KaidoModelContainer.shared)
}
