import AppKit
import Foundation

extension AppState {
    // MARK: remedies

    /// A finding's remedies as this item can use them: the components that provide the missing
    /// libraries, the other graphics path, advice
    func remedies(for diagnosis: CrashDiagnosis, item: LibraryItem) -> [Remedy] {
        var result: [Remedy] = []
        func add(_ remedy: Remedy) { if !result.contains(remedy) { result.append(remedy) } }
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        for id in diagnosis.remedies {
            switch id {
            case "install-missing-dll":
                let installed = Winetricks.installed(in: bottle)
                var verbs: [String] = []
                for verb in diagnosis.missingLibraries.compactMap(MissingLibrary.verb(for:))
                where !installed.contains(verb) && !verbs.contains(verb) {
                    verbs.append(verb)
                }
                if !verbs.isEmpty { add(.install(verbs)) }
            case "switch-graphics":
                if let other = otherGraphics(for: item) { add(.graphics(other)) }
            case "raytracing-off":
                if itemEnvironment(item)["D3DM_SUPPORT_DXR"] == "1" { add(.raytracingOff) }
            case "metalfx-off":
                if item.metalFX, engine?.d3dmetalVersion != nil, canTargetExecutables(item) { add(.metalFXOff) }
            case "logging-crash":
                if item.logging == .normal { add(.logging(.crash)) }
            default:
                if id.hasPrefix("info:"), let text = Remedy.advice[String(id.dropFirst(5))] { add(.note(text)) }
            }
        }
        return result
    }

    /// The graphics path worth trying instead of the current one, if the item's .exe is known
    private func otherGraphics(for item: LibraryItem) -> LibraryItem.Graphics? {
        guard canTargetExecutables(item) else { return nil }
        switch effectiveGraphics(item) {
        case .automatic, .d3dmetal:
            return engine?.hasDXMT == true && GraphicsSelection.supportsDXMT(profile: profile(for: item)) ? .dxmt : .dxvk
        case .dxmt: return engine?.d3dmetalVersion == nil ? .wine : .d3dmetal
        case .dxvk: return engine?.d3dmetalVersion == nil ? .wine : .automatic
        case .wine: return .vulkan
        case .vulkan: return engine?.d3dmetalVersion == nil ? .wine : .automatic
        }
    }

    func apply(_ remedy: Remedy, to id: String) async {
        guard var item = item(id) else { return }
        guard !item.isolated, !item.bottle.hasPrefix("isolated-") else {
            errorMessage = t("Автоматическая установка компонентов в изолированном прототипе пока недоступна.")
            return
        }
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        switch remedy {
        case .install(let verbs):
            _ = await installRuntimeComponents(verbs, for: item)
        case .graphics(let graphics):
            item.graphics = graphics
            upsert(item)
        case .raytracingOff:
            item.raytracing = false
            item.extraEnvironment["D3DM_SUPPORT_DXR"] = "0"
            upsert(item)
        case .metalFXOff:
            item.metalFX = false
            upsert(item)
        case .logging(let logging):
            item.logging = logging
            upsert(item)
        case .linkLauncher(let recipeID, _):
            item.recipeID = recipeID
            item.kind = .launcher
            upsert(item)
            refreshGames()
        case .audioDriver(let driver):
            updateBottle(item.bottle) { $0.audioDriver = driver }
            // what the registry has may differ from what was last written: write it again
            try? FileManager.default.removeItem(at: bottle.url.appendingPathComponent(".exerunner-audio"))
        case .audioLatency(let latency):
            updateBottle(item.bottle) { $0.audioLatency = latency }
        case .resetAudio:
            guard let engine else { return }
            do {
                try await BottleManager.resetAudio(bottle, engine: engine, log: Paths.logFile("\(item.bottle)-audio"))
            } catch {
                errorMessage = error.localizedDescription
            }
            await refreshProcesses()
        case .testAudio:
            guard let engine, FileManager.default.fileExists(atPath: engine.audioTest.path) else { return }
            let token = beginActivity(t("Проигрываю тестовый звук…"))
            defer { endActivity(token) }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("exerunner-audio-\(UUID().uuidString).log")
            defer { try? FileManager.default.removeItem(at: output) }
            do {
                try await BottleManager.ensure(bottle, engine: engine, log: Paths.logFile("\(item.bottle)-audio"))
                try await BottleManager.applyAudio(settings(forBottle: item.bottle), to: bottle, engine: engine, log: output)
                _ = try await WineProcess.run(engine: engine, arguments: [engine.audioTest.path, "--beep"],
                                              environment: WineEnvironment.make(engine: engine, prefix: bottle.url), log: output)
                audioTests[item.bottle] = AudioTestResult(output: (try? String(contentsOf: output, encoding: .utf8)) ?? "")
            } catch {
                errorMessage = error.localizedDescription
            }
        case .restartBottle:
            await stopBottle(item)
        case .clearDNSOverride:
            guard let engine else { return }
            do {
                try await BottleManager.importRegistry("""

                    [HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\Tcpip\\Parameters]
                    "NameServer"=-

                    """, into: bottle, engine: engine, log: Paths.logFile("\(item.bottle)-network"))
            } catch {
                errorMessage = error.localizedDescription
            }
        case .performanceHUD:
            item.performanceHUD = true
            upsert(item)
        case .variable(let name, let value):
            item.extraEnvironment[name] = value
            upsert(item)
        case .note:
            break
        }
    }

