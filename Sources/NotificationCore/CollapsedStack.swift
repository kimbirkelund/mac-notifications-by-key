public enum CollapsedStack {
    public static func matches(actions: [String]) -> Bool {
        actions.contains("Clear All") && !actions.contains("Close")
    }
}
