// Immutable rig connection config. Password is not a field here — it lives
// in flutter_secure_storage and is passed alongside the LGConfig at
// connect-time so the model can be safely logged or serialized to
// SharedPreferences without leaking the credential. Immutable so that when
// the user edits Settings and reconnects, Provider's notifyListeners() has a
// clear before/after to react to.

class LGConfig {
  /// Hostname or IP. For our dev loop (Mac → Windows VBox port forwards), this
  /// defaults to the Windows host's LAN IP. From inside a Windows-hosted
  /// emulator (BlueStacks or Windows AVD), '10.0.2.2' is the correct alternative.
  final String host;

  /// SSH port. Defaults to 2201 (Windows VBox forward → lg1:22).
  final int port;

  /// SSH username. The rig's default is 'lg' across all 3 VMs.
  final String user;

  /// Number of screens in the rig. Defaults to 3, which is what Task 2
  /// requires. Used by the left/right-most-screen formulas below.
  final int screens;

  const LGConfig({
    required this.host,
    required this.port,
    required this.user,
    this.screens = 3,
  });

  /// Sensible defaults for a fresh install. Used by SettingsPage when
  /// SharedPreferences has no saved config yet.
  factory LGConfig.defaults() =>
      const LGConfig(host: '192.168.0.243', port: 2201, user: 'lg', screens: 3);

  /// Returns a copy with selected fields replaced. Standard Dart immutable-data
  /// pattern. Use this in SettingsPage when the user edits one field.
  LGConfig copyWith({String? host, int? port, String? user, int? screens}) =>
      LGConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        user: user ?? this.user,
        screens: screens ?? this.screens,
      );

  /// The screen index that's furthest LEFT in the rig. For 3 screens this is
  /// slave_3 (lg3). Logo button writes its KML to /var/www/html/kml/slave_3.kml.
  /// Formula from the LG-Master-Web-App reference project.
  int get leftMostScreen => screens == 1 ? 1 : (screens / 2).floor() + 2;

  /// The screen index that's furthest RIGHT. For 3 screens this is slave_2
  /// (lg2). Used by Clean KMLs to blank that screen's overlay.
  /// Formula from the LG-Master-Web-App reference project.
  int get rightMostScreen => screens == 1 ? 1 : (screens / 2).floor() + 1;

  /// String representation safe to log (no password).
  @override
  String toString() => 'LGConfig($user@$host:$port, screens=$screens)';
}
