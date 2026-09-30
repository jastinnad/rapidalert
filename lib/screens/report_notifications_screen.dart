import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/offline_cache.dart';
import '../data/reporter_service.dart';
import '../models/reporter_models.dart';
import 'ui_components.dart';

/// The updates the backend sent this account about one report
/// (`GET /api/reports/notifications`). The backend keeps no read/unread
/// state, so none is shown.
class ReportNotificationsScreen extends StatefulWidget {
  const ReportNotificationsScreen({super.key, required this.service, required this.reportId, required this.trackingId});

  final ReporterService service;
  final int reportId;
  final String trackingId;

  @override
  State<ReportNotificationsScreen> createState() => _ReportNotificationsScreenState();
}

class _ReportNotificationsScreenState extends State<ReportNotificationsScreen> {
  List<ReportNotification>? _items;
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
      final items = await widget.service.loadReportNotifications(widget.reportId);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = isNetworkError(e)
            ? "You're offline. Connect to the internet to see updates."
            : "Couldn't load updates right now. Please try again.",
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final dateFormat = DateFormat('MMM d, y • h:mm a');

    return Scaffold(
      backgroundColor: RapidAlertColors.background,
      appBar: AppBar(title: Text('Updates · ${widget.trackingId}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading && items == null)
              const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              ErrorRetry(message: _error!, onRetry: _load)
            else if (items == null || items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                  'No updates yet. You will see one here each time your report changes status.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: RapidAlertColors.lightText),
                ),
              )
            else
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notifications_active_outlined, color: RapidAlertColors.primaryRed, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.message, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
                              if (item.createdAt != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  dateFormat.format(item.createdAt!),
                                  style: const TextStyle(fontSize: 12, color: RapidAlertColors.lightText),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
