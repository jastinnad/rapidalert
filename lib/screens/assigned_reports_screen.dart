import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class AssignedReportsScreen extends StatefulWidget {
  const AssignedReportsScreen({super.key, required this.service});

  final ResponderService service;

  @override
  State<AssignedReportsScreen> createState() => _AssignedReportsScreenState();
}

class _AssignedReportsScreenState extends State<AssignedReportsScreen> {
  ReportStatus? _filter;
  String? _updatingReportId;

  Future<void> _advanceStatus(IncidentReport report, ReportStatus nextStatus) async {
    setState(() => _updatingReportId = report.id);
    try {
      await widget.service.updateReportStatus(report.id, nextStatus);
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
    return StreamBuilder<List<IncidentReport>>(
      stream: widget.service.reportsStream,
      initialData: widget.service.reports,
      builder: (context, snapshot) {
        final reports = snapshot.data ?? const <IncidentReport>[];
        final filtered = _filter == null
            ? reports
            : reports.where((r) => r.status == _filter).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            const ScreenHeader(
              title: 'Track Assigned Reports',
              subtitle: 'Review responder queue, update status, and prioritize need-help incidents.',
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_alt_rounded,
                    color: RapidAlertColors.operationsBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButton<ReportStatus?>(
                      value: _filter,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem<ReportStatus?>(
                          value: null,
                          child: Text('All Statuses'),
                        ),
                        ...ReportStatus.values.map(
                          (status) => DropdownMenuItem<ReportStatus?>(
                            value: status,
                            child: Text(_reportStatusLabel(status)),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _filter = value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (filtered.isEmpty)
              const GlassCard(
                child: Text('No reports matched your selected filter.'),
              )
            else
              ...filtered.map(
                (report) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                report.id,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _statusChip(report.status, report.needHelp),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${report.hazard} - ${report.location}'),
                        const SizedBox(height: 2),
                        Text(
                          'Reporter: ${report.reporterName}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Updated: ${DateFormat('MMM d, h:mm a').format(report.updated)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: RapidAlertColors.lightText),
                        ),
                        if (_nextStep(report.status) != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _updatingReportId == report.id
                                  ? null
                                  : () => _advanceStatus(report, _nextStep(report.status)!.$2),
                              child: _updatingReportId == report.id
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(_nextStep(report.status)!.$1),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The one forward transition available from a status, matching the
  /// backend's real StatusMachine — `resolved`/`completed` have none.
  (String, ReportStatus)? _nextStep(ReportStatus status) {
    return switch (status) {
      ReportStatus.assigned => ('Start — En Route', ReportStatus.enRoute),
      ReportStatus.enRoute => ('Arrived — On Scene', ReportStatus.onScene),
      ReportStatus.onScene => ('Mark Resolved', ReportStatus.resolved),
      ReportStatus.resolved || ReportStatus.completed => null,
    };
  }

  Widget _statusChip(ReportStatus status, bool needHelp) {
    final color = needHelp ? RapidAlertColors.warning : _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        needHelp ? 'Need Help' : _reportStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

Color _statusColor(ReportStatus status) {
  return switch (status) {
    ReportStatus.assigned => RapidAlertColors.statusAssigned,
    ReportStatus.enRoute => RapidAlertColors.enRoute,
    ReportStatus.onScene => RapidAlertColors.onSceneAccent,
    ReportStatus.resolved => RapidAlertColors.statusResolved,
    ReportStatus.completed => RapidAlertColors.statusCompleted,
  };
}

String _reportStatusLabel(ReportStatus status) {
  return switch (status) {
    ReportStatus.assigned => 'Assigned',
    ReportStatus.enRoute => 'En Route',
    ReportStatus.onScene => 'On Scene',
    ReportStatus.resolved => 'Resolved',
    ReportStatus.completed => 'Completed',
  };
}
