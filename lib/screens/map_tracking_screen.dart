import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../data/osrm_route.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'assigned_reports_screen.dart' show reportStatusColor, reportStatusLabel;
import 'ui_components.dart';

/// Re-fetch the road route once the responder has moved this far from where
/// the last route was drawn from, so a driving responder's route stays
/// reasonably current without hammering the routing API on every GPS tick.
const _rerouteThresholdMeters = 300;

class MapTrackingScreen extends StatefulWidget {
  const MapTrackingScreen({super.key, required this.service, this.initialReportId, this.onOpenChat});

  final ResponderService service;

  /// Report to show first (e.g. from an assignment alert or Start — En
  /// Route); defaults to the first assigned report.
  final String? initialReportId;

  /// Opens the Chat tab on a report; no Message button without it.
  final ValueChanged<String>? onOpenChat;

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

  /// What the camera was last framed on (report + which points), so it is
  /// framed once per report and again only when the responder's live
  /// position first appears — not on every GPS tick.
  String? _framedFor;

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

  /// The report whose status is being changed from this screen.
  String? _updatingReportId;

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

  /// Moves the camera to the real points known for a report: both when the
  /// responder is live, else the report's location, else the responder's
  /// own (possibly last known) fix. Nothing known: the camera stays put.
  void _frame(List<LatLng> points) {
    void fit() {
      if (!mounted || points.isEmpty) return;
      final spread = points.length < 2 ? 0.0 : const Distance().distance(points.first, points.last);
      if (spread < 50) {
        _mapController.move(points.first, 16);
        return;
      }
      _mapController.fitCamera(
        CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(48)),
      );
    }

