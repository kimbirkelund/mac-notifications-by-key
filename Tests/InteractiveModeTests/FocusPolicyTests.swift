import Testing

@testable import InteractiveMode

@Suite struct FocusPolicyTests {
    private func decide(
        _ activation: FocusPolicy.Activation?, field: Bool, was: Bool = false
    ) -> FocusPolicy.Decision {
        FocusPolicy.decide(
            activation: activation, textFieldVisible: field, previousTextFieldVisible: was)
    }

    /// RIM-25
    @Test func otherAppActivatedWithoutFieldReclaims() {
        #expect(decide(.other, field: false) == .reclaim)
    }

    /// RIM-25
    @Test func notificationCenterActivatedWithoutFieldReclaims() {
        #expect(decide(.notificationCenter, field: false) == .reclaim)
    }

    /// RIM-27
    @Test func anyAppActivatedWithFieldVisibleDoesNothing() {
        for activation in [FocusPolicy.Activation.other, .notificationCenter, .overlay] {
            #expect(decide(activation, field: true, was: true) == .none)
        }
    }

    /// RIM-27
    @Test func fieldAppearingYields() {
        #expect(decide(nil, field: true, was: false) == .yieldToTextField)
    }

    /// RIM-25
    @Test func fieldDisappearingReclaims() {
        #expect(decide(nil, field: false, was: true) == .reclaim)
    }

    @Test func overlayActivatedDoesNothing() {
        #expect(decide(.overlay, field: false) == .none)
    }

    private func decide(
        overlayLostFocus: Bool = false, panelReopenCompleted: Bool = false, field: Bool
    ) -> FocusPolicy.Decision {
        FocusPolicy.decide(
            activation: nil, textFieldVisible: field, previousTextFieldVisible: field,
            overlayLostFocus: overlayLostFocus, panelReopenCompleted: panelReopenCompleted)
    }

    /// RIM-25
    @Test func overlayLostFocusWithoutFieldReclaims() {
        #expect(decide(overlayLostFocus: true, field: false) == .reclaim)
    }

    /// RIM-27
    @Test func overlayLostFocusWithFieldDoesNothing() {
        #expect(decide(overlayLostFocus: true, field: true) == .none)
    }

    /// RIM-31
    @Test func panelReopenCompletedWithoutFieldReclaims() {
        #expect(decide(panelReopenCompleted: true, field: false) == .reclaim)
    }

    /// RIM-27
    @Test func panelReopenCompletedWithFieldDoesNothing() {
        #expect(decide(panelReopenCompleted: true, field: true) == .none)
    }

    /// RIM-25
    @Test func lostFocusOrCompletedReopenReclaimsEvenWhenOverlayIsFrontmost() {
        for (lost, reopened) in [(true, false), (false, true)] {
            #expect(
                FocusPolicy.decide(
                    activation: .overlay, textFieldVisible: false,
                    previousTextFieldVisible: false, overlayLostFocus: lost,
                    panelReopenCompleted: reopened) == .reclaim)
        }
    }

    @Test func quietPollDoesNothing() {
        #expect(decide(nil, field: false) == .none)
        #expect(decide(nil, field: true, was: true) == .none)
    }
}
