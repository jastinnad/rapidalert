import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../app/theme.dart';
import '../data/backend_features.dart';
import '../data/offline_cache.dart';
import '../data/osrm_route.dart';
import '../data/report_submission_ids.dart';
import '../data/reporter_service.dart';
import '../models/reporter_models.dart';
import 'report_chat_screen.dart';
import 'report_history_screen.dart';
import 'report_notifications_screen.dart';
import 'ui_components.dart';

/// Statuses the screen keeps refreshing, so assignment and en route show up
/// by themselves ('received' is the Need Help auto-report's first stage).
/// Stops at resolved. The responder position itself only ever arrives
/// (from the backend) while en_route/on_scene.
const _pollingStatuses = {'reported', 'received', 'assigned', 'en_route', 'on_scene'};

class ReportTrackingScreen extends StatefulWidget {
  const ReportTrackingScreen({super.key, required this.service, this.submissionIds});

  final ReporterService service;

  /// Where this install's report IDs are kept; defaults to secure storage.
  final ReportSubmissionIds? submissionIds;

  @override
  State<ReportTrackingScreen> createState() => _ReportTrackingScreenState();
}

class _ReportTrackingScreenState extends State<ReportTrackingScreen> {
  final _trackingIdController = TextEditingController();
  TrackedReport? _report;
  bool _loading = false;
  bool _searched = false;
  String? _error;
  Timer? _pollTimer;

  /// Set while [_report] is a saved copy (the server couldn't be reached):
  /// when that copy was fetched. Null while the data is live.
  DateTime? _offlineSavedAt;
  DateTime? _lastLiveAt;
  late final _submissionIds = widget.submissionIds ?? ReportSubmissionIds();

  @override
  void initState() {
    super.initState();
    // Show the reporter's latest report by default, if any.
    _search();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _trackingIdController.dispose();
    super.dispose();
  }

  /// [background] refreshes (the live-tracking poll) update the card in
  /// place instead of swapping it for a spinner, so it doesn't blink every
  /// few seconds; a failed background refresh keeps the last good data.
  Future<void> _search({bool background = false}) async {
    if (!background) {
      setState(() {
        _loading = true;
        _error = null;
        _searched = true;
      });
    }
    try {
      final trackingId = _trackingIdController.text.trim().isEmpty ? null : _trackingIdController.text.trim();
      // Guests are found by a report's own client_report_id: this install's
      // latest report for a blank search, or, for a tracking ID this install
      // submitted, that report's ID. Any other tracking ID is sent alone
      // (the backend requires both to match when both are sent, so sending
      // an unrelated ID would hide a report from another device).
      // Signed-in reporters are matched by their account instead.
      final isGuest = widget.service.currentUserId == null;
      final clientReportId = !isGuest
          ? null
          : trackingId == null
          ? await _submissionIds.latestSubmittedId()
          : await _submissionIds.clientReportIdFor(trackingId);
      // Without an ID the backend falls back to matching guests by IP, which
      // on mobile networks can be another phone's report.
      final report = trackingId == null && clientReportId == null && isGuest
          ? null
          : await widget.service.trackReport(trackingId: trackingId, clientReportId: clientReportId);
      if (!mounted) return;
      setState(() {
        _report = report;
        _offlineSavedAt = null;
        _lastLiveAt = DateTime.now();
      });
      _syncPollTimer(report);
    } catch (e) {
      if (!mounted) return;
      final offline = isNetworkError(e);
      if (background) {
        // Keep the card, but stop presenting it as live.
        if (offline && _report != null) setState(() => _offlineSavedAt ??= _lastLiveAt ?? DateTime.now());
        return;
      }
      final trackingId = _trackingIdController.text.trim();
      CachedCopy<TrackedReport>? cached;
      if (offline) {
        try {
          cached = await widget.service.cachedTrackedReport(trackingId: trackingId.isEmpty ? null : trackingId);
        } catch (_) {
          cached = null;
        }
      }
      if (!mounted) return;
      _pollTimer?.cancel();
      _pollTimer = null;
      setState(() {
        if (cached != null) {
          _report = cached.value;
          _offlineSavedAt = cached.savedAt;
        } else {
          _report = null;
          _error = offline
              ? "You're offline and there's no saved copy of this report yet. Connect to the internet and try again."
              : "Couldn't load your report right now. Please try again.";
        }
      });
    } finally {
      if (mounted && !background) setState(() => _loading = false);
    }
  }

