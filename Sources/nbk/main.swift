import Foundation
import NotificationAX
import NotificationCore

func die(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let usage = """
    usage: nbk <command> [args]
      list [--wait <seconds>]   print presented notifications as JSON (newest first)
      dismiss <index>           dismiss the notification at <index>
      action <index> <name>     perform a named action (e.g. "Show")
      press <index>             default activation (open)
      doctor                    report Accessibility trust, NC pid, macOS version
    """

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { die(usage, code: 64) }
let rest = Array(args.dropFirst())

func intArg(_ tokens: [String], _ position: Int) -> Int? {
    guard position < tokens.count else { return nil }
    return Int(tokens[position])
}

do {
    switch command {
    case "list":
        var wait: TimeInterval = 0
        if let i = rest.firstIndex(of: "--wait"), let v = intArg(rest, i + 1).map(Double.init) {
            wait = v
        }
        let items = try NotificationAX.read(wait: wait)
        print(try Output.json(items))

    case "dismiss":
        guard let n = intArg(rest, 0) else { die("usage: nbk dismiss <index>", code: 64) }
        try NotificationAX.dismiss(index: n)

    case "press":
        guard let n = intArg(rest, 0) else { die("usage: nbk press <index>", code: 64) }
        try NotificationAX.press(index: n)

    case "action":
        guard let n = intArg(rest, 0), rest.count >= 2 else {
            die("usage: nbk action <index> <name>", code: 64)
        }
        try NotificationAX.perform(action: rest[1], index: n)

    case "doctor":
        let trusted = NotificationAX.isTrusted
        let pid = NotificationAX.notificationCenterPID()
        print("accessibility_trust: \(trusted)")
        print("notification_center_pid: \(pid.map(String.init) ?? "not found")")
        print("macos: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        if !trusted { die(NbkError.notTrusted.message, code: NbkError.notTrusted.exitCode) }

    case "-h", "--help", "help":
        print(usage)

    default:
        die("unknown command: \(command)\n\(usage)", code: 64)
    }
} catch let error as NbkError {
    die(error.message, code: error.exitCode)
} catch {
    die("error: \(error)")
}
