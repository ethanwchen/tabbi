import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

/// The screenshots that will go with the next question, above the text in
/// the question field. Each one can be taken off on hover.
struct PendingAttachments: View {
    @ObservedObject var session: ClaudeAskSession

    var body: some View {
        if !session.pendingAttachments.isEmpty || session.captureFailed {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(session.pendingAttachments) { attachment in
                    PendingThumbnail(image: session.thumbnail(for: attachment), attachment: attachment) {
                        session.removePending(attachment)
                    }
                    .transition(.motionPop)
                }
                if session.captureFailed {
                    Label("Couldn't take a screenshot. Try again.", systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .motion(Theme.Motion.snappy, value: session.pendingAttachments.map(\.id))
            .motion(Theme.Motion.snappy, value: session.captureFailed)
        }
    }
}

private struct PendingThumbnail: View {
    let image: NSImage?
    let attachment: ClaudeAskAttachment
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        AttachmentThumbnail(image: image, attachment: attachment, height: 32)
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.Palette.primaryText)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Theme.Palette.background.opacity(0.85)))
                        .overlay(Circle().strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Remove this screenshot")
                .offset(x: Theme.Spacing.xs, y: -Theme.Spacing.xs)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
            .onHover { hovering = $0 }
            .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// A screenshot at a fixed height and its own aspect ratio, with a hairline
/// edge so a light capture still reads against the black notch.
struct AttachmentThumbnail: View {
    let image: NSImage?
    let attachment: ClaudeAskAttachment
    let height: CGFloat

    private var width: CGFloat {
        let ratio = CGFloat(attachment.pixelWidth) / CGFloat(max(attachment.pixelHeight, 1))
        return (height * min(max(ratio, 0.5), 2.5)).rounded()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                // The file is gone (deleted elsewhere): keep the shape.
                Image(systemName: "photo")
                    .font(.system(size: height * 0.3, weight: .medium))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Palette.surface)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
        .help("Screenshot sent with this question")
    }
}

/// Attach screenshot, at the right edge of the question field. Shows a
/// spinner while capturing and dims once the next question has as many
/// screenshots as it can take.
struct AttachButton: View {
    @ObservedObject var session: ClaudeAskSession

    private var isFull: Bool { session.pendingAttachments.count >= ClaudeAskSession.maxPendingAttachments }

    var body: some View {
        ZStack {
            if session.isCapturing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 24, height: 24)
                    .help("Taking a screenshot")
                    .transition(.opacity)
            } else {
                IconButton(symbol: "camera.viewfinder", size: 24, help: help) { session.attachScreenshot() }
                    .disabled(isFull)
                    .opacity(isFull ? 0.45 : 1)
                    .transition(.opacity)
            }
        }
        .motion(Theme.Motion.snappy, value: session.isCapturing)
    }

    private var help: String {
        isFull
            ? "A question can take up to \(ClaudeAskSession.maxPendingAttachments) screenshots"
            : "Attach a screenshot of this screen (Tabbi stays out of it)"
    }
}

/// Shown before the system is asked for Screen Recording: what it is for,
/// where the image goes, and one button to the exact Settings pane. Not Now
/// goes back to the chat, and the question can still be sent without one.
struct ScreenAccessView: View {
    @ObservedObject var session: ClaudeAskSession
    let accent: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
            VStack(spacing: Theme.Spacing.xs) {
                Text("Allow screenshots")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("To attach your screen, turn on Tabbi under Screen Recording. The screenshot goes only to Claude with your question.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
            HStack(spacing: Theme.Spacing.s) {
                PillButton(title: "Not Now", help: "Back to the chat without a screenshot") {
                    session.isAskingScreenAccess = false
                }
                PillButton(title: "Open System Settings", symbol: "arrow.up.forward.app",
                           tint: Theme.Palette.primaryText,
                           help: "Open Privacy & Security > Screen Recording in System Settings") {
                    session.openScreenRecordingSettings()
                }
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
