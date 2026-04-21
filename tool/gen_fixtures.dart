// Regenerates test/fixtures/*.kml from kml_makers.dart. Run after
// intentionally changing a builder's output so the matching golden test
// picks up the new expected value.
//
// Run with: dart run tool/gen_fixtures.dart

import 'dart:io';
// Tool scripts use relative import to avoid package: dance for one-off scripts.
// ignore: avoid_relative_lib_imports
import '../lib/utils/kml/kml_makers.dart';

void main() {
  Directory('test/fixtures').createSync(recursive: true);

  File('test/fixtures/golden_logo.kml').writeAsStringSync(
    buildLogoKml(
      imageUrl:
          'https://raw.githubusercontent.com/lucisays/imagen/main/LGMasterWebAppLogo.png',
    ),
  );

  File(
    'test/fixtures/golden_pyramid_madrid.kml',
  ).writeAsStringSync(buildPyramidKml(centerLat: 40.4168, centerLng: -3.7038));

  File(
    'test/fixtures/golden_lookat_madrid.kml',
  ).writeAsStringSync(buildLookAtXml(lat: 40.4168, lng: -3.7038));

  File(
    'test/fixtures/golden_blank_slave_3.kml',
  ).writeAsStringSync(blankSlaveKml(3));

  // ignore: avoid_print — tool script, stdout is the intended channel.
  print('Generated 4 golden fixtures.');
}
