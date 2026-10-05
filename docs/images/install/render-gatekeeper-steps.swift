#!/usr/bin/env swift
// Draws gatekeeper-steps.png for docs/install.md: the two screens someone sees
// when macOS blocks a copy of Tabbi that is not notarized (a contributor's
// ad-hoc build), with numbered steps.
//
//     swift docs/images/install/render-gatekeeper-steps.swift
//
// It is an illustration, not a screenshot: capturing the real screens would
// mean blocking an app on purpose and leaving an exception behind in System
// Settings. The wording follows macOS 15 and 26 (Apple support article 102445).

import AppKit
import SwiftUI

let root = URL(fileURLWithPath: #filePath).absoluteURL.deletingLastPathComponent()
let repo = root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("gatekeeper-steps.png")
let appIcon = NSImage(contentsOf: repo.appendingPathComponent("Resources/AppIcon.icns"))
    ?? NSWorkspace.shared.icon(for: .applicationBundle)

let accent = Color(red: 0.20, green: 0.47, blue: 0.96)
let surface = Color(white: 0.12)
let raised = Color(white: 0.19)
let stroke = Color(white: 1, opacity: 0.10)

struct StepBadge: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(accent))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PillButton: View {
    let title: String
    var primary = false
    var highlighted = false
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 28)
            .frame(maxWidth: primary || !highlighted ? .infinity : nil)
            .background(Capsule().fill(primary ? accent : raised))
            .overlay {
                if highlighted {
                    Capsule().inset(by: -4).stroke(Color(red: 1, green: 0.62, blue: 0.20), lineWidth: 2.5)
                }
            }
    }
}

/// The dialog macOS 15 and later shows instead of opening the app.
struct BlockedDialog: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: appIcon).resizable().frame(width: 56, height: 56)
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 22))
                    .offset(x: 6, y: 4)
            }
            Text("\u{201C}Tabbi\u{201D} Not Opened")
                .font(.system(size: 14, weight: .bold))
            Text("Apple could not verify \u{201C}Tabbi\u{201D} is free of malware that may harm your Mac or compromise your privacy.")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.80))
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                PillButton(title: "Done", primary: true)
                PillButton(title: "Move to Trash")
            }
            .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(surface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(stroke))
    }
}

/// The Security section near the bottom of System Settings > Privacy & Security.
struct SecuritySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent))
                Text("Privacy & Security")
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.bottom, 18)
            Text("Security")
                .font(.system(size: 13, weight: .bold))
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Allow applications from")
                    Spacer()
                    Text("App Store & Known Developers")
                        .foregroundStyle(Color(white: 0.65))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(white: 0.65))
                }
                .padding(.vertical, 12)
                Rectangle().fill(stroke).frame(height: 1)
                HStack(spacing: 12) {
                    Text("\u{201C}Tabbi\u{201D} was blocked to protect your Mac.")
                    Spacer(minLength: 8)
                    PillButton(title: "Open Anyway", highlighted: true)
                }
                .padding(.vertical, 12)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(raised.opacity(0.6)))
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(width: 480)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(surface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(stroke))
    }
}

struct Steps: View {
    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                StepBadge(number: 1, text: "Open Tabbi once. When macOS stops it, click Done.")
                BlockedDialog()
            }
            .frame(width: 260)
            VStack(alignment: .leading, spacing: 16) {
                StepBadge(number: 2, text: "Within an hour, open System Settings > Privacy & Security, scroll down and click Open Anyway.")
                SecuritySection()
                StepBadge(number: 3, text: "Enter your Mac password, then click Open. macOS remembers your choice.")
            }
            .frame(width: 480)
        }
        .padding(32)
        .background(
            LinearGradient(colors: [Color(white: 0.07), Color(red: 0.08, green: 0.07, blue: 0.11)],
                           startPoint: .top, endPoint: .bottom)
        )
        .environment(\.colorScheme, .dark)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Steps())
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("render-gatekeeper-steps: rendering failed\n".utf8))
        exit(1)
    }
    try! data.write(to: output)
    print(output.path)
}
