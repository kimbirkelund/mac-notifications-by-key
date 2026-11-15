import CoreGraphics
import Testing

@testable import NotificationCore

@Suite("PanelOpenDiagnostic")
struct PanelOpenDiagnosticTests {
    @Test func namesTheClockFramePointerAndFrontmostApp() {
        let text = PanelOpenDiagnostic.describe(
            clock: CGRect(x: 3306, y: 4, width: 114, height: 22),
            pointer: CGPoint(x: 1700.5, y: 700),
            frontmost: (name: "Ghostty", bundleID: "com.mitchellh.ghostty"))
        #expect(
            text
                == "clock at (3306, 4) 114x22, pointer at (1700.5, 700), frontmost Ghostty (com.mitchellh.ghostty)"
        )
    }

    @Test func marksWhatIsUnknown() {
        let text = PanelOpenDiagnostic.describe(clock: nil, pointer: nil, frontmost: nil)
        #expect(text == "clock at unknown, pointer at unknown, frontmost unknown")
    }

    @Test func anAppWithoutABundleIDIsNamedAlone() {
        let text = PanelOpenDiagnostic.describe(
            clock: nil, pointer: nil, frontmost: (name: "nbk", bundleID: nil))
        #expect(text.hasSuffix("frontmost nbk"))
    }

    @Test func nonFiniteAndHugeValuesDoNotTrap() {
        let text = PanelOpenDiagnostic.describe(
            clock: CGRect(x: CGFloat.infinity, y: 1e300, width: 1, height: 1),
            pointer: CGPoint(x: -CGFloat.infinity, y: 0), frontmost: nil)
        #expect(text == "clock at (inf, 1e+300) 1x1, pointer at (-inf, 0), frontmost unknown")
    }
}
