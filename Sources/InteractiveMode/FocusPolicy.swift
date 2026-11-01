enum FocusPolicy {
    enum Activation: Sendable, Equatable {
        case overlay
        case notificationCenter
        case other
    }

    enum Decision: Sendable, Equatable {
        case none
        case reclaim
        case yieldToTextField
    }

    static func decide(
        activation: Activation?,
        textFieldVisible: Bool,
        previousTextFieldVisible: Bool
    ) -> Decision {
        if textFieldVisible {
            return previousTextFieldVisible ? .none : .yieldToTextField
        }
        if previousTextFieldVisible { return .reclaim }
        switch activation {
        case nil, .overlay: return .none
        case .notificationCenter, .other: return .reclaim
        }
    }
}