    // MARK: checks

    func checks(for symptom: Symptom, item: LibraryItem) async -> [Check] {
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        await refreshProcesses()
        switch symptom {
        case .launch:
            return [engineCheck(), d3dmetalCheck(), prefixCheck(bottle), outputCheck(item)] + gameCrashChecks(item)
                + componentChecks(item, bottle) + antiCheatChecks(item) + [graphicsCheck(item)]
        case .launcher:
            return launcherChecks(item, bottle) + [outputCheck(item, only: [.networkingLaunchers, .graphics, .coreCrashFatal])]
        case .graphics:
            return [graphicsCheck(item)] + raytracingChecks(item) + [d3dmetalCheck(), outputCheck(item, only: [.graphics]), gpuCheck()]
        case .audio:
            return audioChecks(item, bottle)
        case .controller:
            return controllerChecks(item)
        case .dependencies:
            return componentChecks(item, bottle) + [missingLibrariesCheck(item)]
        case .network:
            return networkChecks(item, bottle) + [outputCheck(item, only: [.networkingLaunchers])]
        case .performance:
            return performanceChecks(item)
        }
    }

    private func engineCheck() -> Check {
        let title = t("Движок")
        guard let engine else { return Check(title: title, status: .problem, detail: t("Движок не найден. Укажи его папку в настройках.")) }
        guard rosettaInstalled else {
            return Check(title: title, status: .problem, detail: t("Нет Rosetta, а без неё движок (x86_64) не запустится. Поставь её в настройках."))
        }
        var missing: [String] = []
        if !engine.hasCompatModule { missing.append(t("модуля совместимости")) }
        if !engine.hasDXVK { missing.append("DXVK") }
        if !engine.hasMoltenVK { missing.append("MoltenVK") }
        let version = engineVersion ?? "Wine"
        if !missing.isEmpty { return Check(title: title, status: .warning, detail: t("\(version): нет \(missing.joined(separator: ", ")).")) }
        return Check(title: title, status: .ok, detail: t("\(version) с DXVK, MoltenVK и модулем совместимости."))
    }

    private func d3dmetalCheck() -> Check {
        if let version = engine?.d3dmetalVersion {
            return Check(title: "D3DMetal", status: .ok, detail: t("Подключён, версия \(version): DirectX 11 и 12 идут через Metal."))
        }
        return Check(title: "D3DMetal", status: .warning,
                     detail: t("Не подключён: DirectX 11 и 12 идут через DXVK или встроенный wined3d, это медленнее, а DirectX 12 почти не работает. Подключи его в настройках."))
    }

