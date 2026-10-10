import CoreAudio
import Foundation
import GameController
import Metal

/// What the helper asks about first. The eight areas are frankea/Whisky's troubleshooting index
/// (GPL-3.0-or-later); the checks behind them are this app's own, since Whisky's flows never get
/// the data they branch on.
enum Symptom: String, CaseIterable, Identifiable {
    case launch, launcher, graphics, audio, controller, dependencies, network, performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launch: "Не запускается или вылетает"
        case .launcher: "Лаунчер не работает"
        case .graphics: "Чёрный экран, артефакты"
        case .audio: "Нет звука или он трещит"
        case .controller: "Геймпад не работает"
        case .dependencies: "Просит компоненты Windows"
        case .network: "Сеть и загрузки"
        case .performance: "Тормозит"
        }
    }

    var symbol: String {
        switch self {
        case .launch: "exclamationmark.triangle"
        case .launcher: "bag"
        case .graphics: "display"
        case .audio: "speaker.wave.2"
        case .controller: "gamecontroller"
        case .dependencies: "shippingbox"
        case .network: "network"
        case .performance: "speedometer"
        }
    }
}

struct Check: Identifiable {
    enum Status: Int, Comparable {
        case ok, info, warning, problem
        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .ok: "ok"
            case .info: "info"
            case .warning: "warning"
            case .problem: "problem"
            }
        }
    }

    let id = UUID()
    let title: String
    let status: Status
    let detail: String
    var remedies: [Remedy] = []
}

/// Something the app can do about a finding, worked out for one item
enum Remedy: Hashable, Identifiable {
    case install([String])
    case graphics(LibraryItem.Graphics)
    case raytracingOff
    case metalFXOff
    case logging(LibraryItem.Logging)
    case linkLauncher(id: String, name: String)
    case audioDriver(BottleSettings.AudioDriver)
    case audioLatency(BottleSettings.AudioLatency)
    case resetAudio
    case testAudio
    case restartBottle
    case clearDNSOverride
    case performanceHUD
    case variable(name: String, value: String)
    /// Advice without an action
    case note(String)

    var id: String { String(describing: self) }

    /// The button's title; nil for advice
    var action: String? {
        switch self {
        case .install(let verbs): "Установить \(verbs.joined(separator: ", "))"
        case .graphics(let graphics): "Графика: \(graphics.title)"
        case .raytracingOff: "Выключить трассировку лучей"
        case .metalFXOff: "Выключить DLSS через MetalFX"
        case .logging(let logging): "Журнал: \(logging.title.lowercased())"
        case .linkLauncher(_, let name): "Применить настройки \(name)"
        case .audioDriver(let driver):
            switch driver {
            case .automatic: "Включить звук"
            case .coreaudio: "Звук напрямую через CoreAudio"
            case .disabled: "Выключить звук"
            }
        case .audioLatency(let latency):
            switch latency {
            case .standard: "Вернуть обычный буфер"
            case .low: "Уменьшить задержку"
            case .stable: "Увеличить буфер"
            }
        case .resetAudio: "Сбросить звуковые устройства"
        case .testAudio: "Проиграть тестовый звук"
        case .restartBottle: "Перезапустить бутылку"
        case .clearDNSOverride: "Убрать подмену DNS"
        case .performanceHUD: "Включить счётчик FPS"
        case .variable(let name, let value): "Задать \(name)=\(value)"
        case .note: nil
        }
    }

    /// Advice for the crash patterns' info:<topic> remedies
    static let advice: [String: String] = [
        "prefix": "Бутылка могла повредиться. Если проверка бутылки в разделе «Не запускается» нашла ошибки, поможет новая бутылка; программы в ней придётся поставить заново.",
        "network": "Сетевая ошибка внутри Windows-программы. Проверь интернет, VPN и время на Mac; лаунчеры через Wine иногда не проходят проверку TLS, тогда помогает повтор позже.",
        "anticheat": "Античит (EasyAntiCheat, BattlEye) не пускает Wine на Mac. Это ограничение античита, настройками его не обойти.",
        "steam-download": "Загрузка в Steam застряла: смени регион загрузки (Steam → Настройки → Загрузки) и очисти там же кэш загрузок.",
        "path": "Wine не нашёл или не смог открыть файл программы. Проверь путь в настройках запуска или переустанови программу.",
        "frame-generation": "Если в игре включена генерация кадров (Frame Generation, FSR 3, DLSS 3), выключи её в настройках игры: на D3DMetal 4 beta она роняет некоторые игры на первом кадре, так было с Black Myth: Wukong.",
    ]
}

/// The Mac's default output, as CoreAudio reports it. The thresholds are frankea/Whisky's
/// CoreAudioDeviceProbe (GPL-3.0-or-later).
enum AudioProbe {
    struct Output {
        let name: String
        let isBluetooth: Bool
        let sampleRate: Double
        let channels: Int
    }

    static func defaultOutput() -> Output? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        let deviceName = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr
            ? (name?.takeRetainedValue() as String? ?? "?") : "?"

        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)

        var rate = Float64(0)
        size = UInt32(MemoryLayout<Float64>.size)
        address.mSelector = kAudioDevicePropertyNominalSampleRate
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate)

        var channels = 0
        address.mSelector = kAudioDevicePropertyStreamConfiguration
        address.mScope = kAudioDevicePropertyScopeOutput
        if AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 {
            let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { raw.deallocate() }
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr {
                let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
                channels = list.reduce(0) { $0 + Int($1.mNumberChannels) }
            }
        }
        return Output(name: deviceName,
                      isBluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                      sampleRate: rate, channels: channels)
    }
}

enum ControllerProbe {
    static func connected() -> [String] {
        GCController.controllers().map { $0.vendorName ?? $0.productCategory }
    }
}

enum GPUProbe {
    static func summary() -> String? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let budget = Double(device.recommendedMaxWorkingSetSize) / 1_073_741_824
        return "\(device.name), до \(String(format: "%.0f", budget)) ГБ памяти под графику"
    }
}

/// What the audio check printed: {"status":"ok","api":"waveOut",...} or {"status":"error",...}
struct AudioTestResult {
    let ok: Bool
    let detail: String
    let date: Date

    init(output: String) {
        let line = output.split(separator: "\n").first { $0.hasPrefix("{\"") }.map(String.init) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
        ok = json["status"] as? String == "ok"
        if ok {
            let rate = json["sampleRate"] as? Int ?? 44100, channels = json["channels"] as? Int ?? 2
            detail = "Звук Windows работает: сигнал прозвучал (\(rate / 1000),\(rate % 1000 / 100) кГц, \(channels == 2 ? "стерео" : "\(channels) канала")). Не услышал — проверь громкость и выход звука на Mac."
        } else if let api = json["api"] as? String {
            detail = "Звук не открылся: \(api) вернул код \(json["code"] as? Int ?? -1)."
        } else {
            detail = "Проверка звука не ответила."
        }
        date = Date()
    }
}