    if (_mapSized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fit());
    } else {
      _pendingFit = fit;
    }
  }

  void _frameOnce(String key, List<LatLng> points) {
    if (_framedFor == key || points.isEmpty) return;
    _framedFor = key;
    _frame(points);
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

  Future<void> _advanceStatus(IncidentReport report, ReportStatus next) async {
    setState(() => _updatingReportId = report.id);
    try {
      await widget.service.updateReportStatus(report.id, next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update status. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _updatingReportId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // About half the screen, never too small to use or so tall that the
        // details below disappear.
        final mapHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * 0.5).clamp(240.0, 480.0)
            : 320.0;
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
              builder: (context, trackingSnapshot) =>
                  _buildBody(context, reports, selected, trackingSnapshot.data, mapHeight),
            );
          },
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<IncidentReport> reports,
    IncidentReport selected,
    GeoPoint? responder,
    double mapHeight,
  ) {
    // `responder` is null until this phone has a real GPS fix: then only the
    // report is drawn, never a made-up responder position. Likewise the
    // report's point is null when it was sent without GPS: no pin, route,
    // distance or ETA is drawn to a made-up spot.
    final reporterLat = selected.reporterLat;
    final reporterLng = selected.reporterLng;
    final reporterPoint = reporterLat != null && reporterLng != null ? LatLng(reporterLat, reporterLng) : null;
    final responderPoint = responder == null ? null : LatLng(responder.lat, responder.lng);
    // Live only while this phone is sharing its location and the fix is
    // fresh; otherwise it's a last known position, and no current distance,
    // route or ETA is worked out from it.
    final recordedAt = responder?.recordedAt;
    final fixAge = recordedAt == null ? null : DateTime.now().difference(recordedAt);
    final responderLive =
        responder != null && widget.service.isSharingLocation && fixAge != null && fixAge <= _liveFor;
    final distanceKm = !responderLive || reporterPoint == null
        ? null
        : _distanceKm(responder.lat, responder.lng, reporterPoint.latitude, reporterPoint.longitude);

    if (reports.isNotEmpty) {
      final both = responderLive && reporterPoint != null;
      _frameOnce('${selected.id}|${both ? 'both' : reporterPoint != null ? 'report' : 'you'}', [
        ?reporterPoint,
        if (both || reporterPoint == null) ?responderPoint,
      ]);
    }
    if (distanceKm != null) {
      _maybeFetchRoute(responderPoint!, reporterPoint!, selected.id);
    }
    final route = distanceKm != null && _routedReportId == selected.id ? _route : null;
    final roadRoute = route?.points;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ScreenHeader(
            title: 'Map Responder to Reporter',
            subtitle: 'The report location, your own position, and the report details.',
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
                      .map(
                        (r) => DropdownMenuItem(
                          value: r.id,
                          child: Text('${r.displayId} - ${r.location}', overflow: TextOverflow.ellipsis),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: SizedBox(
                    key: const Key('responder-map'),
                    height: mapHeight,
                    child: Stack(
                      children: [
                        FlutterMap(
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
                        if (reporterPoint != null || responderPoint != null)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Material(
                              color: Colors.white,
                              shape: const CircleBorder(side: BorderSide(color: RapidAlertColors.border)),
                              child: IconButton(
                                key: const Key('responder-map-fit'),
                                tooltip: 'Show the report and your position',
                                icon: const Icon(Icons.zoom_out_map_rounded, size: 20),
                                onPressed: () => _frame([?reporterPoint, ?responderPoint]),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Legend(
                        key: const Key('responder-map-legend'),
                        reportShown: reporterPoint != null,
                        you: responderPoint == null
                            ? null
                            : responderLive
                            ? 'You (live GPS)'
                            : 'You (last known)',
                        youLive: responderLive,
                      ),
                      const SizedBox(height: 10),
                      KeyedSubtree(
                        key: const Key('responder-location-state'),
                        child: _locationState(reports, selected, reporterPoint, responder, responderLive, fixAge,
                            distanceKm, route),
                      ),
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
            ),
          ),
          const SizedBox(height: 12),
          if (reports.isNotEmpty) _details(selected),
        ],
      ),
    );
  }

  Widget _locationState(
    List<IncidentReport> reports,
    IncidentReport selected,
    LatLng? reporterPoint,
    GeoPoint? responder,
    bool responderLive,
    Duration? fixAge,
    double? distanceKm,
    RoadRoute? route,
  ) {
    const warn = TextStyle(fontWeight: FontWeight.w600, color: RapidAlertColors.warning);
    if (reports.isEmpty) {
      return const Text('No assigned report.', style: TextStyle(color: RapidAlertColors.lightText));
    }
    final responding = selected.status == ReportStatus.enRoute || selected.status == ReportStatus.onScene;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reporterPoint == null) ...[
          const Text(
            'Reporter location unavailable: this report was sent without a GPS position. '
            'Use the address in the details below.',
            style: warn,
          ),
          const SizedBox(height: 6),
        ],
        if (responder == null && !responding && !widget.service.isSharingLocation)
          // GPS is only used while responding; nothing is waited for yet.
          const Text(
            'Your position is shared and shown here once you tap Start — En Route.',
            style: TextStyle(color: RapidAlertColors.lightText),
          )
        else if (responder == null)
          const Text(
            'Waiting for your GPS position… Distance and ETA appear once it is found. '
            "If this doesn't change, check that location is on and allowed for Rapid Alert.",
            style: warn,
          )
        else if (!responderLive)
          Text(
            '${fixAge == null ? 'Last known position' : 'Last known position — ${_formatAge(fixAge)} ago'}. '
            "Your location isn't being shared now, so distance and ETA aren't shown.",
            style: warn,
          )
        else ...[
          if (distanceKm != null) ...[
            if (route?.duration != null) ...[
              Text(
                'Road route: ${((route!.distanceMeters ?? distanceKm * 1000) / 1000).toStringAsFixed(1)} km'
                ' · ETA about ${_formatEta(route.duration!)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Text(
                'Driving estimate from OSRM, without live traffic.',
                style: TextStyle(fontSize: 12, color: RapidAlertColors.lightText),
              ),
            ] else
              Text(
                'Straight-line distance: ${distanceKm.toStringAsFixed(2)} km (road ETA unavailable)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 4),
          ],
          Text(
            'Live — sharing your location, updated ${_formatAge(fixAge!)} ago.',
            style: const TextStyle(fontSize: 12, color: RapidAlertColors.success),
          ),
        ],
      ],
    );
  }

  Widget _details(IncidentReport report) {
    final next = responderNextStep(report.status);
    final updating = _updatingReportId == report.id;
    final address = [
      if (report.houseNo.isNotEmpty && report.houseNo != '-') report.houseNo,
      if (report.purok.isNotEmpty && report.purok != '-') report.purok,
      if (report.location.isNotEmpty) report.location,
      if (report.city.isNotEmpty && report.city != report.location) report.city,
    ].join(', ');
    final care = [
      if (report.elderlyCount > 0) 'Elderly ${report.elderlyCount}',
      if (report.pwdCount > 0) 'PWD ${report.pwdCount}',
      if (report.childCount > 0) 'Children ${report.childCount}',
      if (report.pregnantCount > 0) 'Pregnant ${report.pregnantCount}',
    ].join(' · ');
    final presence = report.isGuestReport
        ? 'Guest report (no account)'
        : report.reporterOnline == true
        ? 'Online'
        : report.reporterOnline == false
        ? 'Not online right now'
        : null;
    final dateFormat = DateFormat('MMM d, h:mm a');

    return GlassCard(
      key: const Key('responder-report-details'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.trackingId.isNotEmpty ? 'Tracking ID' : 'Report',
                      style: const TextStyle(fontSize: 12, color: RapidAlertColors.lightText),
                    ),
                    SelectableText(
                      report.displayId,
                      key: const Key('responder-tracking-id'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: report.status, needHelp: report.needHelp),
            ],
          ),
          if (next != null || (widget.onOpenChat != null && !report.isGuestReport)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (next != null)
                  FilledButton(
                    key: const Key('map-next-step'),
                    onPressed: updating ? null : () => _advanceStatus(report, next.$2),
                    child: updating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(next.$1),
                  ),
                if (widget.onOpenChat != null && !report.isGuestReport)
                  OutlinedButton.icon(
                    key: const Key('map-message-reporter'),
                    onPressed: () => widget.onOpenChat!(report.id),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('Message reporter'),
                  ),
              ],
            ),
          ],
          const Divider(height: 24),
          _DetailRow(
            label: 'Hazard',
            value: [
              report.hazard,
              if (report.particular.isNotEmpty) report.particular,
            ].join(' — '),
          ),
          if (report.particularDetail.isNotEmpty) _DetailRow(label: 'Severity', value: report.particularDetail),
          _DetailRow(label: 'Address', value: address.isEmpty ? 'Not given' : address),
          if (report.landmark.isNotEmpty && report.landmark != '-')
            _DetailRow(label: 'Landmark', value: report.landmark),
          _DetailRow(
            label: 'Reporter',
            value: presence == null ? report.reporterName : '${report.reporterName} · $presence',
          ),
          if (report.phone.isNotEmpty) _DetailRow(label: 'Contact', value: report.phone),
          if (report.alternateContact.isNotEmpty)
            _DetailRow(label: 'Alternate contact', value: report.alternateContact),
          if (report.currentSituation.isNotEmpty)
            _DetailRow(label: 'Situation', value: report.currentSituation.join('\n')),
          if (report.needs.isNotEmpty)
            _DetailRow(label: 'Needs', value: report.needs.map((n) => n.replaceAll('_', ' ')).join(', ')),
          if (care.isNotEmpty) _DetailRow(label: 'Needs extra care', value: care),
          if (report.reportedAt != null) _DetailRow(label: 'Reported', value: dateFormat.format(report.reportedAt!)),
          _DetailRow(label: 'Updated', value: dateFormat.format(report.updated)),
          if (report.imageUrl.isNotEmpty)
            TextButton.icon(
              onPressed: () => _openUrl(Uri.parse(report.imageUrl), "Couldn't open the photo."),
              icon: const Icon(Icons.photo_rounded, size: 18),
              label: const Text('View photo'),
            ),
        ],
      ),
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

  Future<void> _openInMaps(LatLng destination) => _openUrl(
    Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${destination.latitude},${destination.longitude}&travelmode=driving',
    ),
    "Couldn't open a maps app.",
  );

  Future<void> _openUrl(Uri uri, String failure) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
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

