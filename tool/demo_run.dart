// Live demo driver — exercises LGConnection against the real rig.
// Same code path the Flutter app uses, no UI layer.
//
// Run with:
//   dart run tool/demo_run.dart
//
// Watch the 3 VM displays on Windows. Each step prints what it's doing,
// then pauses so you can see the rig respond.

import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../lib/connections/lg_connection.dart';
// ignore: avoid_relative_lib_imports
import '../lib/models/lg_config.dart';
// ignore: avoid_relative_lib_imports
import '../lib/utils/connection_log.dart';
// ignore: avoid_relative_lib_imports
import '../lib/utils/kml/kml_makers.dart';

const String logoUrl =
    'https://raw.githubusercontent.com/lucisays/imagen/main/LGMasterWebAppLogo.png';
const double homeLat = 40.4168;
const double homeLng = -3.7038;

void log(String msg) {
  // ignore: avoid_print
  print('[demo] $msg');
}

Future<void> pause(int seconds, String reason) async {
  log('   pause ${seconds}s — $reason');
  await Future<void>.delayed(Duration(seconds: seconds));
}

Future<void> main() async {
  final connLog = ConnectionLog();
  final conn = LGConnection(connLog);
  final cfg = LGConfig.defaults();

  log('=== Live demo: LGConnection vs ${cfg.host}:${cfg.port} ===');
  log('Watch the 3 VM displays on Windows. Each step pauses for visibility.');
  log('');

  log('Step 1/7 — connect()');
  await conn.connect(cfg, 'lqgalaxy');
  log('   isConnected = ${conn.isConnected}');
  await pause(2, 'settled');

  log('Step 2/7 — sendLogo() → slave_3.kml (left screen / lg3)');
  await conn.sendLogo(buildLogoKml(imageUrl: logoUrl));
  await pause(5, 'lg3 should now show LG logo at lower-left');

  log('Step 3/7 — sendPyramidAndFly() → upload + kmls.txt + flytoview Madrid');
  await conn.sendPyramidAndFly(
    buildPyramidKml(centerLat: homeLat, centerLng: homeLng),
    buildLookAtXml(lat: homeLat, lng: homeLng),
  );
  await pause(
    8,
    'all 3 screens fly to Madrid; red pyramid appears across them',
  );

  log('Step 4/7 — flyTo() → camera move only (no KML change)');
  await conn.flyTo(
    buildLookAtXml(
      lat: homeLat,
      lng: homeLng,
      range: 8000, // pull back for a different view
    ),
  );
  await pause(5, 'camera pulls back; pyramid still visible');

  log('Step 5/7 — cleanLogos() → blank slave_3.kml');
  await conn.cleanLogos();
  await pause(4, 'lg3 logo disappears');

  log('Step 6/7 — cleanKml() → exittour, truncate kmls.txt, blank slave_2.kml');
  await conn.cleanKml();
  await pause(4, 'pyramid disappears, default GE view returns');

  log('Step 7/7 — disconnect()');
  await conn.disconnect();
  log('   isConnected = ${conn.isConnected}');

  log('');
  log('=== Demo complete. ${connLog.entries.length} log events captured. ===');
  log('');
  log('Final log entries (newest first):');
  for (final e in connLog.entries.take(20)) {
    log('   ${e.toString()}');
  }
  exit(0);
}
