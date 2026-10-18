import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(t("История запусков")).font(.largeTitle.weight(.semibold))
                Text(t("Игровое время считается по обнаруженным процессам игры, без времени лаунчера. Пауза внутри игры и работа в фоне входят в это время; сон Mac — нет."))
                    .foregroundStyle(.secondary)
                Text(t("Всего игрового времени:") + " " + Self.duration(state.history.gameSeconds.values.reduce(0, +))).font(.headline)
                if let error = state.historyError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if state.history.sessions.isEmpty { Text(t("Запуски появятся здесь после использования этой версии ExeRunner.")) }
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(state.history.sessions.prefix(200))) { session in row(session) }
                }
                Text(t("Показаны последние 200 записей. Полная история ограничена 2000 завершёнными сессиями; суммарное игровое время сохраняется отдельно."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(t("Проверка процессов выполняется примерно раз в 2 секунды. Неизвестное время после потери наблюдения не добавляется; очень короткий запуск может остаться без замера."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.navigationTitle(t("История"))
    }
    private func row(_ session: HistorySession) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: session.target.kind == .game ? "gamecontroller" : (session.target.kind == .launcher ? "bag" : "app"))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.target.name).font(.headline)
                Text(session.requested.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text(title(session.status)).font(.caption).foregroundStyle(session.status == .crashed || session.status == .failed ? .orange : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(session.target.kind == .game && session.observed != nil ? Self.duration(session.seconds) : "—")
                    .monospacedDigit()
                Text(session.target.kind == .game ? t("Время игры") : t("Не игровое время")).font(.caption).foregroundStyle(.secondary)
            }
            if let item = state.item(session.target.itemID) {
                Button(t("Открыть")) { state.launch(item) }.disabled(state.running.contains(item.id) || state.isShuttingDown)
            }
        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
    static func duration(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? max(0, min(seconds, Double(Int.max / 4))) : 0
        let value = Int(safe)
        return String(format: "%ld:%02ld:%02ld", value / 3600, value / 60 % 60, value % 60)
    }
    private func title(_ status: SessionStatus) -> String {
        switch status {
        case .starting: t("Ожидание процесса")
        case .running: t("Работает")
        case .ended: t("Процесс завершился; причина неизвестна")
        case .exited: t("Завершено")
        case .stopped: t("Остановлено пользователем")
        case .crashed: t("Аварийное завершение")
        case .failed: t("Не удалось запустить")
        case .interrupted: t("Наблюдение прервано; учтено только подтверждённое время")
        case .unobserved: t("Процесс не наблюдался; время не начислено")
        }
    }
}

struct RecentApplicationsView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        if !state.recentItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Недавние приложения")).font(.title3.weight(.semibold))
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(state.recentItems) { item in
                            Button { state.launch(item) } label: {
                                Label(item.name, systemImage: item.kind == .game ? "gamecontroller" : "app")
                                    .lineLimit(1)
                            }.disabled(state.running.contains(item.id) || state.isShuttingDown)
                        }
                    }
                }
            }
        }
    }
}
