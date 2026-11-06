import SwiftUI
import UIKit
import SwiftData
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(PrefKey.morningOn) private var morningOn = true
    @AppStorage(PrefKey.morningTime) private var morningTime = 7 * 60
    @AppStorage(PrefKey.trainingOn) private var trainingOn = true
    @AppStorage(PrefKey.trainingTime) private var trainingTime = 17 * 60
    @AppStorage(PrefKey.eveningOn) private var eveningOn = true
    @AppStorage(PrefKey.eveningTime) private var eveningTime = 20 * 60
    @AppStorage(PrefKey.todoOn) private var todoOn = true
    @AppStorage(PrefKey.quietOn) private var quietOn = false
    @AppStorage(PrefKey.quietStart) private var quietStart = 22 * 60
    @AppStorage(PrefKey.quietEnd) private var quietEnd = 7 * 60

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0
    @State private var testSent = false

    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importCandidate: BackupData?
    @State private var message: String?

    private var prefsSignature: String {
        [morningOn, trainingOn, eveningOn, todoOn, quietOn].map { $0 ? "1" : "0" }.joined()
            + "|\(morningTime)|\(trainingTime)|\(eveningTime)|\(quietStart)|\(quietEnd)"
    }

    var body: some View {
        NavigationStack {
            Form {
                permissionSection

                timeSection(title: "Morgen-Übersicht",
                            footer: "Training, Termine, To-Dos und Gewohnheiten des Tages.",
                            isOn: $morningOn,
                            minutes: $morningTime)

                timeSection(title: "Training-Erinnerung",
                            footer: "Nur an Trainingstagen und nur, solange das Training offen ist.",
                            isOn: $trainingOn,
                            minutes: $trainingTime)

                timeSection(title: "Abend-Check",
                            footer: "Noch offene To-Dos und Gewohnheiten. Entfällt, wenn alles erledigt ist.",
                            isOn: $eveningOn,
                            minutes: $eveningTime)

                Section {
                    Toggle("Individuelle Erinnerungen", isOn: $todoOn)
                } footer: {
                    Text("Erinnerungen, die du bei einzelnen To-Dos, Terminen und Gewohnheiten festlegst.")
                }

                Section {
                    Toggle("Ruhezeiten", isOn: $quietOn.animation())
                    if quietOn {
                        DatePicker("Von", selection: .minutes($quietStart), displayedComponents: .hourAndMinute)
                        DatePicker("Bis", selection: .minutes($quietEnd), displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Mitteilungen, die in die Ruhezeit fallen, werden nicht zugestellt.")
                }

                backupSection

                Section {
                    LabeledContent("Version", value: versionString)
                } footer: {
                    Text("Alle Daten liegen ausschließlich auf diesem iPhone.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task { await refreshStatus() }
            .onChange(of: prefsSignature) { _, _ in
                NotificationScheduler.shared.scheduleSoon()
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await refreshStatus()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshStatus() }
                }
            }
            .alert(message ?? "",
                   isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    // MARK: - Abschnitte

    private var permissionSection: some View {
        Section {
            HStack {
                Text("Berechtigung")
                Spacer()
                Text(statusText)
                    .foregroundStyle(statusColor)
            }

            if authStatus == .notDetermined {
                Button("Mitteilungen erlauben") {
                    Task {
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                        await NotificationScheduler.shared.rescheduleNow()
                        await refreshStatus()
                    }
                }
            } else if authStatus == .denied {
                Button("In den iOS-Einstellungen erlauben") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }

            Button {
                Task {
                    await NotificationScheduler.shared.sendTestNotification()
                    testSent = true
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    testSent = false
                }
            } label: {
                HStack {
                    Text("Test-Mitteilung senden")
                    Spacer()
                    if testSent {
                        Text("kommt in 5 Sek.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(authStatus == .denied)
        } header: {
            Text("Mitteilungen")
        } footer: {
            Text("Geplant für die nächsten Tage: \(pendingCount) Mitteilungen. Die Planung wird bei jedem Öffnen der App und nach jeder Änderung erneuert.")
        }
    }

    private func timeSection(title: String, footer: String, isOn: Binding<Bool>, minutes: Binding<Int>) -> some View {
        Section {
            Toggle(title, isOn: isOn.animation())
            if isOn.wrappedValue {
                DatePicker("Uhrzeit", selection: .minutes(minutes), displayedComponents: .hourAndMinute)
            }
        } footer: {
            Text(footer)
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                do {
                    exportDocument = BackupDocument(data: try BackupService.export(ctx))
                    showExporter = true
                } catch {
                    message = "Export fehlgeschlagen: \(error.localizedDescription)"
                }
            } label: {
                Label("Daten exportieren", systemImage: "square.and.arrow.up")
            }
            .fileExporter(isPresented: $showExporter,
                          document: exportDocument,
                          contentType: .json,
                          defaultFilename: "Alltag-Backup-\(Day.today)") { result in
                switch result {
                case .success:
                    message = "Backup gespeichert."
                case .failure(let error):
                    message = "Export fehlgeschlagen: \(error.localizedDescription)"
                }
            }

            Button {
                showImporter = true
            } label: {
                Label("Daten importieren", systemImage: "square.and.arrow.down")
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        importCandidate = try BackupService.decode(data)
                    } catch {
                        message = "Die Datei ist kein gültiges Backup dieser App."
                    }
                case .failure(let error):
                    message = "Import fehlgeschlagen: \(error.localizedDescription)"
                }
            }
            .alert("Backup importieren?",
                   isPresented: Binding(get: { importCandidate != nil }, set: { if !$0 { importCandidate = nil } }),
                   presenting: importCandidate) { backup in
                Button("Alles ersetzen", role: .destructive) {
                    BackupService.restore(backup, into: ctx)
                    importCandidate = nil
                    message = "Import abgeschlossen."
                }
                Button("Abbrechen", role: .cancel) { importCandidate = nil }
            } message: { backup in
                Text("Alle aktuellen Daten werden durch das Backup vom \(Day.mediumDate(Day.key(for: backup.exportedAt))) ersetzt: \(backup.todos.count) To-Dos, \(backup.plans.count) Einheiten, \(backup.sessions.count) Trainings.")
            }
        } header: {
            Text("Datensicherung")
        } footer: {
            Text("Das Backup ist eine JSON-Datei, die du z. B. in der Dateien-App unter „Auf meinem iPhone“ ablegen kannst.")
        }
    }

    // MARK: - Status

    private var statusText: String {
        switch authStatus {
        case .authorized: return "Erlaubt"
        case .denied: return "Abgelehnt"
        case .notDetermined: return "Noch nicht gefragt"
        case .provisional: return "Vorläufig erlaubt"
        case .ephemeral: return "Vorübergehend"
        @unknown default: return "Unbekannt"
        }
    }

    private var statusColor: Color {
        switch authStatus {
        case .authorized, .provisional, .ephemeral: return Theme.accent
        case .denied: return .red
        default: return .secondary
        }
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (Build \(build))"
    }

    private func refreshStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authStatus = settings.authorizationStatus
        pendingCount = await center.pendingNotificationRequests().count
    }
}
