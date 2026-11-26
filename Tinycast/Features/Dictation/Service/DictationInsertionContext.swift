import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum DictationInsertionContext {
    static func read(in target: InjectionTarget?) -> DictationTextFormatter.Context? {
        guard let (text, range) = field(in: target), let selected = Range(range, in: text) else {
            return nil
        }
        return .init(before: text[..<selected.lowerBound], after: text[selected.upperBound...])
    }

    /// What the field holds before the caret, which a translated reply has to continue.
    static func textBeforeCaret(in target: InjectionTarget?) -> String? {
        guard let (text, range) = field(in: target), let selected = Range(range, in: text) else {
            return nil
        }
        return String(text[..<selected.lowerBound])
    }

    /// A browser's window title names the site, which is the only hint which web app is open.
    static func windowTitle(in target: InjectionTarget?) -> String? {
        if let editor = target?.ownEditor { return editor.window?.title }
        guard let app = target?.externalApp else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window)
                == .success,
            let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        var title: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                unsafeDowncast(window, to: AXUIElement.self), kAXTitleAttribute as CFString, &title)
                == .success
        else { return nil }
        return title as? String
    }

    private static func field(in target: InjectionTarget?) -> (String, NSRange)? {
        if let editor = target?.ownEditor { return (editor.string, editor.selectedRange()) }
        guard let app = target?.externalApp else { return nil }
        guard let element = AccessibilityText.focusedElement(in: app) else { return nil }
        var value: CFTypeRef?
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
            let text = value as? String,
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &selected) == .success,
            let selected, CFGetTypeID(selected) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(selected, to: AXValue.self), .cfRange, &range)
        else { return nil }
        return (text, NSRange(location: range.location, length: range.length))
    }
}
