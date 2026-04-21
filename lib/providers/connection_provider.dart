// ChangeNotifier that owns the single LGConnection, the rig config, and
// credential storage. Widgets react to connection state changes (badge
// color, button enable/disable) by listening to this provider.
//
// State responsibilities:
//   - Hold the current LGConfig (host/port/user/screens).
//   - Hold the connected/disconnected/connecting state + last error message.
//   - Persist non-sensitive config to SharedPreferences.
//   - Persist the password to flutter_secure_storage (Keystore-backed on
//     Android) so it never lands on disk in plain text.
//   - Wrap each LGConnection verb so the UI never touches the connection
//     directly.
//
// What it does NOT do: build KMLs (that's kml_makers), format toasts (the
// page owns that), or hold per-widget UI state like _busy.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../connections/lg_connection.dart';
import '../connections/lg_connection_interface.dart';
import '../models/lg_config.dart';
import '../utils/connection_log.dart';

class ConnectionProvider extends ChangeNotifier {
  // Dependencies are injected so this class is testable. In tests we pass a
  // MockLGConnectionInterface and an in-memory SharedPreferences.

  final LGConnectionInterface _conn;
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final ConnectionLog _log;

  // Storage keys. Constants so a typo doesn't silently lose data.
  static const _kHost = 'lg_host';
  static const _kPort = 'lg_port';
  static const _kUser = 'lg_user';
  static const _kScreens = 'lg_screens';
  static const _kPassword = 'lg_password'; // goes to secure storage, not prefs

  ConnectionProvider({
    required LGConnectionInterface connection,
    required SharedPreferences prefs,
    required FlutterSecureStorage secureStorage,
    required ConnectionLog log,
  })  : _conn = connection,
        _prefs = prefs,
        _secure = secureStorage,
        _log = log {
    _config = _loadConfigFromPrefs();
  }

  // ---- Public state (read by widgets) ----

  /// The currently-active or last-attempted config. Always set (loaded from
  /// prefs at construction; defaults if no saved value).
  late LGConfig _config;
  LGConfig get config => _config;

  bool get isConnected => _conn.isConnected;

  /// Tracks whether a connect() is in flight. Drives the "Connecting..." badge.
  bool _connecting = false;
  bool get isConnecting => _connecting;

  /// Last connection error, for tooltip / debug log. Null when no error.
  String? _lastError;
  String? get lastError => _lastError;

  /// The shared log instance (passed through to LGConnection); widgets read
  /// it for the LogPanel.
  ConnectionLog get log => _log;

  // ---- Public actions (called by widgets) ----

  /// Open a connection using the given config + password. On success, persists
  /// both. On failure, _lastError is set and listeners are notified.
  Future<void> connectWith(LGConfig newConfig, String password) async {
    _connecting = true;
    _lastError = null;
    notifyListeners();
    try {
      await _conn.connect(newConfig, password);
      _config = newConfig;
      await _persistConfig(newConfig);
      await _secure.write(key: _kPassword, value: password);
    } catch (e) {
      _lastError = e.toString();
      _log.error('connect failed: $e');
      rethrow; // let the page show its own toast too
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Try to reconnect using saved config + password. Used by the splash for
  /// auto-reconnect. Returns true on success, false on any failure (so the
  /// splash can route to Settings without throwing).

  Future<bool> tryAutoReconnect() async {
    final saved = await _secure.read(key: _kPassword);
    if (saved == null || saved.isEmpty) {
      _log.debug('No saved password — skipping auto-reconnect');
      return false;
    }
    try {
      await connectWith(_config, saved);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    await _conn.disconnect();
    notifyListeners();
  }

  // ---- 5 verb wrappers (called by HomePage button handlers) ----
  // Each wrapper just delegates. No try/catch here — the page wraps with its
  // own snackbar feedback. The provider stays narrowly responsible for state.

  Future<void> sendLogo(String kml) => _conn.sendLogo(kml);
  Future<void> sendPyramidAndFly(String kml, String lookAt) =>
      _conn.sendPyramidAndFly(kml, lookAt);
  Future<void> flyTo(String lookAt) => _conn.flyTo(lookAt);
  Future<void> cleanLogos() => _conn.cleanLogos();
  Future<void> cleanKml() => _conn.cleanKml();

  /// Debug-only nuclear cleanup. Triggers `pkill -9 googleearth-bin` on master.
  /// GE auto-relaunches in ~10s with a clean scene graph. Use only when ghost
  /// content from other LG apps lingers after ordinary cleanKml.
  Future<void> hardReset() => _conn.hardReset();

  // ---- Internal helpers ----

  LGConfig _loadConfigFromPrefs() {
    final defaults = LGConfig.defaults();
    return LGConfig(
      host: _prefs.getString(_kHost) ?? defaults.host,
      port: _prefs.getInt(_kPort) ?? defaults.port,
      user: _prefs.getString(_kUser) ?? defaults.user,
      screens: _prefs.getInt(_kScreens) ?? defaults.screens,
    );
  }

  Future<void> _persistConfig(LGConfig c) async {
    await _prefs.setString(_kHost, c.host);
    await _prefs.setInt(_kPort, c.port);
    await _prefs.setString(_kUser, c.user);
    await _prefs.setInt(_kScreens, c.screens);
  }

  /// Factory used by main.dart at startup. Wires real implementations.
  static Future<ConnectionProvider> create() async {
    final prefs = await SharedPreferences.getInstance();
    final log = ConnectionLog();
    final conn = LGConnection(log);
    return ConnectionProvider(
      connection: conn,
      prefs: prefs,
      secureStorage: const FlutterSecureStorage(),
      log: log,
    );
  }
}
