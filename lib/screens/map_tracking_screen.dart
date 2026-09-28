import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app/theme.dart';
import '../data/osrm_route.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

/// Re-fetch the road route once the responder has moved this far from where
/// the last route was drawn from, so a driving responder's route stays
/// reasonably current without hammering the routing API on every GPS tick.
const _rerouteThresholdMeters = 300;

class MapTrackingScreen extends StatefulWidget {
  const MapTrackingScreen({super.key, required this.service});

  final ResponderService service;

  @override
  State<MapTrackingScreen> createState() => _MapTrackingScreenState();
}

class _MapTrackingScreenState extends State<MapTrackingScreen> {
  String? _selectedReportId;

  final _mapController = MapController();
  String? _lastFitReportId;

  // flutter_map measures its size (and emits that event with the *initial*
  // camera) only after the first frame — even after onMapReady. A fit made
  // before then is overwritten for the tile layer, which then downloads
  // tiles for the stale initial view and leaves the real view grey until the
  // user pans. So the first fit waits for that first size event.
  bool _mapSized = false;
  VoidCallback? _pendingFit;

  // Real road-following route between responder and reporter, fetched from
  // the same OSRM routing backend the website uses — falls back to a
  // straight line (matching the website's own fallback) while loading or if
  // the routing request fails.
  List<LatLng>? _routePoints;
  String? _routedReportId;
  LatLng? _routedFrom;
  int _routeRequestId = 0;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Frames both markers the first time a given report is shown, then
  /// leaves the camera alone so the responder's live position updates
  /// don't keep yanking the map back to center on every poll tick.
  void _fitBoundsOnce(LatLng responderPoint, LatLng reporterPoint, String reportId, double distanceKm) {
    if (_lastFitReportId == reportId) return;
    _lastFitReportId = reportId;
    void fit() {
      if (!mounted) return;
      if (distanceKm < 0.05) {
        _mapController.move(reporterPoint, 15);
        return;
      }
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(responderPoint, reporterPoint),
          padding: const EdgeInsets.all(48),
        ),
      );
    }

    if (_mapSized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fit());
    } else {
      _pendingFit = fit;
    }
  }

  void _onMapEvent(MapEvent event) {
    if (_mapSized || event is! MapEventNonRotatedSizeChange) return;
    _mapSized = true;
    final fit = _pendingFit;
    _pendingFit = null;
    if (fit != null) WidgetsBinding.instance.addPostFrameCallback((_) => fit());
  }

  void _maybeFetchRoute(LatLng responderPoint, LatLng reporterPoint, String reportId) {
    final movedFar = _routedFrom != null &&
        const Distance().distance(_routedFrom!, responderPoint) > _rerouteThresholdMeters;
    if (_routedReportId == reportId && !movedFar) return;

    // Clear the stale route immediately (in this same build) so switching to
    // a different report never shows the old report's route mislabeled as
    // current — the fallback straight line takes over until this resolves.
    final requestId = ++_routeRequestId;
    _routedReportId = reportId;
    _routedFrom = responderPoint;
    _routePoints = null;
    fetchRoadRoute(responderPoint, reporterPoint).then((points) {
      // Ignore a response from a request a newer selection/move has superseded.
      if (!mounted || requestId != _routeRequestId) return;
      setState(() => _routePoints = points);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<IncidentReport>>(
      stream: widget.service.reportsStream,
      initialData: widget.service.reports,
      builder: (context, snapshot) {
        final reports = snapshot.data ?? const <IncidentReport>[];
        final selected = reports.firstWhere(
          (r) => r.id == _selectedReportId,
          orElse: () => reports.isNotEmpty ? reports.first : _emptyReport,
        );

        return StreamBuilder<GeoPoint>(
          stream: widget.service.responderTrackingStream,
          initialData: widget.service.currentResponderPoint,
          builder: (context, trackingSnapshot) {
            final responder =
                trackingSnapshot.data ??
                const GeoPoint(lat: 13.9412, lng: 121.1631);
            final distanceKm = _distanceKm(
              responder.lat,
              responder.lng,
              selected.reporterLat,
              selected.reporterLng,
            );
            final responderPoint = LatLng(responder.lat, responder.lng);
            final reporterPoint = LatLng(selected.reporterLat, selected.reporterLng);
            _fitBoundsOnce(responderPoint, reporterPoint, selected.id, distanceKm);
            _maybeFetchRoute(responderPoint, reporterPoint, selected.id);
            final roadRoute = _routedReportId == selected.id ? _routePoints : null;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                const ScreenHeader(
                  title: 'Map Responder to Reporter',
                  subtitle: 'Live responder tracking and route estimation to reporter location.',
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assigned Incident',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        isExpanded: true,
                        value:
                            _selectedReportId ??
                            (reports.isNotEmpty ? reports.first.id : null),
                        items: reports
                            .map(
                              (r) => DropdownMenuItem(
                                value: r.id,
                                child: Text('${r.id} - ${r.location}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedReportId = value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 260,
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: reporterPoint,
                          initialZoom: 14,
                          onMapEvent: _onMapEvent,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'site.rapidalert.app',
                          ),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: roadRoute ?? [responderPoint, reporterPoint],
                                color: RapidAlertColors.dispatchBlue,
                                strokeWidth: roadRoute != null ? 4 : 3,
                                pattern: roadRoute != null
                                    ? const StrokePattern.solid()
                                    : StrokePattern.dashed(segments: const [8, 4]),
                              ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: responderPoint,
                                width: 32,
                                height: 32,
                                child: const Icon(Icons.local_shipping_rounded, color: RapidAlertColors.dispatchBlue, size: 32),
                              ),
                              Marker(
                                point: reporterPoint,
                                width: 36,
                                height: 36,
                                child: const Icon(Icons.location_on_rounded, color: RapidAlertColors.emergencyRed, size: 36),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.id,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Reporter: ${selected.reporterName}'),
                      Text('Location: ${selected.location}'),
                      const SizedBox(height: 8),
                      Text(
                        'Responder -> Reporter Distance: ${distanceKm.toStringAsFixed(2)} km',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static final _emptyReport = IncidentReport(
    id: 'N/A',
    hazard: 'N/A',
    location: 'No report',
    reporterName: 'N/A',
    status: ReportStatus.assigned,
    needHelp: false,
    updated: DateTime.fromMillisecondsSinceEpoch(0),
    reporterLat: 13.9412,
    reporterLng: 121.1631,
  );

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180;
}
