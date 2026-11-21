import Testing

@testable import NotificationCore

@Suite struct ActionOutcomeTests {
    @Test func zeroCodeIsSuccess() {
        #expect(ActionOutcome.isPerformed(action: "Close", app: "Mail", axError: 0))
    }

    @Test func slackReplyGenericFailureIsPerformed() {
        #expect(ActionOutcome.isPerformed(action: "Reply", app: "Slack", axError: -25200))
    }

    @Test func replyGenericFailureFromAnotherAppIsFailure() {
        #expect(!ActionOutcome.isPerformed(action: "Reply", app: "Mail", axError: -25200))
        #expect(!ActionOutcome.isPerformed(action: "Reply", app: nil, axError: -25200))
    }

    @Test func slackReplyWithAnotherErrorIsFailure() {
        #expect(!ActionOutcome.isPerformed(action: "Reply", app: "Slack", axError: -25204))
    }

    @Test func otherActionGenericFailureOnSlackIsFailure() {
        #expect(!ActionOutcome.isPerformed(action: "Close", app: "Slack", axError: -25200))
    }

    @Test func onlyReplyDependsOnTheApp() {
        #expect(ActionOutcome.dependsOnApp(action: "Reply"))
        #expect(!ActionOutcome.dependsOnApp(action: "Close"))
    }
}
