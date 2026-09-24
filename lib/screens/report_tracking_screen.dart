import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/device_id_service.dart';
import '../data/reporter_service.dart';
import '../models/reporter_models.dart';
import 'ui_components.dart';

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

  @override
  void initState() {
    super.initState();
    // Show the reporter's latest report by default, if any.
    _search();
  }

  @override
  void dispose() {
    _trackingIdController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final deviceId = await DeviceIdService.getOrCreate();
      final report = await widget.service.trackReport(
        trackingId: _trackingIdController.text.trim().isEmpty ? null : _trackingIdController.text.trim(),
        clientReportId: deviceId,
      );
      if (!mounted) return;
      setState(() => _report = report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load report. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            if (!_loading && _report != null) _ReportCard(report: _report!),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final TrackedReport report;

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
                Text('Responder: ${report.assignedResponderName}'),
              ],
            ),
            const SizedBox(height: 6),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'resolved' || 'completed' => RapidAlertColors.success,
      'received' || 'reported' => RapidAlertColors.warning,
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