    private func prefixCheck(_ bottle: Bottle) -> Check {
        let title = t("Бутылка «\(bottle.name)»")
        guard bottle.exists else { return Check(title: title, status: .info, detail: t("Ещё не создана: появится при первом запуске.")) }
        let problems = PrefixCheck.problems(in: bottle)
        if problems.isEmpty { return Check(title: title, status: .ok, detail: t("Цела: диск C:, профиль пользователя и AppData на месте.")) }
        return Check(title: title, status: .problem, detail: problems.map(PrefixCheck.describe).joined(separator: ". ") + ".",
                     remedies: [.note(Remedy.advice["prefix"]!)])
    }

    /// The last launch's output through the crash patterns, optionally only some categories
    private func outputCheck(_ item: LibraryItem, only categories: Set<CrashPattern.Category>? = nil) -> Check {
        let title = followsClient[item.id] != nil || item.isSteamGame ? t("Журнал запуска (общий со Steam)") : t("Журнал запуска")
        guard let text = segment(for: item.id)?.window() else {
            return Check(title: title, status: .info, detail: t("Журнала пока нет: запусти программу и проверь снова."))
        }
        var diagnosis = diagnoses[item.id] ?? CrashClassifier.shared.classify(text)
        if let categories { diagnosis = CrashDiagnosis(matches: diagnosis.matches.filter { categories.contains($0.pattern.category) }) }
        guard let primary = diagnosis.primary else {
            return Check(title: title, status: .ok, detail: t("Известных ошибок нет."))
        }
        if primary.pattern.id == "process-exit" {
            return Check(title: title, status: .problem, detail: primary.line,
                         remedies: remedies(for: diagnosis, item: item))
        }
        let more = diagnosis.matches.count > 1 ? t(" Всего находок: \(diagnosis.matches.count).") : ""
        return Check(title: title, status: primary.pattern.severity >= .error ? .problem : .warning,
                     detail: t("\(diagnosis.headline), \(diagnosis.confidenceTitle). Строка \(primary.lineNumber): \(primary.line.prefix(180))\(more)"),
                     remedies: remedies(for: diagnosis, item: item))
    }

    /// The game's own crash report from its last launch (Unreal writes one, wine's log stays clean)
    private func gameCrashChecks(_ item: LibraryItem) -> [Check] {
        guard let report = UnrealCrashReport.latest(in: crashReportRoots(for: item), since: launchTimes[item.id]) else { return [] }
        let diagnosis = UnrealCrashReport.diagnosis(report)
        let when = report.date.formatted(date: .abbreviated, time: .shortened)
        return [Check(title: t("Отчёт о вылете Unreal"), status: .problem, detail: "\(when): \(diagnosis.primary?.line ?? report.error)",
                      remedies: remedies(for: diagnosis, item: item))]
    }

    private func componentChecks(_ item: LibraryItem, _ bottle: Bottle) -> [Check] {
        guard let profile = profile(for: item), !profile.recommended.winetricks.isEmpty else { return [] }
        let installed = Winetricks.installed(in: bottle)
        let missing = profile.recommended.winetricks.filter { !installed.contains($0) }
        let title = t("Компоненты из базы")
        if missing.isEmpty {
            return [Check(title: title, status: .ok, detail: t("Стоят: \(profile.recommended.winetricks.joined(separator: ", "))."))]
        }
        let when = item.useRecommended ? t("Поставятся при следующем запуске, или сейчас.") : t("Рекомендации базы для этой игры выключены.")
        return [Check(title: title, status: .warning, detail: t("«\(profile.title)» нужны \(missing.joined(separator: ", ")). \(when)"),
                      remedies: [.install(missing)])]
    }

