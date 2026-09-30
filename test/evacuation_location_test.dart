import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'package:rapidalert/data/offline_cache.dart';
import 'package:rapidalert/data/reporter_service.dart';
import 'package:rapidalert/models/reporter_models.dart';
import 'package:rapidalert/screens/evacuation_centers_screen.dart';

/// Device GPS: a real fix at [fix], or unavailable (permission denied).
class _FakeGps extends GeolocatorPlatform {
  _FakeGps({this.fix});

  final ({double lat, double lng})? fix;

  @override
  Future<LocationPermission> checkPermission() async =>
      fix == null ? LocationPermission.deniedForever : LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() => checkPermission();

  @override
  Future<bool> isLocationServiceEnabled() async => fix != null;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async => Position(
    latitude: fix!.lat,
    longitude: fix!.lng,
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

class _CentersService extends Fake implements ReporterService {
  final ranked = <({double lat, double lon})>[];

  @override
  Future<EvacuationRankedResult> loadNearestEvacuationCenters({
    required double lat,
    required double lon,
    int groupSize = 1,
    bool fromUserLocation = true,
  }) async {
    ranked.add((lat: lat, lon: lon));
    return EvacuationRankedResult.fromApi({
      'centres': [
        {
          'area_id': 1,
          'name': 'Tibig Covered Court',
          'lat': 13.95,
          'lon': 121.15,
          'capacity': 300,
          'available_slots': 300,
          'status': 'green',
          'status_color': '#22c55e',
          'status_label': 'Ample Capacity',
          'distance_km': 1.4,
          'eta_minutes': 3,
        },
      ],
    });
  }
}

/// Offline, with only a saved copy that was ranked without a real location
/// (so it has no distances or ETAs).
class _OfflineCentersService extends Fake implements ReporterService {
  @override
  Future<EvacuationRankedResult> loadNearestEvacuationCenters({
    required double lat,
    required double lon,
    int groupSize = 1,
    bool fromUserLocation = true,
  }) async => throw http.ClientException('Failed host lookup');

  @override
  Future<CachedCopy<EvacuationRankedResult>?> cachedEvacuationCenters() async => CachedCopy(
    EvacuationRankedResult.fromApi({
      'centres': [
        {
          'area_id': 1,
          'name': 'Tibig Covered Court',
          'lat': 13.95,
          'lon': 121.15,
          'capacity': 300,
          'available_slots': 300,
          'status': 'green',
          'status_color': '#22c55e',
          'status_label': 'Ample Capacity',
        },
      ],
    }),
    DateTime.now().subtract(const Duration(minutes: 10)),
  );
}

void main() {
  final originalGps = GeolocatorPlatform.instance;
  tearDown(() => GeolocatorPlatform.instance = originalGps);

  Future<_CentersService> pumpScreen(WidgetTester tester) async {
    final service = _CentersService();
    await tester.pumpWidget(MaterialApp(home: EvacuationCentersScreen(service: service)));
    await tester.pump();
    await tester.pump();
    return service;
  }

  testWidgets('without GPS: no "you are here" marker, no distances, and a clear message', (tester) async {
    GeolocatorPlatform.instance = _FakeGps();
    await pumpScreen(tester);

    expect(find.textContaining('Your location is unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byIcon(Icons.my_location_rounded), findsNothing);
    expect(find.bySemanticsLabel('Your location'), findsNothing);
    expect(find.textContaining('km'), findsNothing, reason: 'distances would be from Lipa City, not the user');
    expect(find.text('300/300 slots'), findsOneWidget, reason: 'the centers themselves are still listed');
  });

  testWidgets('with a real GPS fix: the marker and distances are shown', (tester) async {
    GeolocatorPlatform.instance = _FakeGps(fix: (lat: 13.935, lng: 121.15));
    final service = await pumpScreen(tester);

    expect(service.ranked.single, (lat: 13.935, lon: 121.15));
    expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
    expect(find.textContaining('Your location is unavailable'), findsNothing);
    expect(find.text('1.4 km · 3 min · 300/300 slots'), findsOneWidget);
  });

  testWidgets('offline, a copy saved without a real location shows no distances even once GPS works', (tester) async {
    GeolocatorPlatform.instance = _FakeGps(fix: (lat: 13.935, lng: 121.15));
    await tester.pumpWidget(MaterialApp(home: EvacuationCentersScreen(service: _OfflineCentersService())));
    await tester.pump();
    await tester.pump();

    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('300/300 slots'), findsOneWidget);
    expect(find.textContaining('km'), findsNothing);
    expect(find.textContaining(' min'), findsNothing);
  });
}
