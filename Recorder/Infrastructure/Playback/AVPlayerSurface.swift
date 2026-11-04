import AVKit
import SwiftUI

/// Renders the playback service's video with AVKit. The aspect ratio is kept and the rest letterboxed in black. The
/// Viewer draws its own controls, and `App` injects this view so that Presentation stays free of AVFoundation types.
struct AVPlayerSurface: NSViewRepresentable {
    let service: AVPlaybackService

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        view.allowsVideoFrameAnalysis = false
        // Nothing here answers the system's media commands, so playback should not be offered to them.
        view.updatesNowPlayingInfoCenter = false
        view.player = service.player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}