    private func missingLibrariesCheck(_ item: LibraryItem) -> Check {
        let title = t("Недостающие DLL")
        guard let text = segment(for: item.id)?.window() else {
            return Check(title: title, status: .info, detail: t("Журнала пока нет: после запуска здесь будет видно, каких библиотек не хватило."))
        }
        let failures = CrashDiagnosis(matches: CrashClassifier.shared.classify(text).matches
            .filter { $0.pattern.category == .dependenciesLoading })
        let names = failures.missingLibraries
        guard !names.isEmpty else { return Check(title: title, status: .ok, detail: t("В журнале нет ошибок загрузки библиотек.")) }
        var detail = t("Не загрузились: \(names.joined(separator: ", ")).")
        let unknown = names.filter { MissingLibrary.verb(for: $0) == nil }
        if !unknown.isEmpty { detail += t(" Для \(unknown.joined(separator: ", ")) готового компонента нет: проверь, что программа установлена целиком.") }
        return Check(title: title, status: .problem, detail: detail, remedies: remedies(for: failures, item: item))
    }

    private func antiCheatChecks(_ item: LibraryItem) -> [Check] {
        guard let antiCheat = profile(for: item)?.antiCheat else { return [] }
        return [Check(title: t("Античит"), status: .warning, detail: t("В игре \(antiCheat). \(Remedy.advice["anticheat"]!)"))]
    }

    private func graphicsCheck(_ item: LibraryItem) -> Check {
        let current = effectiveGraphics(item)
        var detail = t("Сейчас: \(current.title).")
        var remedies: [Remedy] = []
        if let profile = profile(for: item), profile.recommended.graphics != current {
            detail += t(" База рекомендует: \(profile.recommended.graphics.title).")
            if canTargetExecutables(item) { remedies.append(.graphics(profile.recommended.graphics)) }
        }
        if let other = otherGraphics(for: item), !remedies.contains(.graphics(other)) { remedies.append(.graphics(other)) }
        if item.isSteamGame, !canTargetExecutables(item) {
            detail += t(" Её .exe нет в базе, поэтому графика переключается, только когда Steam запускается вместе с игрой.")
        }
        return Check(title: t("Графика"), status: .info, detail: detail, remedies: remedies)
    }

    private func raytracingChecks(_ item: LibraryItem) -> [Check] {
        guard itemEnvironment(item)["D3DM_SUPPORT_DXR"] == "1" else { return [] }
        return [Check(title: t("Трассировка лучей"), status: .warning,
                      detail: t("Включена. На Mac она часто роняет игру или даёт артефакты."), remedies: [.raytracingOff])]
    }

    private func gpuCheck() -> Check {
        Check(title: t("Видеочип"), status: .info, detail: GPUProbe.summary() ?? t("Metal не отвечает."))
    }