  /// Keeps re-fetching every ~7s until the report is resolved, so status
  /// changes and the responder's position and ETA stay current;
  /// stops the moment the status leaves that window (e.g. once resolved).
  void _syncPollTimer(TrackedReport? report) {
    final shouldPoll = report != null && _pollingStatuses.contains(report.status);
    if (shouldPoll && _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 7), (_) => _search(background: true));
    } else if (!shouldPoll && _pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A tab inside ReporterHomeShell, which paints the photo background.
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Track Your Report')),
      body: RefreshIndicator(
        onRefresh: _search,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _trackingIdController,
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'Enter tracking ID (or leave blank for latest)',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: RapidAlertColors.border),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: RapidAlertColors.border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _loading ? null : _search,
                  tooltip: 'Search report',
                  icon: const Icon(Icons.search_rounded),
                  style: IconButton.styleFrom(backgroundColor: RapidAlertColors.primaryRed),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (!_loading && _error != null) ErrorRetry(message: _error!, onRetry: _search),
            if (!_loading && _error == null && _searched && _report == null)
              const Center(
                child: Padding(padding: EdgeInsets.only(top: 40), child: Text('No report found.')),
              ),
            if (!_loading && _report != null && _offlineSavedAt != null) ...[
              OfflineBanner(
                savedAt: _offlineSavedAt!,
                onRetry: _search,
                detail: 'Status and responder position may have changed.',
              ),
              const SizedBox(height: 12),
            ],
            if (!_loading && _report != null)
              _ReportCard(
                report: _report!,
                service: widget.service,
                offline: _offlineSavedAt != null,
                // Guests reach a report's history with this phone's client_report_id.
                clientReportIdLookup: widget.service.currentUserId == null
                    ? () => _submissionIds.clientReportIdFor(_report!.trackingId)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.service, required this.offline, this.clientReportIdLookup});

  final TrackedReport report;
  final ReporterService service;
  final bool offline;
  final Future<String?> Function()? clientReportIdLookup;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, y • h:mm a');

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(report.trackingId, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              _StatusChip(status: report.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(report.hazard, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${report.barangay}, ${report.city}', style: const TextStyle(color: RapidAlertColors.lightText)),
          const SizedBox(height: 10),
          if (report.assignedResponderName != null) ...[
            Row(
              children: [
                const Icon(Icons.badge_outlined, size: 16, color: RapidAlertColors.lightText),
                const SizedBox(width: 6),
                Expanded(child: Text('Responder: ${report.assignedResponderName}')),
                if (report.assignedResponderUserId != null && service.currentUserId != null)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportChatScreen(
                          service: service,
                          reportId: report.id,
                          receiverId: report.assignedResponderUserId!,
                          receiverName: report.assignedResponderName!,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                    label: const Text('Message'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          if (report.responderLat != null && report.responderLng != null) ...[
            _ResponderTrackingCard(report: report, offline: offline),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 16, color: RapidAlertColors.lightText),
              const SizedBox(width: 6),
              Text('Last update: ${dateFormat.format(report.updatedAt.toLocal())}'),
            ],
          ),
          if (report.adminComment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: RapidAlertColors.background, borderRadius: BorderRadius.circular(8)),
              child: Text(report.adminComment),
            ),
          ],
          const SizedBox(height: 8),
          if (service.currentUserId != null || BackendFeatures.reporterTrackingDetails)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // The updates list needs an account (the backend keys it by user).
                if (service.currentUserId != null)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportNotificationsScreen(
                          service: service,
                          reportId: report.id,
                          trackingId: report.trackingId,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.notifications_none_rounded, size: 18),
                    label: const Text('View updates'),
                  ),
                // Needs the history endpoint, which production doesn't have yet.
                if (BackendFeatures.reporterTrackingDetails)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportHistoryScreen(
                          service: service,
                          trackingId: report.trackingId,
                          clientReportIdLookup: clientReportIdLookup,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Status history'),
                  ),
              ],
            ),
          if (service.currentUserId == null) ...[
            if (BackendFeatures.reporterTrackingDetails) const SizedBox(height: 6),
            const Text(
              'Sign in to see the list of updates sent about your report.',
              style: TextStyle(fontSize: 12, color: RapidAlertColors.lightText),
            ),
          ],
        ],
      ),
    );
  }
}

/// The responder's position on the reporter's map. While it's live and the
/// incident has real coordinates, also the incident pin and the OSRM road
/// route with its ETA; a stale or saved position gets neither.
class _ResponderTrackingCard extends StatefulWidget {
  const _ResponderTrackingCard({required this.report, required this.offline});

  final TrackedReport report;
  final bool offline;

  @override
  State<_ResponderTrackingCard> createState() => _ResponderTrackingCardState();
}

class _ResponderTrackingCardState extends State<_ResponderTrackingCard> {
  static const _staleAfter = Duration(seconds: 60);

  /// Re-fetch the road route once the responder has moved this far.
  static const _rerouteAfterMeters = 100;

