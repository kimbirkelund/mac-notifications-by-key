import Testing

@testable import NotificationAX

@Suite struct NbkErrorTests {
    @Test func notTrustedMessageNamesTheCurrentSettingsPath() {
        let message = NbkError.notTrusted.message
        #expect(message.contains("System Settings"))
        #expect(message.contains("Privacy & Security"))
        #expect(message.contains("Device Control and Data Access"))
        #expect(message.contains("\"Accessibility\" on older macOS"))
    }
}
