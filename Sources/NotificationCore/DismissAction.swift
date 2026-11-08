public enum DismissAction {
    public static func name(for actions: [String]) -> String {
        if CollapsedStack.matches(actions: actions) { return "Clear All" }
        return actions.contains("Dismiss") ? "Dismiss" : "Close"
    }
}
