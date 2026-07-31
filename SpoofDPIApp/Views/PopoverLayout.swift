import AppKit
import SwiftUI

enum PopoverLayout {
    static var screen: NSScreen {
        NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first!
    }

    /// Compact menubar panel width that scales gently with display size.
    static var width: CGFloat {
        let screenWidth = screen.visibleFrame.width
        let ideal = screenWidth * 0.14
        return ideal.clamped(to: 280...340)
    }

    /// Main content area height (Status / Settings).
    static var contentHeight: CGFloat {
        let screenHeight = screen.visibleFrame.height
        let ideal = screenHeight * 0.18
        return ideal.clamped(to: 180...260)
    }

    static var horizontalPadding: CGFloat {
        width < 300 ? 14 : 16
    }

    static var titleSize: CGFloat {
        width < 300 ? 18 : 20
    }

    static var toggleScale: CGFloat {
        contentHeight < 200 ? 1.7 : 2.0
    }

    static var statusTitleFont: Font {
        .headline.weight(.bold)
    }

    static var statusDetailFont: Font {
        .subheadline
    }

    static var statusSecondaryFont: Font {
        .caption
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
