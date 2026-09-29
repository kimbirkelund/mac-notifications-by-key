public struct SelectionState: Equatable, Sendable {
    public private(set) var count: Int
    public private(set) var selectedIndex: Int?

    public init(count: Int, selectedIndex: Int?) {
        self.count = max(count, 0)
        self.selectedIndex =
            count > 0 ? selectedIndex.map { min(max($0, 0), count - 1) } : nil
    }

    public static func initial(count: Int) -> SelectionState {
        SelectionState(count: count, selectedIndex: count > 0 ? 0 : nil)
    }

    public mutating func moveDown() {
        guard let i = selectedIndex else { return }
        selectedIndex = min(i + 1, count - 1)
    }

    public mutating func moveUp() {
        guard let i = selectedIndex else { return }
        selectedIndex = max(i - 1, 0)
    }

    public func clamped(to count: Int) -> SelectionState {
        guard count > 0 else { return SelectionState(count: 0, selectedIndex: nil) }
        return SelectionState(count: count, selectedIndex: min(selectedIndex ?? 0, count - 1))
    }
}

public enum SelectionMove: Equatable, Sendable {
    case up, down
}

extension SelectionState {
    public mutating func apply(_ move: SelectionMove) {
        switch move {
        case .up: moveUp()
        case .down: moveDown()
        }
    }
}
