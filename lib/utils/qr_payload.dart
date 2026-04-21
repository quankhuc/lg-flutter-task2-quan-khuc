// QR payload codec: encodes/decodes rig connection settings as a URI.
// Schema: lg://USER:PASSWORD@HOST:PORT
// Example: lg://lg:lqgalaxy@192.168.0.243:2201
//
// Using Dart's Uri class gives us free port validation and percent-encoding
// for passwords containing special characters like '@', ':', '/'.
//
// Use case: print this QR as a sticker on the rig wall. Anyone scanning it
// gets all 4 connection params at once and Settings prefills its fields.

import '../models/lg_config.dart';

class QrPayload {
  final LGConfig config;
  final String password;

  QrPayload({required this.config, required this.password});

  /// Encode as a URI string. Password is URI-percent-encoded so special
  /// characters (e.g. '@', ':', '/') don't break parsing on the way back.
  String encode() {
    final user = Uri.encodeComponent(config.user);
    final pw = Uri.encodeComponent(password);
    return 'lg://$user:$pw@${config.host}:${config.port}';
  }

  /// Decode a scanned URI string. Returns null if the scheme isn't 'lg' or
  /// any required field is missing — callers show "Invalid QR" toast on null.
  static QrPayload? tryDecode(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'lg') return null;
    if (uri.host.isEmpty || uri.port == 0 || uri.userInfo.isEmpty) return null;
    final parts = uri.userInfo.split(':');
    if (parts.length != 2) return null;
    final user = Uri.decodeComponent(parts[0]);
    final pw = Uri.decodeComponent(parts[1]);
    if (user.isEmpty || pw.isEmpty) return null;
    return QrPayload(
      config: LGConfig(
        host: uri.host,
        port: uri.port,
        user: user,
        screens: 3, // QR doesn't carry screen count; uses default
      ),
      password: pw,
    );
  }
}
