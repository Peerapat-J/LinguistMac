public struct AppFeature: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let systemImage: String

    public init(
        id: String,
        title: String,
        summary: String,
        systemImage: String
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
    }
}

public extension AppFeature {
    static let starterFeatures: [AppFeature] = [
        AppFeature(
            id: "screen-translation",
            title: "Screen Translation",
            summary: "Capture selected screen text, recognize it, and translate it.",
            systemImage: "rectangle.dashed"
        ),
        AppFeature(
            id: "quick-translate",
            title: "Quick Translate",
            summary: "Translate typed or selected text without taking a screenshot.",
            systemImage: "text.cursor"
        ),
        AppFeature(
            id: "history",
            title: "History",
            summary: "Keep recent translation results available for review.",
            systemImage: "clock"
        )
    ]
}
