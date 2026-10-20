import AppKit
import UniformTypeIdentifiers

@main enum Test {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let panel = FilePicker.makePanel(startAt: directory, fileExtensions: ["exe"])
        precondition(panel.canChooseFiles && !panel.canChooseDirectories && !panel.allowsMultipleSelection)
        precondition(!panel.allowsOtherFileTypes)
        precondition(panel.allowedContentTypes.count == 1 && panel.allowedContentTypes.first?.preferredFilenameExtension == "exe")
        precondition(panel.directoryURL?.standardizedFileURL.path == directory.standardizedFileURL.path)
        print("native EXE picker: NSOpenPanel, EXE filter, single file, starting directory passed")
    }
}
