// Concrete dartssh2 implementation of LGConnectionInterface.
//
// Architecture (unified per-slave polling): there are N screens. Each polls
// /var/www/html/kml/slave_$N.kml on master's Apache every 2 seconds. To put
// content on screen N, write to that file. One mechanism, symmetric across
// screens, no NLC ghosts.
//
// Design choices:
//   1. SFTP for all file writes. Eliminates shell-injection risk on KMLs
//      with single quotes (SFTP is binary, no shell parsing).
//   2. dartssh2's built-in keepAliveInterval prevents the server's idle
//      timeout from killing the session during a demo.
//   3. SFTP channel opened once at connect-time and reused across all writes
//      (~50ms saving per write).
//   4. sendPyramidAndFly and cleanKml deliberately skip the left-most slave
//      so the logo stays visible for the duration of the demo (Task 2 spec).
//   5. hardReset is the debug-only nuclear option: blanks all slaves, truncates
//      kmls.txt, and pkills + relaunches googleearth-bin on all N VMs (parallel
//      kill, staggered relaunch to avoid a RAM spike). Recovers from NLC ghosts
//      left by other LG apps (SatNOGS, Data Spaces) and from slave GE crashes.
//      Uses LG's standard passwordless intra-rig SSH from lg1 to lg2..lgN.
//
// Standard rig paths used:
//   - Per-screen content: /var/www/html/kml/slave_$N.kml
//   - GE command channel: /tmp/query.txt
//   - Legacy master manifest (only touched by hardReset): /var/www/html/kmls.txt
//
// Prerequisite: each VM (lg1, lg2, lg3) must have a NetworkLink in its
// ~/.googleearth/myplaces.kml pointing to its slave_$N.kml on master's web.
// Run scripts/rig-setup-slaves.sh once to install. Idempotent.

import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../models/lg_config.dart';
import '../utils/connection_log.dart';
import 'lg_connection_interface.dart';

class LGConnection implements LGConnectionInterface {
  /// The active SSH client. Null when disconnected.
  SSHClient? _client;

  /// The active SFTP subsystem. Opened once at connect() and reused for all
  /// file writes. Null when disconnected.
  SftpClient? _sftp;

  /// The config that was used for the current connection. Useful for log
  /// messages like "Connected to `host`:`port`".
  LGConfig? _activeConfig;

  /// Reference to the shared connection log so this class can write info /
  /// warn / error events that surface in the LogPanel widget.
  final ConnectionLog _log;

  LGConnection(this._log);

  @override
  bool get isConnected => _client != null && _sftp != null;

  // -------- connect() --------
  // Opens TCP socket → SSH handshake → authenticate with password →
  // open SFTP subsystem. dartssh2 starts its own keepalive timer based on
  // keepAliveInterval — we don't need our own.
  @override
  Future<void> connect(LGConfig cfg, String password) async {
    // Bail if already connected so we don't leak resources.
    if (isConnected) {
      _log.warn('connect() called while already connected; ignoring');
      return;
    }

    _log.info('Connecting to ${cfg.host}:${cfg.port} as ${cfg.user}...');

    // 10-second TCP timeout. If the rig is unreachable we want to fail fast
    // so the UI can show a clear error rather than spin forever.
    final socket = await SSHSocket.connect(
      cfg.host,
      cfg.port,
      timeout: const Duration(seconds: 10),
    );

    // Build the SSH client. keepAliveInterval makes dartssh2 send SSH-level
    // keepalives every 10s — prevents the server's idle-timeout from killing
    // our session during the demo.
    _client = SSHClient(
      socket,
      username: cfg.user,
      onPasswordRequest: () => password,
      keepAliveInterval: const Duration(seconds: 10),
    );

    // Wait for the SSH key exchange + auth to complete. Throws SSHAuthFailError
    // if the password is wrong, SSHStateError if the connection drops.
    await _client!.authenticated;

    // Open the SFTP subsystem once. All file writes route through this single
    // channel. Avoids ~50ms of subsystem-open overhead per write.
    _sftp = await _client!.sftp();

    _activeConfig = cfg;
    _log.info('Connected to ${cfg.host}:${cfg.port}');
  }

