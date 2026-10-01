import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

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
  const MapTrackingScreen({super.key, required this.service, this.initialReportId});

  final ResponderService service;

  /// Report to show first (e.g. from an assignment alert); defaults to the
  /// first assigned report.
  final String? initialReportId;

  @override
  State<MapTrackingScreen> createState() => _MapTrackingScreenState();
}

class _MapTrackingScreenState extends State<MapTrackingScreen> {
  late String? _selectedReportId = widget.initialReportId;

  @override
  void didUpdateWidget(covariant MapTrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Already on the Map tab when View was tapped.
    final requested = widget.initialReportId;
    if (requested != null && requested != oldWidget.initialReportId) {
      _selectedReportId = requested;
    }
  }

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
  RoadRoute? _route;
  String? _routedReportId;
  LatLng? _routedFrom;
  int _routeRequestId = 0;

  /// A fix older than this is a last known position, not a live one (the
  /// same threshold the reporter's tracking card uses).
  static const _liveFor = Duration(seconds: 60);

  /// Re-checks the fix's age, so the screen turns stale without a new fix.
  Timer? _ageTimer;

  @override
  void initState() {
    super.initState();
    _ageTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
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
        CameraFit.bounds(bounds: LatLngBounds(responderPoint, reporterPoint), padding: const EdgeInsets.all(48)),
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
    final movedFar =
        _routedFrom != null && const Distance().distance(_routedFrom!, responderPoint) > _rerouteThresholdMeters;
    if (_routedReportId == reportId && !movedFar) return;

    // Clear the stale route immediately (in this same build) so switching to
    // a different report never shows the old report's route mislabeled as
    // current — the fallback straight line takes over until this resolves.
    final requestId = ++_routeRequestId;
    _routedReportId = reportId;
    _routedFrom = responderPoint;
    _route = null;
    fetchRoadRouteDetails(responderPoint, reporterPoint).then((route) {
      // Ignore a response from a request a newer selection/move has superseded.
      if (!mounted || requestId != _routeRequestId) return;
      setState(() => _route = route);
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
            // Null until this phone has a real GPS fix: then only the
            // reporter is drawn, never a made-up responder position.
            final responder = trackingSnapshot.data;
            // Likewise null when the report has no GPS position: no pin,
            // route, distance or ETA is drawn to a made-up spot.
            final reporterLat = selected.reporterLat;
            final reporterLng = selected.reporterLng;
            final reporterPoint = reporterLat != null && reporterLng != null ? LatLng(reporterLat, reporterLng) : null;
            final responderPoint = responder == null ? null : LatLng(responder.lat, responder.lng);
            // Live only while this phone is sharing its location and the fix
            // is fresh; otherwise it's a last known position, and no current
            // distance, route or ETA is worked out from it.
            final recordedAt = responder?.recordedAt;
            final fixAge = recordedAt == null ? null : DateTime.now().difference(recordedAt);
            final responderLive =
                responder != null && widget.service.isSharingLocation && fixAge != null && fixAge <= _liveFor;
            final distanceKm = !responderLive || reporterPoint == null
                ? null
                : _distanceKm(responder.lat, responder.lng, reporterPoint.latitude, reporterPoint.longitude);
            if (distanceKm != null && responderPoint != null && reporterPoint != null) {
              _fitBoundsOnce(responderPoint, reporterPoint, selected.id, distanceKm);
              _maybeFetchRoute(responderPoint, reporterPoint, selected.id);
            }
            final route = distanceKm != null && _routedReportId == selected.id ? _route : null;
            final roadRoute = route?.points;

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
                      const Text('Assigned Incident', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        isExpanded: true,
                        // Always one of the items (a requested report may have left the list).
                        value: reports.isEmpty ? null : selected.id,
                        items: reports
                            .map((r) => DropdownMenuItem(value: r.id, child: Text('${r.id} - ${r.location}')))
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
                          // Camera only; nothing is drawn at the Lipa fallback.
                          initialCenter: reporterPoint ?? responderPoint ?? _lipaMapCenter,
                          initialZoom: 14,
                          onMapEvent: _onMapEvent,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'site.rapidalert.app',
                          ),
                          if (distanceKm != null)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: roadRoute ?? [responderPoint!, reporterPoint!],
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
                              if (responderPoint != null)
                                Marker(
                                  point: responderPoint,
                                  width: 32,
                                  height: 32,
                                  child: Icon(
                                    Icons.local_shipping_rounded,
                                    color: responderLive ? RapidAlertColors.dispatchBlue : RapidAlertColors.lightText,
                                    size: 32,
                                    semanticLabel: responderLive ? 'Your position' : 'Your last known position',
                                  ),
                                ),
                              if (reporterPoint != null)
                                Marker(
                                  point: reporterPoint,
                                  width: 36,
                                  height: 36,
                                  child: const Icon(
                                    Icons.location_on_rounded,
                                    color: RapidAlertColors.emergencyRed,
                                    size: 36,
                                    semanticLabel: 'Reporter location',
                                  ),
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
                      Text(selected.id, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('Reporter: ${selected.reporterName}'),
                      Text('Location: ${selected.location}'),
                      const SizedBox(height: 8),
                      if (reports.isNotEmpty && reporterPoint == null)
                        const Text(
                          'Reporter location unavailable: this report was sent without a GPS position. '
                          'Use the barangay and address above.',
                          style: TextStyle(fontWeight: FontWeight.w600, color: RapidAlertColors.warning),
                        )
                      else if (reports.isEmpty)
                        const Text('No assigned report.', style: TextStyle(color: RapidAlertColors.lightText))
                      else if (responder == null)
                        const Text(
                          'Waiting for your GPS position… Distance and ETA appear once it is found.',
                          style: TextStyle(fontWeight: FontWeight.w600, color: RapidAlertColors.warning),
                        )
                      else if (!responderLive)
                        Text(
                          '${fixAge == null ? 'Last known position' : 'Last known position — ${_formatAge(fixAge)} ago'}. '
                          "Your location isn't being shared now, so distance and ETA aren't shown.",
                          style: const TextStyle(fontWeight: FontWeight.w600, color: RapidAlertColors.warning),
                        )
                      else ...[
                        if (route?.duration != null) ...[
                          Text(
                            'Road route: ${((route!.distanceMeters ?? distanceKm! * 1000) / 1000).toStringAsFixed(1)} km'
                            ' · ETA about ${_formatEta(route.duration!)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Text(
                            'Driving estimate from OSRM, without live traffic.',
                            style: TextStyle(fontSize: 12, color: RapidAlertColors.lightText),
                          ),
                        ] else
                          Text(
                            'Straight-line distance: ${distanceKm!.toStringAsFixed(2)} km (road ETA unavailable)',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Live — sharing your location, updated ${_formatAge(fixAge)} ago.',
                          style: const TextStyle(fontSize: 12, color: RapidAlertColors.success),
                        ),
                      ],
                      // Turn-by-turn navigation to the report's real position.
                      if (reporterPoint != null) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => _openInMaps(reporterPoint),
                          icon: const Icon(Icons.navigation_rounded, size: 18),
                          label: const Text('Open in Google Maps'),
                        ),
                      ],
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
    reporterLat: null,
    reporterLng: null,
  );

  /// Lipa City: where the camera starts when no position is known. Nothing
  /// is ever drawn here.
  static const _lipaMapCenter = LatLng(13.9411, 121.1634);

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180;

  Future<void> _openInMaps(LatLng destination) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${destination.latitude},${destination.longitude}&travelmode=driving',
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open a maps app.")));
    }
  }

  static String _formatAge(Duration age) {
    if (age.inMinutes < 1) return '${age.inSeconds < 0 ? 0 : age.inSeconds}s';
    if (age.inHours < 1) return '${age.inMinutes}m';
    return '${age.inHours}h ${age.inMinutes % 60}m';
  }

  static String _formatEta(Duration d) {
    final minutes = (d.inSeconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }
}
