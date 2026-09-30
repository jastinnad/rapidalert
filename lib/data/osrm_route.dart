import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Fetches a real road-following route between two points from the public
/// OSRM demo server — the same routing backend the website already uses
/// (see `DisasterDecisionSupportService::routeDetails()` and `evacuation.js`
/// on the web side), so mobile and web draw routes the same way instead of
/// a straight line cutting through buildings.
///
/// Returns null on any failure (timeout, no route found, bad response) so
/// callers can fall back to a straight line, matching the website's own
/// fallback behavior.
Future<List<LatLng>?> fetchRoadRoute(LatLng origin, LatLng destination) async =>
    (await fetchRoadRouteDetails(origin, destination))?.points;

/// A road route with OSRM's own driving estimate. [duration] is OSRM's
/// free-flow figure (no live traffic), so show it as an estimate.
class RoadRoute {
  const RoadRoute({required this.points, required this.distanceMeters, required this.duration});

  final List<LatLng> points;
  final double? distanceMeters;
  final Duration? duration;
}

Future<RoadRoute?> fetchRoadRouteDetails(LatLng origin, LatLng destination) async {
  final url = Uri.parse(
    'https://router.project-osrm.org/route/v1/driving/'
    '${origin.longitude},${origin.latitude};'
    '${destination.longitude},${destination.latitude}'
    '?geometries=geojson&overview=full',
  );

  try {
    // The public demo server can be slow; the straight-line fallback is
    // already on screen meanwhile, so waiting a little longer costs nothing.
    final response = await http.get(url).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = json['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;

    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List<dynamic>?;
    if (coordinates == null || coordinates.isEmpty) return null;

    final seconds = (route['duration'] as num?)?.toDouble();
    return RoadRoute(
      points: coordinates
          .map((c) => c as List<dynamic>)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList(),
      distanceMeters: (route['distance'] as num?)?.toDouble(),
      duration: seconds == null ? null : Duration(seconds: seconds.round()),
    );
  } catch (e) {
    debugPrint('Road route unavailable, using straight line: $e');
    return null;
  }
}
