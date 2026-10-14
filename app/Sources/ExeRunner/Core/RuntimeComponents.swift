import Foundation

/// Common Windows libraries, independent of application/game profiles.
struct RuntimeComponent: Identifiable {
    enum Group: String, CaseIterable, Identifiable {
        case visualC, dotnet, directX, fonts, system
        var id: String { rawValue }
        var title: String {
            switch self {
            case .visualC: return "Visual C++"
            case .dotnet: return ".NET"
            case .directX: return "DirectX"
            case .fonts: return t("Шрифты")
            case .system: return t("Системные библиотеки")
            }
        }
    }
    let id: String
    let title: String
    let group: Group

    static let all: [RuntimeComponent] = [
        .init(id: "vcrun2026", title: "Visual C++ 2017–2026", group: .visualC),
        .init(id: "vcrun2022", title: "Visual C++ 2015–2022", group: .visualC),
        .init(id: "vcrun2013", title: "Visual C++ 2013", group: .visualC),
        .init(id: "vcrun2012", title: "Visual C++ 2012", group: .visualC),
        .init(id: "vcrun2010", title: "Visual C++ 2010", group: .visualC),
        .init(id: "vcrun2008", title: "Visual C++ 2008", group: .visualC),
        .init(id: "vcrun2005", title: "Visual C++ 2005", group: .visualC),
        .init(id: "dotnet48", title: ".NET Framework 4.8", group: .dotnet),
        .init(id: "dotnetdesktop10", title: ".NET Desktop Runtime 10", group: .dotnet),
        .init(id: "dotnet10", title: ".NET Runtime 10", group: .dotnet),
        .init(id: "dotnetdesktop8", title: ".NET Desktop Runtime 8", group: .dotnet),
        .init(id: "dotnetdesktop9", title: ".NET Desktop Runtime 9", group: .dotnet),
        .init(id: "dotnet8", title: ".NET Runtime 8", group: .dotnet),
        .init(id: "dotnet9", title: ".NET Runtime 9", group: .dotnet),
        .init(id: "d3dx9", title: "DirectX 9 libraries", group: .directX),
        .init(id: "d3dx10", title: "DirectX 10 libraries", group: .directX),
        .init(id: "d3dx11_43", title: "DirectX 11 libraries", group: .directX),
        .init(id: "d3dcompiler_43", title: "D3DCompiler 43", group: .directX),
        .init(id: "d3dcompiler_47", title: "D3DCompiler 47", group: .directX),
        .init(id: "xact", title: "XAudio / XACT", group: .directX),
        .init(id: "xinput", title: "XInput", group: .directX),
        .init(id: "corefonts", title: "Microsoft Core Fonts", group: .fonts),
        .init(id: "tahoma", title: "Tahoma", group: .fonts),
        .init(id: "msxml3", title: "MSXML 3", group: .system),
        .init(id: "msxml6", title: "MSXML 6", group: .system),
        .init(id: "gdiplus", title: "GDI+", group: .system),
        .init(id: "riched20", title: "RichEdit 2", group: .system),
    ]

    /// Recognized imports suggest libraries, not an application-specific recipe.
    /// Wine Mono already supplies mscoree; do not automatically replace it with native .NET.
    static func suggested(for executable: URL, available: Set<String> = [], installed: Set<String> = []) -> [String] {
        let known = Set(all.map(\.id))
        let adjacent = Set(((try? FileManager.default.contentsOfDirectory(atPath: executable.deletingLastPathComponent().path)) ?? [])
            .map { $0.lowercased() })
        let imports = PEInspection.read(executable)?.imports ?? []
        var result = Set(imports.filter { !adjacent.contains($0.lowercased()) }
            .compactMap { MissingLibrary.verb(for: $0) }.filter { known.contains($0) && $0 != "dotnet48" })
        let config = executable.deletingPathExtension().appendingPathExtension("runtimeconfig.json")
        if let size = try? config.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1024 * 1024,
           let data = try? Data(contentsOf: config),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let options = json["runtimeOptions"] as? [String: Any] {
            var frameworks = options["frameworks"] as? [[String: Any]] ?? []
            if let framework = options["framework"] as? [String: Any] { frameworks.append(framework) }
            for framework in frameworks {
                guard let name = framework["name"] as? String,
                      let version = framework["version"] as? String,
                      let major = version.split(separator: ".").first, ["8", "9", "10"].contains(major) else { continue }
                if name == "Microsoft.WindowsDesktop.App" { result.insert("dotnetdesktop\(major)") }
                if name == "Microsoft.NETCore.App" { result.insert("dotnet\(major)") }
            }
        }
        // Desktop also installs the matching base runtime.
        for major in ["8", "9", "10"] where result.contains("dotnetdesktop\(major)") { result.remove("dotnet\(major)") }
        if result.contains("vcrun2022"), available.contains("vcrun2026"), !installed.contains("vcrun2022") {
            result.remove("vcrun2022"); result.insert("vcrun2026")
        }
        return result.sorted()
    }
}