    private func launcherChecks(_ item: LibraryItem, _ bottle: Bottle) -> [Check] {
        var result: [Check] = []
        if let detected = detectedLauncher(for: item) {
            result.append(Check(title: t("Тип лаунчера"), status: .problem,
                                detail: t("Похоже на \(detected.name), но его настройки не применены. Без них интерфейс лаунчера обычно чёрный или падает."),
                                remedies: [.linkLauncher(id: detected.id, name: detected.name)]))
        }
        let launcher = item.isSteamGame ? steamClient(for: item) : item
        guard let launcher, let recipe = recipe(launcher.recipeID), recipe.kind == .launcher else {
            if result.isEmpty {
                result.append(Check(title: t("Тип лаунчера"), status: .info, detail: t("Это не лаунчер из каталога. Общие проверки собраны в разделе «Не запускается».")))
            }
            return result
        }
        result.append(Check(title: t("Тип лаунчера"), status: .ok,
                            detail: t("\(recipe.name): его окна рисуются через DXVK (\(recipe.dxvkExecutables.joined(separator: ", "))).")))
        if bottle.exists, let engine {
            let shipped = engine.dxvk.appendingPathComponent("x64/d3d11.dll").path
            let inBottle = bottle.driveC.appendingPathComponent("windows/system32/d3d11.dll").path
            if !FileManager.default.contentsEqual(atPath: shipped, andPath: inBottle) {
                result.append(Check(title: t("DXVK в бутылке"), status: .warning, detail: t("Ещё не скопирован: появится при следующем запуске из приложения.")))
            }
        }
        let own = processes(of: launcher, in: processTable)
        if recipe.discoversSteamGames {
            let helpers = processTable.filter { $0.prefix == bottle.prefixPath && $0.name.lowercased() == "steamwebhelper.exe" }
            if own.isEmpty {
                result.append(Check(title: "Steam", status: .info, detail: t("Сейчас не запущен.")))
            } else if helpers.isEmpty {
                result.append(Check(title: "Steam", status: .problem,
                                    detail: t("Запущен, но его интерфейс (steamwebhelper) не поднялся: окно будет чёрным или пустым."),
                                    remedies: [.restartBottle]))
            } else {
                result.append(Check(title: "Steam", status: .ok, detail: t("Запущен, интерфейс работает (steamwebhelper: \(helpers.count)).")))
            }
        } else {
            result.append(Check(title: recipe.name, status: .info, detail: own.isEmpty ? t("Сейчас не запущен.") : t("Запущен.")))
        }
        return result
    }

    private func audioChecks(_ item: LibraryItem, _ bottle: Bottle) -> [Check] {
        var result: [Check] = []
        if let output = AudioProbe.defaultOutput() {
            var status = Check.Status.ok
            var notes: [String] = []
            if output.channels == 0 {
                status = .problem
                notes.append(t("у него нет выходных каналов"))
            }
            if output.sampleRate > 0, output.sampleRate < 22050 {
                status = .problem
                notes.append(t("гарнитура в режиме разговора: выбери её как наушники без микрофона"))
            } else if output.sampleRate > 0, output.sampleRate < 44100 {
                status = max(status, .warning)
                notes.append(t("лучше 44100 или 48000 Гц"))
            }
            if output.isBluetooth {
                status = max(status, .warning)
                notes.append(t("Bluetooth добавляет задержку, проводные надёжнее"))
            }
            let rate = output.sampleRate > 0 ? t(", \(Int(output.sampleRate)) Гц") : ""
            result.append(Check(title: t("Выход звука на Mac"), status: status,
                                detail: "\(output.name)\(rate)" + (notes.isEmpty ? "." : ": " + notes.joined(separator: "; ") + ".")))
        } else {
            result.append(Check(title: t("Выход звука на Mac"), status: .problem,
                                detail: t("macOS не отдаёт устройство вывода. Выбери его в Настройках системы → Звук.")))
        }

        let settings = settings(forBottle: item.bottle)
        let registry = BottleManager.registryValues(in: bottle, hive: "user.reg", key: "Software\\\\Wine\\\\Drivers")
        if settings.audioDriver == .disabled {
            result.append(Check(title: t("Звук в бутылке"), status: .problem, detail: t("Выключен в настройках бутылки «\(item.bottle)»."),
                                remedies: [.audioDriver(.automatic)]))
        } else if registry?["audio"] == "" {
            result.append(Check(title: t("Звук в бутылке"), status: .problem, detail: t("В реестре бутылки звук выключен, хотя в настройках включён."),
                                remedies: [.audioDriver(settings.audioDriver)]))
        } else {
            result.append(Check(title: t("Звук в бутылке"), status: .ok, detail: t("Драйвер: \(settings.audioDriver.title.lowercased())."),
                                remedies: settings.audioDriver == .automatic ? [.audioDriver(.coreaudio)] : []))
        }
        result.append(Check(title: t("Буфер звука"), status: settings.audioLatency == .low ? .warning : .info,
                            detail: settings.audioLatency == .low
                                ? t("Низкая задержка: под нагрузкой даёт треск.")
                                : t("\(settings.audioLatency.title). Если звук трещит или заикается, поможет буфер побольше."),
                            remedies: settings.audioLatency == .stable ? [] : [.audioLatency(.stable)]))
        if let test = audioTests[item.bottle] {
            result.append(Check(title: t("Тестовый звук"), status: test.ok ? .ok : .problem, detail: test.detail, remedies: [.testAudio]))
        } else if engine.map({ FileManager.default.fileExists(atPath: $0.audioTest.path) }) == true {
            result.append(Check(title: t("Тестовый звук"), status: .info,
                                detail: t("Проиграет короткий сигнал через звук Windows в этой бутылке: так видно, доходит ли звук до Mac."),
                                remedies: [.testAudio]))
        }
        result.append(Check(title: t("Звуковые устройства Windows"), status: .info,
                            detail: t("Если звук ушёл не туда или пропал после смены наушников, сбрось устройства: бутылка остановится и найдёт их заново."),
                            remedies: [.resetAudio]))
        return result
    }

