import AppKit
import DemoNotifications

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: demo-nc <file>\n".utf8))
    exit(2)
}

let file: DemoFile
do {
    file = try DemoFile.load(from: URL(fileURLWithPath: arguments[1]))
} catch {
    FileHandle.standardError.write(Data("demo-nc: \(error)\n".utf8))
    exit(1)
}

let missingApp = file.notifications.enumerated().flatMap { index, notification in
    [(String(index), notification)]
        + notification.members.enumerated().map { ("\(index).members.\($0.offset)", $0.element) }
}.first { $0.1.app == nil }
if let (location, notification) = missingApp {
    let title = notification.title.map { " (\"\($0)\")" } ?? ""
    FileHandle.standardError.write(
        Data("demo-nc: notification \(location)\(title) has no \"app\"\n".utf8))
    exit(1)
}

let app = NSApplication.shared
let controller = DemoController(model: DemoNotificationsModel(notifications: file.notifications))
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
