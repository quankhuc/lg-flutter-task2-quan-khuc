// In-memory ring buffer (50 entries max) of connection events. Drives the
// debug log panel surfaced from HomePage. A fixed-size buffer keeps RAM
// bounded during long demo sessions, keeps ListView.builder snappy, and 50
// entries is plenty of context to triage the most recent failure.
//
// ChangeNotifier is mixed in so widgets rebuild when new entries arrive
// without needing a separate Stream.

import 'package:flutter/foundation.dart';

enum LogSeverity { debug, info, warn, error }

class LogEntry {
  final DateTime timestamp;
  final LogSeverity severity;
  final String message;

  LogEntry(this.severity, this.message) : timestamp = DateTime.now();

  /// Format like "22:14:31  INFO  Connected to 192.168.0.243:2201".
  /// Two-space gaps make the severity column scan easily.
  @override
  String toString() {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s  ${severity.name.toUpperCase().padRight(5)}  $message';
  }
}

class ConnectionLog extends ChangeNotifier {
  /// Capacity is a constant. If you ever want to tune it, expose via Settings.
  static const int _capacity = 50;

  final List<LogEntry> _entries = <LogEntry>[];

  /// Read-only view used by LogPanel. Returns most-recent-first so the panel
  /// shows new events at the top without needing to scroll.
  List<LogEntry> get entries => List.unmodifiable(_entries.reversed);

  void debug(String msg) => _add(LogEntry(LogSeverity.debug, msg));
  void info(String msg) => _add(LogEntry(LogSeverity.info, msg));
  void warn(String msg) => _add(LogEntry(LogSeverity.warn, msg));
  void error(String msg) => _add(LogEntry(LogSeverity.error, msg));

  void _add(LogEntry e) {
    _entries.add(e);
    // Drop oldest when we exceed capacity. removeAt(0) is O(n) but n=51 once,
    // so this is ~50 element shifts per overflow — negligible.
    if (_entries.length > _capacity) {
      _entries.removeAt(0);
    }
    // Mirror to debug console so you can also see logs in `flutter run` output
    // during development. No-op in release builds.
    if (kDebugMode) {
      debugPrint(e.toString());
    }
    notifyListeners();
  }

  /// Used by Settings → "Clear log" debug action.
  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
