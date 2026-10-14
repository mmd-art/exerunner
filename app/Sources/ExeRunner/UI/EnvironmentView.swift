import SwiftUI

struct EnvironmentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    var inventory: DeviceInventory? = nil
    @State private var configuration = BottleSettings()
    @State private var devices = DeviceInventory()
    @State private var portNumber = 1
    @State private var portDevice = ""
    @State private var error: String?
    @State private var reservedPorts: Set<Int> = []
    private var selectedEngine: Engine? { try? state.selectedEngine(forBottle: item.bottle, proposed: configuration) }
    private var isolated: Bool { item.isolated || item.bottle.hasPrefix("isolated-") }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text(t("Эти настройки общие для всех программ Windows-среды «\(item.bottle)»."))
                        .font(.callout).foregroundStyle(.secondary)
                    if isolated { Text(t("Настройка движка и устройств в изолированном прототипе пока недоступна.")).foregroundStyle(.orange) }
                }
                Section(t("Движок этой Windows-среды")) {
                    Text(configuration.enginePath == nil ? t("По умолчанию приложения") : t("Выбран отдельно для этой среды"))
                    Text(selectedEngine?.root.path ?? t("Выбранный движок недоступен. Проверь папку с bin/wine и bin/wineserver."))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let version = selectedEngine?.recordedVersion { Text(version).font(.callout) }
                    HStack {
                        Button(t("Выбрать папку движка…")) {
                            if let file = FilePicker.choose(files: false, folders: true, startAt: selectedEngine?.root) {
                                do {
                                    _ = try EngineSelection.resolve(defaultEngine: nil, path: file.path)
                                    configuration.enginePath = file.path
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                        Button(t("Использовать движок по умолчанию")) { configuration.enginePath = nil }
                            .disabled(configuration.enginePath == nil)
                    }
                    .disabled(isolated)
                    Text(t("Смена движка применяется после остановки всех программ этой среды. Другие среды сохраняют свой выбор."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(t("Печать")) {
                    capability(t("Печать через принтеры Mac"), selectedEngine?.supportsPrinting == true)
                    if devices.printers.isEmpty { Text(t("На Mac нет настроенных принтеров.")).foregroundStyle(.secondary) }
                    ForEach(devices.printers, id: \.self) { Text($0).font(.callout) }
                    Button(t("Открыть настройки печати Windows…")) { Task { await state.openPrintingSettings(for: item) } }
                        .disabled(isolated || selectedEngine?.supportsPrinting != true || configuration.enginePath != state.settings(forBottle: item.bottle).enginePath)
                    Text(t("Выбор принтера и печать выполняются в самой Windows-программе. Физический принтер должен быть доступен на Mac."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(t("Последовательные порты (COM)")) {
                    ForEach(configuration.serialPorts) { port in
                        HStack {
                            Text(port.name).monospaced()
                            Text(port.device).font(.callout).foregroundStyle(.secondary)
                            if !SerialPortMapper.connected(port.device) { Text(t("Не подключён")).font(.caption).foregroundStyle(.orange) }
                            Spacer()
                            Button { configuration.serialPorts.removeAll { $0.number == port.number } } label: { Image(systemName: "minus.circle") }
                                .disabled(isolated)
                        }
                    }
                    if devices.serial.isEmpty { Text(t("Последовательные устройства не обнаружены.")).foregroundStyle(.secondary) }
                    HStack {
                        Picker("COM", selection: $portNumber) { ForEach(1..<256, id: \.self) { Text("COM\($0)").tag($0) } }.frame(width: 120)
                        Picker(t("Порт Mac"), selection: $portDevice) {
                            Text(t("Выбрать порт")).tag("")
                            ForEach(devices.serial) { Text($0.name).tag($0.node ?? "") }
                        }
                        Button(t("Подключить")) {
                            configuration.serialPorts.append(.init(number: portNumber, device: portDevice))
                            portNumber = nextFreePort()
                        }
                        .disabled(isolated || portDevice.isEmpty || reservedPorts.contains(portNumber) || configuration.serialPorts.contains { $0.number == portNumber })
                    }
                    if reservedPorts.contains(portNumber) { Text(t("Этот номер COM уже используется вне ExeRunner.")).font(.caption).foregroundStyle(.orange) }
                    Text(t("Изменения COM применяются при следующем запуске программы этой среды.")).font(.caption).foregroundStyle(.secondary)
                    Text(t("USB-serial устройства используют драйвер Mac и подключаются к Windows как COM. Ручные подключения сохраняются."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("USB · HID · MIDI") {
                    capability("USB", selectedEngine?.supportsUSB == true)
                    capability(t("Контроллеры HID"), selectedEngine?.supportsHID == true)
                    Picker(t("Режим контроллера"), selection: $configuration.controllerMode) {
                        ForEach(BottleSettings.ControllerMode.allCases) { mode in Text(mode.title).tag(mode).disabled(mode == .xinput && selectedEngine?.hasXInputMapping != true) }
                    }.disabled(isolated)
                    Text(t("Xbox / XInput преобразует совместимые геймпады для игр с Xbox-вводом. Нативный HID сохраняет исходный интерфейс. Автоматически возвращает прежнюю политику среды. Изменение применяется при следующем запуске."))
                        .font(.caption).foregroundStyle(.secondary)
                    capability("MIDI", selectedEngine?.supportsMIDI == true)
                    ForEach(devices.usb) { device in Label(device.name + " · " + device.detail, systemImage: "cable.connector") }
                    ForEach(devices.controllers) { device in Label(device.name, systemImage: "gamecontroller") }
                    ForEach(devices.midiInputs, id: \.self) { Text(t("Вход MIDI: \($0)")) }
                    ForEach(devices.midiOutputs, id: \.self) { Text(t("Выход MIDI: \($0)")) }
                    if devices.usb.isEmpty && devices.controllers.isEmpty && devices.midiInputs.isEmpty && devices.midiOutputs.isEmpty {
                        Text(t("Подключённые USB, HID-контроллеры и MIDI-устройства не обнаружены.")).foregroundStyle(.secondary)
                    }
                    Text(t("Поддержка зависит от интерфейса устройства. Произвольные драйверы Windows, ASIO и аппаратные ключи защиты требуют отдельной совместимости."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button(t("Обновить устройства")) { refreshDevices() }
                Spacer()
                Button(t("Отмена")) { dismiss() }
                Button(t("Сохранить")) {
                    do { try state.saveEnvironment(configuration, for: item.bottle); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.pillProminent).disabled(isolated)
            }
            .buttonStyle(.pill).padding(16)
        }
        .frame(width: 700, height: 780)
        .onAppear {
            configuration = state.settings(forBottle: item.bottle)
            refreshDevices(); portNumber = nextFreePort()
        }
        .alert(t("Не удалось сохранить настройки"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func refreshDevices() {
        devices = inventory ?? DeviceInventory.current()
        do { reservedPorts = try SerialPortMapper.unmanagedNumbers(in: Bottle(name: item.bottle, root: state.bottlesRoot)) }
        catch { reservedPorts = Set(1...255); self.error = error.localizedDescription }
    }
    private func nextFreePort() -> Int {
        let used = Set(configuration.serialPorts.map(\.number)).union(reservedPorts)
        return (1...255).first { !used.contains($0) } ?? 255
    }
    private func capability(_ title: String, _ enabled: Bool) -> some View {
        HStack {
            Text(title); Spacer()
            Text(enabled ? t("Доступно в движке") : t("Нет в выбранном движке"))
                .font(.caption).foregroundStyle(enabled ? Color.green : Color.secondary)
        }
    }
}