    private func controllerChecks(_ item: LibraryItem) -> [Check] {
        let pads = ControllerProbe.connected()
        var result = [Check(title: t("Геймпады"), status: pads.isEmpty ? .warning : .ok,
                            detail: pads.isEmpty
                                ? t("macOS не видит ни одного. Подключи геймпад кабелем или по Bluetooth и проверь в Настройках системы → Игровые контроллеры.")
                                : t("Подключены: \(pads.joined(separator: ", ")). Игра видит их как контроллеры XInput."))]
        if item.isSteamGame {
            result.append(Check(title: "Steam Input", status: .info,
                                detail: t("Если игра не видит геймпад, включи Steam Input в свойствах игры в Steam (раздел «Контроллер»).")))
        }
        return result
    }

    private func networkChecks(_ item: LibraryItem, _ bottle: Bottle) -> [Check] {
        var result: [Check] = []
        let keys = ["System\\\\CurrentControlSet\\\\Services\\\\Tcpip\\\\Parameters", "System\\\\ControlSet001\\\\Services\\\\Tcpip\\\\Parameters"]
        let dns = keys.compactMap { BottleManager.registryValues(in: bottle, hive: "system.reg", key: $0)?["nameserver"] }.first { !$0.isEmpty }
        if let dns {
            result.append(Check(title: "DNS", status: .problem, detail: t("В бутылке прописан свой DNS (\(dns)), из-за него лаунчеры не находят серверы."),
                                remedies: [.clearDNSOverride]))
        } else {
            result.append(Check(title: "DNS", status: .ok, detail: t("Бутылка берёт DNS у Mac.")))
        }
        let client = item.isSteamGame ? steamClient(for: item) : (recipe(item.recipeID)?.discoversSteamGames == true ? item : nil)
        if let client {
            if processes(of: client, in: processTable).isEmpty {
                result.append(Check(title: t("Загрузки Steam"), status: .info, detail: t("Steam не запущен.")))
            } else if let minutes = stalledDownloadMinutes(SteamLibrary.root(in: bottle).appendingPathComponent("steamapps/downloading")) {
                result.append(Check(title: t("Загрузки Steam"), status: .warning, detail: t("Загрузка не двигается \(minutes) мин."),
                                    remedies: [.note(Remedy.advice["steam-download"]!)]))
            } else {
                result.append(Check(title: t("Загрузки Steam"), status: .ok, detail: t("Зависших загрузок нет.")))
            }
        }
        return result
    }

