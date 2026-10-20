import AppKit
import UniformTypeIdentifiers

/// The native Finder dialog, shared by file and folder workflows.
@MainActor
enum FilePicker {
    static func choose(files: Bool = true, folders: Bool = false, startAt: URL? = nil, prompt: String = t("Выбрать"), fileExtensions: [String] = []) -> URL? {
        let panel = makePanel(files: files, folders: folders, startAt: startAt, prompt: prompt, fileExtensions: fileExtensions)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func makePanel(files: Bool = true, folders: Bool = false, startAt: URL? = nil,
                          prompt: String = t("Выбрать"), fileExtensions: [String] = []) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = files
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        if !fileExtensions.isEmpty {
            panel.allowedContentTypes = fileExtensions.compactMap { UTType(filenameExtension: $0) }
            panel.allowsOtherFileTypes = false
        }
        if let startAt { panel.directoryURL = startAt }
        return panel
    }
}
