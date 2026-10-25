import ApplicationServices
import Foundation

let maxDepth = 12

struct Node: Encodable {
    let role: String?
    let identifier: String?
    let title: String?
    let value: String?
    let selected: Bool?
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let actions: [String]?
    let children: [Node]

    enum CodingKeys: String, CodingKey {
        case role, identifier, title, value, selected, x, y, width, height, actions, children
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(title, forKey: .title)
        try container.encode(value, forKey: .value)
        try container.encode(selected, forKey: .selected)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encodeIfPresent(actions, forKey: .actions)
        try container.encode(children, forKey: .children)
    }
}

struct Extra: Encodable {
    let role: String?
    let subrole: String?
    let identifier: String?
    let description: String?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case role, subrole, identifier, description, title
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(subrole, forKey: .subrole)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(description, forKey: .description)
        try container.encode(title, forKey: .title)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
    guard let value = attribute(element, name), CFGetTypeID(value) == CFBooleanGetTypeID() else {
        return nil
    }
    return CFBooleanGetValue(value as! CFBoolean)
}

func axValueAttribute<T>(
    _ element: AXUIElement, _ name: String, type: AXValueType, into result: inout T
) -> Bool {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else {
        return false
    }
    return AXValueGetValue(value as! AXValue, type, &result)
}

func node(_ element: AXUIElement, depth: Int) -> Node {
    var point = CGPoint.zero
    var size = CGSize.zero
    let hasPoint = axValueAttribute(element, kAXPositionAttribute, type: .cgPoint, into: &point)
    let hasSize = axValueAttribute(element, kAXSizeAttribute, type: .cgSize, into: &size)
    let kids = depth < maxDepth ? childElements(element) : []
    return Node(
        role: stringAttribute(element, kAXRoleAttribute),
        identifier: stringAttribute(element, kAXIdentifierAttribute),
        title: stringAttribute(element, kAXTitleAttribute),
        value: stringAttribute(element, kAXValueAttribute),
        selected: boolAttribute(element, kAXSelectedAttribute),
        x: hasPoint ? Double(point.x) : nil,
        y: hasPoint ? Double(point.y) : nil,
        width: hasSize ? Double(size.width) : nil,
        height: hasSize ? Double(size.height) : nil,
        actions: actionNames(element),
        children: kids.map { node($0, depth: depth + 1) }
    )
}

func actionNames(_ element: AXUIElement) -> [String]? {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
        let actions = names as? [String], !actions.isEmpty
    else {
        return nil
    }
    return actions
}

func childElements(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func extras(_ app: AXUIElement) -> [Extra] {
    guard let bar = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID()
    else {
        return []
    }
    return childElements(unsafeDowncast(bar, to: AXUIElement.self)).map {
        Extra(
            role: stringAttribute($0, kAXRoleAttribute),
            subrole: stringAttribute($0, kAXSubroleAttribute),
            identifier: stringAttribute($0, kAXIdentifierAttribute),
            description: stringAttribute($0, kAXDescriptionAttribute),
            title: stringAttribute($0, kAXTitleAttribute)
        )
    }
}

struct Dump: Encodable {
    let windows: [Node]
    let extras: [Extra]
}

let arguments = CommandLine.arguments
guard arguments.count == 2, let pid = pid_t(arguments[1]) else {
    fail("usage: axdump <pid>")
}
guard AXIsProcessTrusted() else {
    fail("axdump: Accessibility access is not granted")
}

let app = AXUIElementCreateApplication(pid)
guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
    fail("axdump: no windows attribute for pid \(pid)")
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(
    try encoder.encode(Dump(windows: windows.map { node($0, depth: 1) }, extras: extras(app))))
FileHandle.standardOutput.write(Data("\n".utf8))
