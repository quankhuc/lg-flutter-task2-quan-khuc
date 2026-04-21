// Pure functions that build KML strings from typed inputs. No I/O, no SSH,
// no async. Every function is deterministic — same inputs produce the same
// output — which is what makes the golden-fixture tests possible: we commit
// a known-good output to test/fixtures/ and CI fails if any future change
// produces a different string.
//
// Golden-fixture rule: if you change the output of any of these functions,
// you must also update the matching test/fixtures/*.kml file. The test
// failure will tell you which file. Verify the new output renders correctly
// in Google Earth desktop before updating the fixture.

/// Escapes the 5 XML-significant characters. Apply to any user-supplied text
/// (city name, custom labels) before it's interpolated into a KML string.
///
/// Order matters: '&' must be replaced FIRST, otherwise '&amp;' from later
/// substitutions would itself get escaped to '&amp;amp;'.
String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll("'", '&apos;')
    .replaceAll('"', '&quot;');

/// Wraps a body fragment in the standard KML envelope. All 5 builders that
/// produce full KML documents use this.
String _kmlEnvelope(String body) => '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<kml xmlns="http://www.opengis.net/kml/2.2">\n'
    '  <Document>\n'
    '$body\n'
    '  </Document>\n'
    '</kml>\n';

/// Builds a ScreenOverlay KML that shows a logo image at upper-left.
///
/// [imageUrl] must be reachable from the Liquid Galaxy itself (the rig's
/// Google Earth fetches the image, not the phone). A public GitHub raw URL
/// works well:
///   https://raw.githubusercontent.com/`user`/`repo`/main/assets/lg_logo.png
///
/// Positioning math (corrected after a live demo overflowed off the top):
///   - overlayXY (0, 1) anchors the TOP-LEFT corner of the overlay so the
///     logo extends DOWN from the anchor and never clips off the top of
///     the screen regardless of image height.
///   - screenXY (0.02, 0.95) pins that anchor at 2% from left and 95% from
///     bottom (= 5% from top), just inside the screen edge.
String buildLogoKml({
  required String imageUrl,
  double sizeWidthPx = 554,
  double sizeHeightPx = 500,
}) {
  final body = '''    <name>LG Logo</name>
    <ScreenOverlay>
      <name>LG Logo</name>
      <Icon><href>${xmlEscape(imageUrl)}</href></Icon>
      <overlayXY x="0" y="1" xunits="fraction" yunits="fraction"/>
      <screenXY x="0.02" y="0.95" xunits="fraction" yunits="fraction"/>
      <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
      <size x="$sizeWidthPx" y="$sizeHeightPx" xunits="pixels" yunits="pixels"/>
    </ScreenOverlay>''';
  return _kmlEnvelope(body);
}

/// Builds a 4-sided 3D pyramid KML centered on (lat, lng) with an apex
/// [heightMeters] above ground. Sides are [sideColor], base is [baseColor].
///
/// Colors use KML's ABGR hex format (NOT standard RGB). Defaults give a
/// semi-transparent red pyramid with a semi-transparent yellow base, chosen
/// for visibility against typical Google Earth backgrounds.
///
/// Footprint width is approximately [footprintMeters] in both lat/lng
/// directions. The meters-to-degrees conversion uses the rough approximation
/// 1 degree latitude ≈ 111,000 m — good enough at this display range, not
/// for precision GIS work.
String buildPyramidKml({
  required double centerLat,
  required double centerLng,
  double heightMeters = 1000,
  double footprintMeters = 100,
  String sideColor = 'cc0000ff',
  String baseColor = 'cc00ffff',
}) {
  // Convert footprint half-width (meters) to a delta in degrees. This is a
  // crude approximation that ignores latitude shrinkage of longitude degrees.
  // For a 100m footprint anywhere outside the poles the error is invisible
  // at our display range.
  final halfDeg = (footprintMeters / 2) / 111000.0;

  final nwLat = centerLat + halfDeg, nwLng = centerLng - halfDeg;
  final neLat = centerLat + halfDeg, neLng = centerLng + halfDeg;
  final seLat = centerLat - halfDeg, seLng = centerLng + halfDeg;
  final swLat = centerLat - halfDeg, swLng = centerLng - halfDeg;

  // Helper to build one triangular face from two ground corners + apex.
  String face(String name, double aLng, double aLat, double bLng, double bLat) {
    return '''    <Placemark>
      <name>$name</name>
      <styleUrl>#pyramidSide</styleUrl>
      <Polygon>
        <altitudeMode>relativeToGround</altitudeMode>
        <outerBoundaryIs><LinearRing><coordinates>
          $aLng,$aLat,0 $bLng,$bLat,0 $centerLng,$centerLat,$heightMeters $aLng,$aLat,0
        </coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  final body = '''    <name>3D Pyramid</name>
    <Style id="pyramidSide">
      <PolyStyle><color>$sideColor</color><fill>1</fill><outline>1</outline></PolyStyle>
      <LineStyle><color>ff000000</color><width>2</width></LineStyle>
    </Style>
    <Style id="pyramidBase">
      <PolyStyle><color>$baseColor</color><fill>1</fill></PolyStyle>
    </Style>
${face('Face N', nwLng, nwLat, neLng, neLat)}
${face('Face E', neLng, neLat, seLng, seLat)}
${face('Face S', seLng, seLat, swLng, swLat)}
${face('Face W', swLng, swLat, nwLng, nwLat)}
    <Placemark>
      <name>Base</name>
      <styleUrl>#pyramidBase</styleUrl>
      <Polygon>
        <altitudeMode>clampToGround</altitudeMode>
        <outerBoundaryIs><LinearRing><coordinates>
          $nwLng,$nwLat,0 $neLng,$neLat,0 $seLng,$seLat,0 $swLng,$swLat,0 $nwLng,$nwLat,0
        </coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  return _kmlEnvelope(body);
}

/// Builds a bare `<LookAt>` XML fragment (NOT wrapped in kml/Document) used
/// as the value of the `flytoview=` command written to /tmp/query.txt.
///
/// Defaults are tuned for a ~1km-tall pyramid:
///   range=4500 places the camera ~4.5x the object height away.
///   tilt=60   gives a 3D oblique view (vs straight-down at tilt=0).
String buildLookAtXml({
  required double lat,
  required double lng,
  double altitude = 0,
  double range = 4500,
  double tilt = 60,
  double heading = 0,
}) {
  return '<LookAt>'
      '<longitude>$lng</longitude>'
      '<latitude>$lat</latitude>'
      '<altitude>$altitude</altitude>'
      '<heading>$heading</heading>'
      '<tilt>$tilt</tilt>'
      '<range>$range</range>'
      '<altitudeMode>relativeToGround</altitudeMode>'
      '</LookAt>';
}

/// Builds an empty-but-well-formed KML used by clean-buttons. GE rejects
/// truly empty files; a Document with just a name is silent.
String blankSlaveKml(int slaveNumber) =>
    _kmlEnvelope('    <name>slave_$slaveNumber</name>');
