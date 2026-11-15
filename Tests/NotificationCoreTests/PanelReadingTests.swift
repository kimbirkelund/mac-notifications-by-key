import Testing

@testable import NotificationCore

@Suite("PanelReading")
struct PanelReadingTests {
    // Validates RIM-16: only an open, empty panel means nothing is left.
    @Test func anOpenEmptyPanelHasNothingLeft() {
        #expect(PanelReading.classify(isEmpty: true, panelOpen: true) == .nothingLeft)
    }

    @Test func anOpenPanelWithNotificationsIsShown() {
        #expect(PanelReading.classify(isEmpty: false, panelOpen: true) == .notifications)
    }

    // Validates RIM-31: a closed panel is reopened, whatever the read returned.
    @Test("a closed panel is reopened", arguments: [true, false])
    func aClosedPanelIsReopened(isEmpty: Bool) {
        #expect(PanelReading.classify(isEmpty: isEmpty, panelOpen: false) == .panelClosed)
    }

    // Validates RIM-31: a confirmed reopen is followed by a fresh read.
    @Test func aConfirmedReopenReadsAgain() {
        #expect(PanelReading.afterReopen(confirmed: true) == .readAgain)
    }

    // Validates RIM-32: a reopen that is not confirmed ends the mode.
    @Test func anUnconfirmedReopenEndsTheMode() {
        #expect(PanelReading.afterReopen(confirmed: false) == .endCouldNotKeepOpen)
    }
}
