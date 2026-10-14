import Foundation

/// Generic installer transport; every path/argument remains one argument.
enum WindowsInstaller {
    static func arguments(for file: URL) -> [String] {
        file.pathExtension.lowercased() == "msi" ? ["msiexec", "/i", file.path] : [file.path]
    }

    static func succeeded(_ status: Int32, isMSI: Bool) -> Bool {
        if status == 0 { return true }
        // Wine's Unix process transport exposes only the low byte of Windows exit status.
        // MSI's two reboot success codes must not be reported as failed installations.
        // https://learn.microsoft.com/en-us/windows/win32/msi/error-codes
        return isMSI && [1641, 3010, 1641 & 255, 3010 & 255].contains(status)
    }
}
