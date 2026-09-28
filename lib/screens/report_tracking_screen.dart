import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../app/theme.dart';
import '../data/device_id_service.dart';
import '../data/reporter_service.dart';
import '../models/reporter_models.dart';
import 'report_chat_screen.dart';
import 'ui_components.dart';

const _liveTrackingStatuses = {'en_route', 'on_scene'};

class ReportTrackingScreen extends StatefulWidget {
  const ReportTrackingScreen({super.key, required this.service});

  final ReporterService service;

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
      // Only scope by this device's own guest ID for the "my latest report"
      // case (blank field). An explicit tracking ID is meant to be looked
      // up by anyone who has it, not just the device that submitted it —
      // sending both made the backend require both to match, so an
      // explicit tracking-ID search from a different device always failed.
      final deviceId = trackingId == null ? await DeviceIdService.getOrCreate() : null;
      final report = await widget.service.trackReport(
        trackingId: trackingId,
        clientReportId: deviceId,
      );
      if (!mounted) return;
      setState(() => _report = report);
      _syncPollTimer(report);
    } catch (e) {
      if (!mounted || background) return;
      setState(() => _error = 'Failed to load report. Try again.');
    } finally {
      if (mounted && !background) setState(() => _loading = false);
    }
  }

  /// Keeps re-fetching every ~7s while help is actively en route/on scene,
  /// so the responder's position and ETA stay current; stops the moment the
  /// status leaves that window (including mid-poll, e.g. once resolved).
  void _syncPollTimer(TrackedReport? report) {
    final shouldPoll = report != null && _liveTrackingStatuses.contains(report.status);
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
                  icon: const Icon(Icons.search_rounded),
                  style: IconButton.styleFrom(backgroundColor: RapidAlertColors.primaryRed),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (!_loading && _error != null) Center(child: Text(_error!)),
            if (!_loading && _error == null && _searched && _report == null)
              const Center(child: Padding(padding: EdgeInsets.only(top: 40), child: Text('No report found.'))),
            if (!_loading && _report != null) _ReportCard(report: _report!, service: widget.service),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.service});

  final TrackedReport report;
  final ReporterService service;

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
                child: Text(
                  report.trackingId,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              _StatusChip(status: report.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(report.hazard, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            '${report.barangay}, ${report.city}',
            style: const TextStyle(color: RapidAlertColors.lightText),
          ),
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
            _ResponderTrackingCard(report: report),
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
              decoration: BoxDecoration(
                color: RapidAlertColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(report.adminComment),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResponderTrackingCard extends StatelessWidget {
  const _ResponderTrackingCard({required this.report});

  final TrackedReport report;

  static const _staleAfter = Duration(seconds: 60);

  @override
  Widget build(BuildContext context) {
    final point = LatLng(report.responderLat!, report.responderLng!);
    final updatedAt = report.responderLocationUpdatedAt;
    final age = updatedAt != null ? DateTime.now().difference(updatedAt) : null;
    final isStale = age == null || age > _staleAfter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 180,
            child: IgnorePointer(
              child: FlutterMap(
                options: MapOptions(initialCenter: point, initialZoom: 14),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'site.rapidalert.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 32,
                        height: 32,
                        child: const Icon(Icons.local_shipping_rounded, color: RapidAlertColors.enRoute, size: 32),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (report.etaMinutes != null) ...[
              const Icon(Icons.timer_outlined, size: 16, color: RapidAlertColors.lightText),
              const SizedBox(width: 6),
              Text('ETA ~${report.etaMinutes} min'),
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
