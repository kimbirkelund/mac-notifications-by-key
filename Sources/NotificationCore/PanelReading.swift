/// An empty read alone cannot tell an open, empty panel from a closed one, so a
/// read is judged together with whether the panel was still open after it.
public enum PanelReading: Equatable, Sendable {
    case notifications
    case nothingLeft
    case panelClosed

    public enum AfterReopen: Equatable, Sendable {
        case readAgain
        case endCouldNotKeepOpen
    }

    public static func classify(isEmpty: Bool, panelOpen: Bool) -> PanelReading {
        guard panelOpen else { return .panelClosed }
        return isEmpty ? .nothingLeft : .notifications
    }

    public static func afterReopen(confirmed: Bool) -> AfterReopen {
        confirmed ? .readAgain : .endCouldNotKeepOpen
    }
}
