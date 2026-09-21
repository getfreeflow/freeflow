import AppKit
import SwiftUI

// Icons from Lucide, https://lucide.dev (lucide-static 1.44.0).
//
// ISC License
//
// Copyright (c) 2026 Lucide Icons and Contributors
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//
// check, lock, power, search, trash-2 and x are derived from Feather:
//
// The MIT License (MIT)
//
// Copyright (c) 2013-present Cole Bemis
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// The icons FreeFlow uses, stored as the inner elements of Lucide's 24×24 SVGs.
///
/// AppKit renders SVG natively, so each one becomes a vector template image that
/// tints with `foregroundStyle` like any other, with no asset catalog involved.
enum Lucide: String {
    case mic, search, x, check, copy, pin, settings, power, lock, history
    case trash = "trash-2"
    case appWindow = "app-window"
    case clipboardCheck = "clipboard-check"
    case alert = "triangle-alert"

    fileprivate var elements: String {
        switch self {
        case .mic:
            return #"<path d="M12 19v3"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><rect x="9" y="2" width="6" height="13" rx="3"/>"#
        case .search:
            return #"<path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/>"#
        case .x:
            return #"<path d="M18 6 6 18"/><path d="m6 6 12 12"/>"#
        case .check:
            return #"<path d="M20 6 9 17l-5-5"/>"#
        case .copy:
            return #"<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>"#
        case .pin:
            return #"<path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>"#
        case .settings:
            return #"<path d="M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"/><circle cx="12" cy="12" r="3"/>"#
        case .power:
            return #"<path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.77.04"/>"#
        case .lock:
            return #"<rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>"#
        case .history:
            return #"<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/>"#
        case .trash:
            return #"<path d="M10 11v6"/><path d="M14 11v6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>"#
        case .appWindow:
            return #"<rect x="2" y="4" width="20" height="16" rx="2"/><path d="M10 4v4"/><path d="M2 8h20"/><path d="M6 4v4"/>"#
        case .clipboardCheck:
            return #"<rect width="8" height="4" x="8" y="2" rx="1" ry="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><path d="m9 14 2 2 4-4"/>"#
        case .alert:
            return #"<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>"#
        }
    }

    /// A template image at the given stroke width (in the icon's 24-unit grid).
    func image(strokeWidth: CGFloat) -> NSImage {
        let key = "\(rawValue)@\(strokeWidth)" as NSString
        if let cached = iconCache.object(forKey: key) { return cached }

        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="\#(strokeWidth)" stroke-linecap="round" stroke-linejoin="round">\#(elements)</svg>"#
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage()
        image.isTemplate = true
        iconCache.setObject(image, forKey: key)
        return image
    }
}

private let iconCache = NSCache<NSString, NSImage>()

/// A Lucide icon, tinted by the surrounding `foregroundStyle`.
struct Icon: View {
    let icon: Lucide
    var size: CGFloat
    var strokeWidth: CGFloat

    init(_ icon: Lucide, size: CGFloat = 14, strokeWidth: CGFloat = 2) {
        self.icon = icon
        self.size = size
        self.strokeWidth = strokeWidth
    }

    var body: some View {
        Image(nsImage: icon.image(strokeWidth: strokeWidth))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Mark

/// The FreeFlow mark: five rounded bars. Drawn rather than borrowed from SF
/// Symbols, so it's the same shape in the menu bar, the panel and the overlay.
struct FreeFlowMark: View {
    var height: CGFloat = 14

    static let bars: [CGFloat] = [0.42, 0.78, 1.0, 0.6, 0.36]

    var body: some View {
        HStack(spacing: height * 0.13) {
            ForEach(Self.bars.indices, id: \.self) { index in
                Capsule()
                    .frame(width: height * 0.15, height: height * Self.bars[index])
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// Template image for the menu bar, drawn at the status bar's own size.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let tallest: CGFloat = 13
            let width: CGFloat = 2.2
            let gap: CGFloat = 1.6
            let total = CGFloat(bars.count) * width + CGFloat(bars.count - 1) * gap
            var x = (rect.width - total) / 2

            NSColor.black.setFill()
            for ratio in bars {
                let height = tallest * ratio
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: (rect.height - height) / 2, width: width, height: height),
                    xRadius: width / 2,
                    yRadius: width / 2
                ).fill()
                x += width + gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
