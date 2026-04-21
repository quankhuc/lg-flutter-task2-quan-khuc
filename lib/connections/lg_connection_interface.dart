// Abstract contract for LGConnection. The real dartssh2-backed LGConnection
// and the test-only FakeLGConnection both implement this. The interface
// exists so that ConnectionProvider can be unit-tested in pure Dart without
// needing a real SSH server.

import '../models/lg_config.dart';

abstract class LGConnectionInterface {
  /// Whether an SSH session is currently authenticated and usable.
  bool get isConnected;

  /// Open an SSH+SFTP session to the rig. Throws on TCP timeout, auth failure,
  /// or SFTP subsystem failure. Caller (ConnectionProvider) catches and
  /// surfaces as a toast + log entry.
  Future<void> connect(LGConfig cfg, String password);

  /// Close the SSH session cleanly. Safe to call when already disconnected.
  Future<void> disconnect();

  /// Send the LG logo as a ScreenOverlay KML to the left-most slave.
  /// Caller passes the pre-built KML string from kml_makers.dart.
  Future<void> sendLogo(String logoKml);

  /// Upload a KML body and tell the master to load it via kmls.txt + flyTo.
  /// pyramidKml is the full KML document (from kml_makers.dart).
  /// lookAtXml is the LookAt fragment ONLY (no envelope) — gets prefixed with
  /// 'flytoview=' before being written to /tmp/query.txt.
  Future<void> sendPyramidAndFly(String pyramidKml, String lookAtXml);

  /// Just the camera move. Does not change any KML files.
  Future<void> flyTo(String lookAtXml);

  /// Blank the left-most slave's KML so its logo ScreenOverlay disappears.
  /// Paired counterpart to sendLogo(). Leaves pyramid screens untouched.
  Future<void> cleanLogos();

  /// Stop any tour, blank slave_1.kml + slave_2.kml. Does NOT touch the
  /// left-most slave (slave_3 — logo stays unless the user also taps Clean Logos).
  Future<void> cleanKml();

  /// Debug-only nuclear option: blank ALL slave files, truncate kmls.txt,
  /// and pkill googleearth-bin on master so autostart relaunches GE with a
  /// clean scene graph. Use when ghost content (e.g., NLC children from
  /// other LG apps) lingers and ordinary cleanKml can't evict it.
  Future<void> hardReset();
}
