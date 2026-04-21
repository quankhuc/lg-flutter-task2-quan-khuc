# lg_flutter_task2 — GSoC 2026 Task 2

Flutter app that controls a 3-screen Liquid Galaxy rig over SSH. Five buttons
for the GSoC 2026 pre-selection Task 2 demo:

1. **Send LG Logo** — ScreenOverlay KML onto the left-most screen
2. **Send Pyramid + Fly** — 3D pyramid KML spanning the non-logo screens + camera flyTo
3. **Fly Home** — camera move only, no content change
4. **Clean Logos** — blank the left-most screen's overlay
5. **Reset** — blank all slaves and fly to a world-level view

## Setup

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Default rig host is `192.168.0.243:2201`. Change in Settings inside the app.

## Rig requirements

Each VM needs `~/.googleearth/myplaces.kml` with a NetworkLink pointing at
`http://lg1:81/kml/slave_<N>.kml` with `<refreshMode>onInterval` and
`<refreshInterval>3</refreshInterval>`. The master (lg1) additionally needs
the static `master.kml` and `sync_nlc.php` NetworkLinks if the rig is shared
with apps using the `kmls.txt` flow.

Apache on lg1 must serve `/var/www/html/` on port 81.

## Architecture

```
lib/
├── main.dart                         MaterialApp + MultiProvider entry
├── theme/app_theme.dart              Material 3, emerald seed
├── connections/
│   ├── lg_connection.dart            dartssh2 wrapper (SFTP-only writes)
│   └── lg_connection_interface.dart  testability seam for provider tests
├── providers/
│   └── connection_provider.dart      ChangeNotifier; secure storage for password
├── pages/
│   ├── splash_page.dart              auto-reconnect with min-display + timeout
│   ├── settings_page.dart            form + QR scan + Connect/Disconnect
│   ├── home_page.dart                5 buttons + status badge + log sheet
│   └── qr_scan_page.dart             mobile_scanner full-screen
├── models/lg_config.dart             immutable rig config
└── utils/
    ├── kml/kml_makers.dart           pure KML builders + xmlEscape
    ├── connection_log.dart           ring buffer + ChangeNotifier
    └── qr_payload.dart               lg:// URI codec
```

## Tests

```bash
flutter test
```

49 tests total:

- `kml_makers_test.dart` — KML builders vs golden fixtures
- `qr_payload_test.dart` — URI codec round-trip + edge cases
- `connection_provider_test.dart` — provider state machine with fake SSH
- `widgets/home_page_test.dart` — button presence, enabled state, tap routing
- `lg_connection_paths_test.dart` — path-asserting regression net (catches
  wrong-file-written bugs)

## Build APK

```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

## Credits

- LG logo PNG hosted by the [LG-Master-Web-App](https://github.com/LiquidGalaxyLAB/LG-Master-Web-App)
  project (2025 GSoC contributor Lucía F. Giner)
- Pyramid KML is original (see `lib/utils/kml/kml_makers.dart`)

## License

MIT — see `LICENSE` file.
