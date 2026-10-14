import Foundation

/// A missing explicit engine is an error, never a silent switch to a different runtime.
enum EngineSelection {
    static func resolve(defaultEngine: Engine?, path: String?) throws -> Engine {
        if let path, !path.isEmpty {
            let chosen = Engine(root: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL)
            guard chosen.isValid, FileManager.default.isExecutableFile(atPath: chosen.wineserver.path) else {
                throw AppError(t("Выбранный движок недоступен. Проверь папку с bin/wine и bin/wineserver."))
            }
            return chosen
        }
        guard let defaultEngine else { throw AppError(t("Движок не найден. Укажи его папку в настройках.")) }
        return defaultEngine
    }
    static func configuredEngines(defaultEngine: Engine?, store: URL) -> [Engine] {
        var result = defaultEngine.map { [$0] } ?? []
        if let size = try? store.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1024 * 1024,
           let data = try? Data(contentsOf: store),
           let records = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            for record in records.values {
                if let path = record["enginePath"] as? String,
                   let engine = try? resolve(defaultEngine: nil, path: path), !result.contains(engine) { result.append(engine) }
            }
        }
        return result
    }

}