/// Which marker is which: the report's location vs. this responder's own.
class _Legend extends StatelessWidget {
  const _Legend({super.key, required this.reportShown, required this.you, required this.youLive});

  final bool reportShown;

  /// Null when this phone has no fix: nothing of the responder is drawn.
  final String? you;
  final bool youLive;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, color: RapidAlertColors.labelText);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A crossed-out pin when there is none: no red pin is drawn anywhere.
            Icon(
              reportShown ? Icons.location_on_rounded : Icons.location_off_rounded,
              size: 18,
              color: reportShown ? RapidAlertColors.emergencyRed : RapidAlertColors.lightText,
            ),
            const SizedBox(width: 4),
            Flexible(child: Text(reportShown ? 'Report location' : 'Report location — not sent', style: style)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              you == null ? Icons.gps_off_rounded : Icons.local_shipping_rounded,
              size: 18,
              color: youLive ? RapidAlertColors.dispatchBlue : RapidAlertColors.lightText,
            ),
            const SizedBox(width: 4),
            Flexible(child: Text(you ?? 'You — no GPS position yet', style: style)),
          ],
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontSize: 13, color: RapidAlertColors.lightText)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.needHelp});

  final ReportStatus status;
  final bool needHelp;

  @override
  Widget build(BuildContext context) {
    final color = needHelp ? RapidAlertColors.warning : reportStatusColor(status);
    return Container(
      key: const Key('responder-report-status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
      child: Text(
        needHelp ? 'Need Help' : reportStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