  // -------- disconnect() --------
  // Cleanly tears down both SFTP and the SSH client. Safe to call when
  // already disconnected (the null checks make it idempotent).
  @override
  Future<void> disconnect() async {
    if (!isConnected) return;
    // SftpClient.close() returns void synchronously (it just closes the
    // channel state); don't await it.
    _sftp?.close();
    _client?.close();
    _client = null;
    _sftp = null;
    _log.info('Disconnected from ${_activeConfig?.host}');
    _activeConfig = null;
  }

  // -------- _sftpWrite() --------
  // Single private helper that all 5 button verbs use. Writes a UTF-8 string
  // to a remote path via SFTP. Truncates if the file already exists, creates
  // it if it doesn't.
  //
  // Why this exists as a helper instead of inlined: it appears 10+ times
  // across the verb methods. Centralizing it means we only have one place to
  // adjust (e.g., to add retry logic, or to switch to streamed writes for
  // large files).
  Future<void> _sftpWrite(String path, String content) async {
    if (_sftp == null) {
      throw StateError('Not connected — call connect() first');
    }
    final f = await _sftp!.open(
      path,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    // .write() takes a Stream<Uint8List>. For our small KMLs (<10KB) we wrap
    // the encoded bytes in a single-element stream. For larger files we'd
    // chunk; not needed at this scale.
    await f.write(Stream.value(utf8.encode(content)).cast());
    await f.close();
    _log.debug('SFTP wrote ${content.length}B to $path');
  }

  // -------- sendLogo() --------
  // Writes the logo ScreenOverlay KML to the left-most slave's KML file.
  // That slave polls slave_$N.kml every 2s and shows whatever's in it.
  @override
  Future<void> sendLogo(String logoKml) async {
    final left = _activeConfig?.leftMostScreen ?? 3;
    await _sftpWrite('/var/www/html/kml/slave_$left.kml', logoKml);
    _log.info('Sent logo to slave_$left');
  }

  // -------- sendPyramidAndFly() --------
  // Pyramid on every screen EXCEPT the left-most (logo lives there per Task 2
  // spec — "logo visible during all the demo"). Then flytoview broadcasts the
  // camera to all 3 screens via ViewSync.
  //
  // For 3-screen rig: pyramid on slave_1 (master/center) + slave_2 (right);
  // slave_3 (left) keeps its logo. Visually: pyramid spans 2/3 screens,
  // logo holds on slave_3, all 3 cameras flew to Madrid.
  @override
  Future<void> sendPyramidAndFly(String pyramidKml, String lookAtXml) async {
    final left = _activeConfig?.leftMostScreen ?? 3;
    final n = _activeConfig?.screens ?? 3;
    // Parallel SFTP writes over the same SSH tunnel. dartssh2 multiplexes SFTP
    // operations on the channel so concurrent open/write/close calls all ride
    // a single TCP session — much faster than sequential await for N>1.
    final writes = <Future<void>>[
      for (var i = 1; i <= n; i++)
        if (i != left) _sftpWrite('/var/www/html/kml/slave_$i.kml', pyramidKml),
      _sftpWrite('/tmp/query.txt', 'flytoview=$lookAtXml'),
    ];
    await Future.wait(writes);
    _log.info('Sent pyramid (skipped slave_$left for logo) + flyTo');
  }

  // -------- flyTo() --------
  // Pure camera move. Doesn't change any KML — ViewSync broadcasts the new
  // camera position from master to all slaves.
  @override
  Future<void> flyTo(String lookAtXml) async {
    await _sftpWrite('/tmp/query.txt', 'flytoview=$lookAtXml');
    _log.info('flyTo issued');
  }

  // -------- cleanLogos() --------
  // Blanks the left-most slave's file. Logo disappears within ~2s (next poll).
  @override
  Future<void> cleanLogos() async {
    final left = _activeConfig?.leftMostScreen ?? 3;
    await _sftpWrite('/var/www/html/kml/slave_$left.kml', _blankSlaveKml(left));
    _log.info('Cleaned logos on slave_$left');
  }

  // -------- cleanKml() --------
  // Reset verb: blanks EVERY slave (pyramid AND logo) and halts any tour.
  // Pair this with flyTo(home) at the call site to also return the camera
  // and trigger the onStop view-refresh so the blanks appear immediately
  // instead of waiting for the 30s poll fallback.
  @override
  Future<void> cleanKml() async {
    final n = _activeConfig?.screens ?? 3;
    final writes = <Future<void>>[
      for (var i = 1; i <= n; i++)
        _sftpWrite('/var/www/html/kml/slave_$i.kml', _blankSlaveKml(i)),
      _sftpWrite('/tmp/query.txt', 'exittour=true'),
    ];
    await Future.wait(writes);
    _log.info('Cleaned all $n slave KMLs');
  }

  // -------- hardReset() --------
  // Debug-only nuclear option. Use when:
  //   (a) Ghost content (e.g., NLC children from the Data Spaces app via
  //       kmls.txt) lingers in master's GE scene graph and ordinary cleanKml
  //       can't evict it.
  //   (b) A slave's GE crashed (SIGSEGV in Qt event loop is a known
  //       intermittent crash — see crashlogs in ~/.googleearth/crashlogs/).
  //       Openbox autostart does NOT respawn GE mid-session, so the slave
  //       stays black until manually relaunched.
  //
  // Blanks ALL slave files, truncates kmls.txt, then pkills + relaunches
  // googleearth-bin on ALL N VMs. lg1 runs locally; lg2..lgN via LG's
  // standard passwordless intra-rig SSH.
  //
  // RAM-aware restart strategy:
  //   1. Parallel pkill — frees all GE RAM instantly, simultaneously.
  //   2. Staggered relaunch (5s gaps) — prevents N GEs from hitting their
  //      heavy init-memory peak at the same time, which would thrash swap
  //      on RAM-tight slaves (lg2 typically has ~200 MB free).
  //
  // Task 1 compatibility: we don't touch sync_nlc.php or Data Spaces files.
  // The kmls.txt truncate is benign — Task 1's app overwrites it on every
  // Malaga/Santander/Lleida click. When GE comes back up on each VM it
  // re-reads myplaces.kml and re-subscribes to all NetworkLinks, so Data
  // Spaces resumes normally.
  @override
  Future<void> hardReset() async {
    final n = _activeConfig?.screens ?? 3;
    final writes = <Future<void>>[
      for (var i = 1; i <= n; i++)
        _sftpWrite('/var/www/html/kml/slave_$i.kml', _blankSlaveKml(i)),
      _sftpWrite('/var/www/html/kmls.txt', ''),
    ];
    await Future.wait(writes);

    await _client?.run(buildHardResetCommand(n));
    _log.warn(
        'Hard reset issued — all $n VMs\' GE restarting (~${20 + (n - 1) * 5}s)');
  }

  // -------- buildHardResetCommand() --------
  // Builds the shell pipeline sent to lg1 for the pkill+relaunch phase of
  // hardReset(). Extracted from hardReset() so tests can exercise the exact
  // bytes sent over SSH.
  //
  // Separator is \n, NOT '; '. Reason: several parts end with `&` (backgrounded
  // pkill/ssh). Joining with '; ' produces `cmd &; next` which is a bash
  // syntax error ("unexpected token `;'"). Newlines are a legal statement
  // terminator in bash and interact correctly with backgrounded commands.
  @visibleForTesting
  static String buildHardResetCommand(int n) {
    const relaunch = 'DISPLAY=:0 nohup /opt/google/earth/pro/googleearth-bin '
        '>/tmp/ge.log 2>&1 < /dev/null & disown';
    const sshOpts =
        '-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=3';
    final parts = <String>[
      'pkill -9 googleearth-bin &',
      for (var i = 2; i <= n; i++)
        'ssh $sshOpts lg@lg$i "pkill -9 googleearth-bin" &',
      'wait',
      'sleep 2',
      relaunch,
      for (var i = 2; i <= n; i++) ...[
        'sleep 5',
        'ssh $sshOpts lg@lg$i "$relaunch"',
      ],
    ];
    return parts.join('\n');
  }

  /// Produces a minimal well-formed KML that GE accepts as "no content".
  String _blankSlaveKml(int slaveNumber) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<kml xmlns="http://www.opengis.net/kml/2.2">\n'
      '  <Document><name>slave_$slaveNumber</name></Document>\n'
      '</kml>';
}