  RoadRoute? _route;
  LatLng? _routedFrom;
  LatLng? _routedTo;
  int _routeRequest = 0;

  void _maybeFetchRoute(LatLng from, LatLng to) {
    final moved = _routedFrom == null || const Distance().distance(_routedFrom!, from) > _rerouteAfterMeters;
    if (!moved && _routedTo == to) return;
    final request = ++_routeRequest;
    _routedFrom = from;
    _routedTo = to;
    fetchRoadRouteDetails(from, to).then((route) {
      if (!mounted || request != _routeRequest) return;
      setState(() => _route = route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final point = LatLng(report.responderLat!, report.responderLng!);
    final updatedAt = report.responderLocationUpdatedAt;
    final age = updatedAt != null ? DateTime.now().difference(updatedAt) : null;
    // A saved copy is never live, however recent its timestamp.
    final isStale = widget.offline || age == null || age > _staleAfter;
    // Only used when the backend sends it (BackendFeatures); never a default.
    final incident = BackendFeatures.reporterTrackingDetails && report.latitude != null && report.longitude != null
        ? LatLng(report.latitude!, report.longitude!)
        : null;

    // A route from an old position isn't current, so only while live.
    final showRoute = !isStale && incident != null;
    if (showRoute) _maybeFetchRoute(point, incident);
    final route = showRoute && _routedTo == incident ? _route : null;
    final roadEta = route?.duration;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: [
            isStale ? "Map of the responder's last known position" : "Map of the responder's position",
            if (incident != null) 'and your reported location',
          ].join(' '),
          image: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 180,
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 14,
                    initialCameraFit: incident == null
                        ? null
                        : CameraFit.bounds(
                            bounds: LatLngBounds(point, incident),
                            padding: const EdgeInsets.all(36),
                            maxZoom: 16,
                          ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'site.rapidalert.app',
                    ),
                    if (showRoute)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: route?.points ?? [point, incident],
                            color: RapidAlertColors.enRoute,
                            strokeWidth: route != null ? 4 : 3,
                            pattern: route != null
                                ? const StrokePattern.solid()
                                : StrokePattern.dashed(segments: const [8, 4]),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (incident != null)
                          Marker(
                            point: incident,
                            width: 34,
                            height: 34,
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: RapidAlertColors.emergencyRed,
                              size: 34,
                              semanticLabel: 'Your reported location',
                            ),
                          ),
                        Marker(
                          point: point,
                          width: 32,
                          height: 32,
                          child: Icon(
                            Icons.local_shipping_rounded,
                            color: isStale ? RapidAlertColors.lightText : RapidAlertColors.enRoute,
                            size: 32,
                            semanticLabel: isStale ? 'Responder last known position' : 'Responder position',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // An ETA worked out from an old position isn't current, so it's
            // only shown while the position is live.
            if (!isStale && (roadEta != null || report.etaMinutes != null)) ...[
              const Icon(Icons.timer_outlined, size: 16, color: RapidAlertColors.lightText),
              const SizedBox(width: 6),
              Text(
                roadEta != null
                    ? 'ETA about ${(roadEta.inSeconds / 60).ceil()} min by road'
                    : 'ETA ~${report.etaMinutes} min',
              ),
              const SizedBox(width: 14),
            ],
            Icon(
              isStale ? Icons.warning_amber_rounded : Icons.sensors_rounded,
              size: 16,
              color: isStale ? RapidAlertColors.warning : RapidAlertColors.success,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                age == null
                    ? 'Position unavailable'
                    : isStale
                    ? 'Last known position — ${_formatAge(age)} ago'
                    : 'Live — updated ${_formatAge(age)} ago',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isStale ? RapidAlertColors.warning : RapidAlertColors.lightText,
                ),
              ),
            ),
          ],
        ),
        if (isStale && (report.etaMinutes != null || incident != null)) ...[
          const SizedBox(height: 4),
          const Text(
            "ETA unavailable until the responder's position updates.",
            style: TextStyle(fontSize: 12, color: RapidAlertColors.lightText),
          ),
        ],
        if (!isStale && route != null) ...[
          const SizedBox(height: 2),
          Text(
            '${((route.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} km by road · driving estimate without live traffic',
            style: const TextStyle(fontSize: 12, color: RapidAlertColors.lightText),
          ),
        ],
      ],
    );
  }

  String _formatAge(Duration age) {
    if (age.inMinutes < 1) return '${age.inSeconds}s';
    return '${age.inMinutes}m';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'resolved' || 'completed' => RapidAlertColors.success,
      'received' || 'reported' => RapidAlertColors.warning,
      'en_route' => RapidAlertColors.enRoute,
      'on_scene' => RapidAlertColors.onSceneAccent,
      _ => RapidAlertColors.operationsBlue,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
