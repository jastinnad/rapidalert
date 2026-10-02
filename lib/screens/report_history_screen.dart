import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/offline_cache.dart';
import '../data/reporter_service.dart';
import '../models/reporter_models.dart';
import 'ui_components.dart';

/// A report's lifecycle as recorded by the backend's status machine
/// (`GET /api/reporter/reports/history`). Only recorded steps are shown;
/// nothing is inferred on the phone.
class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key, required this.service, required this.trackingId, this.clientReportIdLookup});

  final ReporterService service;
  final String trackingId;

  /// For guests: this phone's client_report_id for the report, which the
  /// backend requires instead of an account.
  final Future<String?> Function()? clientReportIdLookup;

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  StatusHistory? _history;
  bool _notFound = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clientReportId = await widget.clientReportIdLookup?.call();
      final history = await widget.service.loadStatusHistory(
        trackingId: widget.trackingId,
        clientReportId: clientReportId,
      );
      if (!mounted) return;
      setState(() {
        _history = history;
        _notFound = history == null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = isNetworkError(e)
            ? "You're offline. Connect to the internet to see the status history."
            : "Couldn't load the status history. Please try again.",
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;

    return Scaffold(
      backgroundColor: RapidAlertColors.background,
      appBar: AppBar(title: Text('Status history · ${widget.trackingId}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading && history == null)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              ErrorRetry(message: _error!, onRetry: _load)
            else if (_notFound)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                  "Status history isn't available for this report. It's shown for reports on your "
                  'account, or reports sent from this phone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: RapidAlertColors.lightText),
                ),
              )
            else if (history != null) ...[
              if (history.submittedAt != null)
                _HistoryRow(title: 'Report submitted', subtitle: null, at: history.submittedAt, first: true),
              for (final entry in history.transitions)
                _HistoryRow(title: _title(entry.toStatus), subtitle: _actor(entry), at: entry.at, first: false),
              if (history.transitions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'No status changes yet. Each change will appear here.',
                    style: TextStyle(color: RapidAlertColors.lightText),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _title(String status) => switch (status) {
    'reported' => 'Waiting for a responder',
    'received' => 'Received',
    'validating' => 'Being validated',
    'incomplete' => 'Marked incomplete',
    'assigned' => 'Responder assigned',
    'en_route' => 'Responder on the way',
    'on_scene' => 'Responder arrived',
    'resolved' => 'Resolved',
    'completed' => 'Completed and closed',
    _ => status.replaceAll('_', ' '),
  };

  static String? _actor(StatusHistoryEntry entry) => switch (entry.actorRole) {
    'dispatcher' => 'by a CDRRMO dispatcher',
    'responder' => entry.actorName != null ? 'by ${entry.actorName} (responder)' : 'by the responder',
    '' => null,
    _ => 'by ${entry.actorRole}',
  };
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.title, required this.subtitle, required this.at, required this.first});

  final String title;
  final String? subtitle;
  final DateTime? at;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final when = at == null ? null : DateFormat('MMM d, y • h:mm a').format(at!.toLocal());
    return Semantics(
      label: [title, ?subtitle, ?when].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                first ? Icons.flag_rounded : Icons.check_circle_rounded,
                color: first ? RapidAlertColors.lightText : RapidAlertColors.success,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (subtitle != null) Text(subtitle!, style: const TextStyle(color: RapidAlertColors.lightText)),
                    if (when != null)
                      Text(when, style: const TextStyle(fontSize: 12, color: RapidAlertColors.lightText)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
