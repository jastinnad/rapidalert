import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:rapidalert/data/reporter_service.dart';
import 'package:rapidalert/models/reporter_models.dart';
import 'package:rapidalert/screens/evacuation_centers_screen.dart';

/// A real fix in Lipa City.
class _Gps extends GeolocatorPlatform {
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;
  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.whileInUse;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async => Position(
    latitude: 13.9531,
    longitude: 121.1555,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

/// The /api/evacuation/ranked center shape (EvacuationRanker::rank).
Map<String, dynamic> _centre(int id, String name, double? lat, double? lon, double km) => {
  'area_id': id,
  'name': name,
  'lat': lat,
  'lon': lon,
  'capacity': 300,
  'occupied': 0,
  'available_slots': 300,
  'status': 'green',
  'status_color': '#22c55e',
  'status_label': 'Ample Capacity',
  'distance_km': km,
  'eta_minutes': 3,
  'score': 0.1,
  'is_full': false,
  'is_grey': false,
  'directions_url': 'https://www.google.com/maps/dir/?api=1',
};

/// The backend's answer before and after an admin adds "Brand New Hall"
/// next to the user.
final _before = {
  'centres': [
    _centre(18, 'Balintawak Covered Court', 13.9560, 121.1580, 0.4),
    _centre(2, 'Poblacion Barangay 1 Covered Court', 13.9420, 121.1610, 1.3),
    _centre(16, 'Balagbag Covered Court', 13.9660, 121.1500, 1.6),
  ],
};
final _after = {
  'centres': [
    _centre(106, 'Brand New Hall', 13.9535, 121.1557, 0.05),
    _centre(18, 'Balintawak Covered Court', 13.9560, 121.1580, 0.4),
    _centre(2, 'Poblacion Barangay 1 Covered Court', 13.9420, 121.1610, 1.3),
  ],
};

class _Centers extends Fake implements ReporterService {
  _Centers(this.responses);

  final List<Map<String, dynamic>> responses;
  int calls = 0;

  @override
  Future<EvacuationRankedResult> loadNearestEvacuationCenters({
    required double lat,
    required double lon,
    int groupSize = 1,
    bool fromUserLocation = true,
  }) async {
    final json = responses[calls < responses.length ? calls : responses.length - 1];
    calls++;
    return EvacuationRankedResult.fromApi(json);
  }
}

/// The positions of the center pins on the map (the user's own marker excluded).
List<LatLng> _pins(WidgetTester tester) => [
  for (final m in tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers)
    if (m.width == 96) m.point,
];

Future<_Centers> _pump(WidgetTester tester, List<Map<String, dynamic>> responses, {Size size = const Size(412, 915)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final service = _Centers(responses);
  await tester.pumpWidget(MaterialApp(home: EvacuationCentersScreen(service: service)));
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return service;
}

void main() {
  final originalGps = GeolocatorPlatform.instance;
  setUp(() => GeolocatorPlatform.instance = _Gps());
  tearDown(() => GeolocatorPlatform.instance = originalGps);

  group('Ranked centers model', () {
    test('parses a center from the API, including a newly created one', () {
      final result = EvacuationRankedResult.fromApi(_after);
      final first = result.centres.first;
      expect(first.areaId, 106);
      expect(first.name, 'Brand New Hall');
      expect(first.lat, 13.9535);
      expect(first.lon, 121.1557);
      expect(first.availableSlots, 300);
      expect(first.distanceKm, 0.05);
    });

    test('a center without a real position is left out, never placed at 0,0', () {
      final result = EvacuationRankedResult.fromApi({
        'centres': [
          _centre(1, 'Missing Point', null, null, 0.1),
          _centre(2, 'Zero Point', 0, 0, 0.2),
          _centre(3, 'Real Court', 13.95, 121.15, 0.3),
        ],
      });
      expect(result.centres.map((c) => c.name), ['Real Court']);
    });
  });

  group('Evacuation map and list', () {
    testWidgets('a refresh shows a newly created center on the map and as the top card', (tester) async {
      final service = await _pump(tester, [_before, _after]);
      expect(find.text('Brand New Hall'), findsNothing);
      expect(_pins(tester).first, const LatLng(13.9560, 121.1580));

      // Pull to refresh: the screen asks the backend again, no stale copy.
      await tester.fling(find.byType(ListView).last, const Offset(0, 500), 1000);
      await tester.pumpAndSettle();

      expect(service.calls, 2);
      expect(_pins(tester), contains(const LatLng(13.9535, 121.1557)), reason: 'the new center is pinned on the map');
      expect(_pins(tester).first, const LatLng(13.9535, 121.1557));
      expect(find.text('1 · OPEN'), findsOneWidget);
      final topCard = find.byKey(const Key('evacuation-card-106'));
      expect(topCard, findsOneWidget);
      expect(find.descendant(of: topCard, matching: find.byKey(const Key('evacuation-top-pick'))), findsOneWidget);
      expect(find.descendant(of: topCard, matching: find.text('Brand New Hall')), findsOneWidget);
      expect(find.text('Balagbag Covered Court'), findsNothing, reason: 'still the top 3 only');
    });

    testWidgets('each pin and its card carry the same rank number', (tester) async {
      await _pump(tester, [_before]);

      expect(find.text('1 · OPEN'), findsOneWidget);
      expect(find.text('2 · OPEN'), findsOneWidget);
      expect(find.text('3 · OPEN'), findsOneWidget);
      final secondCard = find.byKey(const Key('evacuation-card-2'));
      expect(find.descendant(of: secondCard, matching: find.text('2')), findsOneWidget);
    });

    testWidgets('the map takes about half the screen and the list stays visible', (tester) async {
      await _pump(tester, [_before]);

      final mapBox = tester.getSize(find.byKey(const Key('evacuation-map')));
      expect(mapBox.height, greaterThan(260), reason: 'larger than the old fixed 260 px');
      expect(find.byType(FlutterMap), findsOneWidget);
      final firstCardTop = tester.getTopLeft(find.byKey(const Key('evacuation-card-18'))).dy;
      expect(firstCardTop, lessThan(915), reason: 'the top card is still on screen');
    });

    testWidgets('on a small phone the map keeps a usable minimum and the list still shows', (tester) async {
      await _pump(tester, [_before], size: const Size(360, 640));

      final mapBox = tester.getSize(find.byKey(const Key('evacuation-map')));
      expect(mapBox.height, greaterThanOrEqualTo(240));
      expect(tester.getTopLeft(find.byKey(const Key('evacuation-card-18'))).dy, lessThan(640));
    });

    testWidgets('a Show all control refits the map without pretending to be "my location"', (tester) async {
      await _pump(tester, [_before]);

      expect(find.byKey(const Key('evacuation-show-all')), findsOneWidget);
      expect(find.byTooltip('Show all centers'), findsOneWidget);
      await tester.tap(find.byKey(const Key('evacuation-show-all')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
