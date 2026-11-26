import Foundation

enum HotKeyAction: Hashable, Sendable {
    /// Fixed actions with no command row of their own.
    case togglePalette
    case dictation
    /// Dictation whose transcript an AI model rewrites into another language before pasting.
    case dictationTranslate
    /// Parameterised over the catalog, so a new built-in command is bindable with no case here.
    case command(CommandID)
    case app(bundleID: String)
    case settingsPane(bundleID: String)
    case customCommand(id: UUID)
    case systemAction(id: SystemAction.ID)
    case windowCommand(id: WindowCommand.ID)
    case windowLayout(id: UUID)
    case windowRoom(id: UUID)
    case customWindowSize(id: UUID)
    case quicklink(id: UUID)
    case quickAction(id: UUID)
    case appleShortcut(id: UUID)
    case snippet(id: StoredSnippet.ID)
    /// Keyed by `AppEntry.id`, which is what survives a reinstall of the extension.
    case extensionCommand(entryID: String)

    /// The UserDefaults key, and the `HotKeyCenter` registration id: one per action.
    var defaultsKey: String {
        switch self {
        case .togglePalette: "hotkey.togglePalette"
        case .dictation: "hotkey.dictation"
        case .dictationTranslate: "hotkey.dictationTranslate"
        case .command(let id): "hotkey." + id.rawValue
        case .app(let bundleID): "hotkey.app." + bundleID
        case .settingsPane(let bundleID): "hotkey.pane." + bundleID
        case .customCommand(let id): "hotkey.customCommand." + id.uuidString.lowercased()
        case .systemAction(let id): "hotkey.systemAction." + id.rawValue
        case .windowCommand(let id): "hotkey.windowCommand." + id.rawValue
        case .windowLayout(let id): "hotkey.windowLayout." + id.uuidString.lowercased()
        case .windowRoom(let id): "hotkey.windowRoom." + id.uuidString.lowercased()
        case .customWindowSize(let id):
            "hotkey.customWindowSize." + id.uuidString.lowercased()
        case .quicklink(let id): "hotkey.quicklink." + id.uuidString.lowercased()
        case .quickAction(let id): "hotkey.quickAction." + id.uuidString.lowercased()
        case .appleShortcut(let id): "hotkey.appleShortcut." + id.uuidString.lowercased()
        case .snippet(let id): "hotkey.snippet." + id
        case .extensionCommand(let entryID): "hotkey.extensionCommand." + entryID
        }
    }

    /// The two recording shortcuts, which answer their key's release as well as its press.
    var recordsDictation: Bool { self == .dictation || self == .dictationTranslate }

    static let builtInActions: [HotKeyAction] =
        [.togglePalette, .dictation, .dictationTranslate] + CommandID.allCases.compactMap(\.hotKeyAction)
}