    /// Minutes since anything under steamapps/downloading changed, when that is over ten
    private func stalledDownloadMinutes(_ folder: URL) -> Int? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]),
              entries.contains(where: { $0.hasDirectoryPath }) else { return nil }
        var newest = Date.distantPast
        for entry in entries {
            for case let file as URL in fm.enumerator(at: entry, includingPropertiesForKeys: [.contentModificationDateKey]) ?? .init() {
                if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date > newest {
                    newest = date
                }
            }
        }
        let minutes = Int(Date().timeIntervalSince(newest) / 60)
        return minutes >= 10 ? minutes : nil
    }

    private func performanceChecks(_ item: LibraryItem) -> [Check] {
        var result: [Check] = []
        let info = ProcessInfo.processInfo
        result.append(info.isLowPowerModeEnabled
            ? Check(title: t("Энергосбережение"), status: .warning, detail: t("Включено: macOS снижает частоты. Выключи его в Настройках системы → Аккумулятор."))
            : Check(title: t("Энергосбережение"), status: .ok, detail: t("Выключено.")))
        switch info.thermalState {
        case .serious, .critical:
            result.append(Check(title: t("Температура"), status: .warning, detail: t("Mac перегрет, частоты уже снижены.")))
        default:
            result.append(Check(title: t("Температура"), status: .ok, detail: t("Перегрева нет.")))
        }
        result.append(Check(title: t("Память"), status: system.memoryGB < 16 ? .warning : .ok,
                            detail: system.memoryGB < 16
                                ? t("\(system.memoryGB) ГБ: игре и Rosetta тесно. Закрой браузер и другие тяжёлые программы.")
                                : t("\(system.memoryGB) ГБ.")))
        if engine?.d3dmetalVersion == nil { result.append(d3dmetalCheck()) }
        if effectiveGraphics(item) == .dxvk, environment(for: item)["DXVK_ASYNC"] != "1" {
            result.append(Check(title: t("Шейдеры DXVK"), status: .info,
                                detail: t("Без асинхронной сборки шейдеров игра дёргается, когда впервые показывает эффект."),
                                remedies: [.variable(name: "DXVK_ASYNC", value: "1")]))
        }
        if !item.performanceHUD {
            result.append(Check(title: t("Замер"), status: .info, detail: t("Счётчик FPS покажет кадры в секунду и время кадра прямо в игре."),
                                remedies: [.performanceHUD]))
        }
        return result
    }

    // MARK: report

    /// Writes the report zip to Downloads and returns it
    func exportReport(for item: LibraryItem, checks: [Check]) async -> URL? {
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        var engineInfo: [String: String] = ["path": engine?.root.path ?? "none", "version": engineVersion ?? "?"]
        if let engine {
            engineInfo["d3dmetal"] = engine.d3dmetalVersion ?? "none"
            engineInfo["dxvk"] = String(engine.hasDXVK)
            engineInfo["moltenvk"] = String(engine.hasMoltenVK)
            engineInfo["compat module"] = String(engine.hasCompatModule)
            engineInfo["discord bridge"] = String(engine.hasDiscordBridge)
        }
        var environment: [String: String] = [:]
        if let engine {
            var extra = self.environment(for: item)
            extra["EXERUNNER_COMPAT_FILE"] = BottleManager.compatFile(bottle).path
            environment = WineEnvironment.make(engine: engine, prefix: bottle.url, extra: extra)
        }
        let segment = segment(for: item.id)
        let input = DiagnosticReport.Input(
            item: item, effectiveGraphics: effectiveGraphics(item), recipe: recipe(item.recipeID), profile: profile(for: item),
            bottle: bottle, bottleSettings: settings(forBottle: item.bottle), system: system, rosetta: rosettaInstalled,
            engine: engineInfo, environment: environment,
            diagnosis: diagnoses[item.id] ?? segment?.window().map(CrashClassifier.shared.classify), checks: checks, log: segment,
            prefixProblems: PrefixCheck.problems(in: bottle).map(PrefixCheck.describe),
            winetricks: Winetricks.installed(in: bottle).sorted(),
            processes: processTable.filter { $0.prefix == bottle.prefixPath }.map(\.name).sorted())
        do {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? Paths.home
            return try await DiagnosticReport.export(input, to: downloads)
        } catch {
            errorMessage = t("Отчёт не сохранился: \(error.localizedDescription)")
            return nil
        }
    }
}
