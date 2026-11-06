# Alltag

Persönliche iPhone-App (SwiftUI, iOS 17+) für Training, Kalender und To-Dos.
Alle Daten bleiben lokal auf dem iPhone.

- Bei jedem Push auf `main` baut GitHub Actions eine unsignierte `Alltag.ipa`.
- Download: Release **„neueste“** (rechts auf der Repository-Seite) oder unter *Actions → Lauf → Artifacts*.
- Installation und 7-Tage-Refresh über AltStore.

Projektstruktur:

```
project.yml                 XcodeGen-Konfiguration (erzeugt das Xcode-Projekt)
Config/Info.plist           App-Einstellungen
.github/workflows/build.yml Build auf macOS-Runner
Alltag/                     Swift-Quellcode und Assets
```

Wichtig: Die Bundle-ID `de.privat.alltag` in `project.yml` nie ändern.
