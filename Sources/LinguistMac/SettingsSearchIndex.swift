import LinguistMacCore

extension SettingsSectionID {
    var searchTerms: [String] {
        switch self {
        case .general:
            [
                title,
                "App",
                "App Language",
                "Language",
                "Menu Bar Icon",
                "Launch at Login",
                "Auto Copy Result to Clipboard",
                "Auto Copy",
                "Drag Translation",
                "Double Copy",
                "Cmd+C+C",
                "Cmd+C+C Translation",
                "Clipboard Translation",
                "Shortcut",
                "Enable Shortcut",
                "Screen Translate",
                "Quick Translate",
                "Selected Text Translate"
            ]
        case .translation:
            [
                title,
                "Translation Engine",
                "Engine",
                "Provider",
                "Apple Translation",
                "Cloud Translation",
                "Source Language",
                "Source",
                "Target Language",
                "Target",
                "Language",
                "Apple Language Packs",
                "Language Packs",
                "Language Pack",
                "Language Groups",
                "Search Language Packs",
                "Supported Languages",
                "Download",
                "Downloading",
                "Still Downloading",
                "Keep Checking",
                "Download Failed",
                "Needs Download",
                "Cancel",
                "Pin",
                "Unpin",
                "Pinned",
                "Current",
                "Ready",
                "Checking",
                "Unsupported",
                "Auto Detect",
                "On Device",
                "System Managed Assets"
            ] + TranslationLanguageCatalog.defaultLanguages.flatMap {
                [$0.displayName, $0.id]
            }
        case .appearance:
            [
                title,
                "Font Family",
                "Font Size",
                "Font",
                "Width",
                "Height",
                "Popup",
                "Match Selection Width"
            ]
        case .notification:
            [
                title,
                "Sound",
                "Play Completion Sound",
                "Screen Translate Sound",
                "System Notification",
                "Show Completion Notification",
                "Badge Notification"
            ]
        case .api:
            [
                title,
                "Provider Keys",
                "API Key",
                "DeepL",
                "Google Cloud Translation",
                "Microsoft Azure Translator",
                "Azure Region",
                "Region",
                "Save",
                "Test",
                "Clear"
            ]
        case .setup:
            [
                title,
                "Setup Guide",
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
                "Not Set Up"
            ]
        case .privacy:
            [
                title,
                "History Store",
                "Translation History",
                "Provider Keys",
                "Keychain",
                "API Settings",
                "Local Data",
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
