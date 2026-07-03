extension SettingsSectionID {
    var searchTerms: [String] {
        switch self {
        case .general:
            [
                title,
                "App",
                "App language",
                "Language",
                "Menu Bar Icon",
                "Launch at login",
                "Auto copy result to clipboard",
                "Auto-copy",
                "Drag translation",
                "Double copy",
                "Cmd+C+C",
                "Cmd+C+C translation",
                "Clipboard translation",
                "Shortcut",
                "Enable Shortcut",
                "Screen translate",
                "Quick translate",
                "Selected text translate"
            ]
        case .translation:
            [
                title,
                "Translation Engine",
                "Engine",
                "Provider",
                "Apple Translation",
                "Cloud translation",
                "Source language",
                "Source",
                "Target language",
                "Target",
                "Language"
            ]
        case .appearance:
            [
                title,
                "Font family",
                "Font size",
                "Font",
                "Width",
                "Height",
                "Popup",
                "Match selection width"
            ]
        case .notification:
            [
                title,
                "Sound",
                "Play completion sound",
                "Screen Translate Sound",
                "System Notification",
                "Show completion notification",
                "Badge Notification"
            ]
        case .api:
            [
                title,
                "Provider Keys",
                "API key",
                "DeepL",
                "Google Cloud Translation",
                "Microsoft Azure Translator",
                "Azure region",
                "Region",
                "Save",
                "Test",
                "Clear"
            ]
        case .setup:
            [
                title,
                "Setup guide",
                "Open Setup Guide",
                "Screen Translation",
                "Screen Recording",
                "Apple Translation",
                "Text Selection",
                "Accessibility",
                "Voice Microphone",
                "Speech Recognition",
                "Cloud Providers",
                "Permission",
                "Ready",
                "Not set up"
            ]
        case .privacy:
            [
                title,
                "History store",
                "Translation history",
                "Provider keys",
                "Keychain",
                "API settings",
                "Local data",
                "Application Support"
            ]
        }
    }

    func matchesSearch(_ query: String) -> Bool {
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !tokens.isEmpty else {
            return true
        }

        let searchableText = searchTerms.joined(separator: " ")
        return tokens.allSatisfy {
            searchableText.localizedCaseInsensitiveContains($0)
        }
    }
}
