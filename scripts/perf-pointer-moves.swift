// Posts mouse-moved events at the pointer's current spot, so the pointer
// does not move but every app with a global mouse monitor (Tabbi's notch
// tracks the pointer that way) handles a move. Lets
// scripts/measure-performance.sh measure what pointer tracking costs.
//
//   usage: perf-pointer-moves [events per second] [seconds]
//
// The terminal running it needs Accessibility access to post events;
// without it macOS drops them silently.
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments.dropFirst().compactMap(Double.init)
let rate = arguments.first ?? 60
let seconds = arguments.dropFirst().first ?? 30
for _ in 0..<Int(rate * seconds) {
    let here = CGEvent(source: nil)?.location ?? .zero
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: here, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(useconds_t(1_000_000 / rate))
}
