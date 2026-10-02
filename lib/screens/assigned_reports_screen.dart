import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class AssignedReportsScreen extends StatefulWidget {
  const AssignedReportsScreen({super.key, required this.service, this.onOpenMap});

  final ResponderService service;

  /// Opens the Map tab on a report (its location and full details). Called
  /// after Start — En Route succeeds, and from each report's map button.
  final ValueChanged<String>? onOpenMap;

  @override
  State<AssignedReportsScreen> createState() => _AssignedReportsScreenState();
}

class _AssignedReportsScreenState extends State<AssignedReportsScreen> {
  ReportStatus? _filter;
  String? _updatingReportId;
  bool _retrying = false;

  Future<void> _advanceStatus(IncidentReport report, ReportStatus nextStatus) async {
    setState(() => _updatingReportId = report.id);
    try {
      await widget.service.updateReportStatus(report.id, nextStatus);
      // Only once the backend accepted it: the responder is now on the way.
      if (mounted && nextStatus == ReportStatus.enRoute) widget.onOpenMap?.call(report.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update status. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _updatingReportId = null);
    }
  }

  Future<void> _retryLoad() async {
    setState(() => _retrying = true);
    await widget.service.refreshReports();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ReportListStatus>(
      stream: widget.service.reportListStatusStream,
      initialData: widget.service.reportListStatus,
      builder: (context, statusSnapshot) => _buildList(context, statusSnapshot.data ?? const ReportListStatus()),
    );
  }

  Widget _buildList(BuildContext context, ReportListStatus loadStatus) {
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
                            child: Text(reportStatusLabel(status)),
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
            // Never loaded: an empty list would wrongly read as "nothing assigned".
            if (!loadStatus.loaded && loadStatus.errorMessage != null)
              GlassCard(
                child: ErrorRetry(message: loadStatus.errorMessage!, onRetry: _retrying ? null : _retryLoad),
              )
            else if (!loadStatus.loaded)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (loadStatus.errorMessage != null) ...[
                _RefreshFailedBanner(
                  message: loadStatus.errorMessage!,
                  lastLoadedAt: loadStatus.lastLoadedAt!,
                  onRetry: _retrying ? null : _retryLoad,
                ),
                const SizedBox(height: 12),
              ],
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
                                report.displayId,
                                key: Key('report-title-${report.id}'),
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
                        if (responderNextStep(report.status) != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: Key('report-next-step-${report.id}'),
                              onPressed: _updatingReportId == report.id
                                  ? null
                                  : () => _advanceStatus(report, responderNextStep(report.status)!.$2),
                              child: _updatingReportId == report.id
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(responderNextStep(report.status)!.$1),
                            ),
                          ),
                        ],
                        if (widget.onOpenMap != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: Key('report-open-map-${report.id}'),
                              onPressed: () => widget.onOpenMap!(report.id),
                              icon: const Icon(Icons.map_rounded, size: 18),
                              label: const Text('Map & details'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _statusChip(ReportStatus status, bool needHelp) {
    final color = needHelp ? RapidAlertColors.warning : reportStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        needHelp ? 'Need Help' : reportStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The list below is the last one that loaded, not a current one.
class _RefreshFailedBanner extends StatelessWidget {
  const _RefreshFailedBanner({required this.message, required this.lastLoadedAt, required this.onRetry});

  final String message;
  final DateTime lastLoadedAt;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          border: Border.all(color: const Color(0xFFFED7AA)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFF9A3412), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$message Showing the list from ${DateFormat('h:mm a').format(lastLoadedAt)}.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412), fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

Color reportStatusColor(ReportStatus status) {
  return switch (status) {
    ReportStatus.assigned => RapidAlertColors.statusAssigned,
    ReportStatus.enRoute => RapidAlertColors.enRoute,
    ReportStatus.onScene => RapidAlertColors.onSceneAccent,
    ReportStatus.resolved => RapidAlertColors.statusResolved,
    ReportStatus.completed => RapidAlertColors.statusCompleted,
  };
}

String reportStatusLabel(ReportStatus status) {
  return switch (status) {
    ReportStatus.assigned => 'Assigned',
    ReportStatus.enRoute => 'En Route',
    ReportStatus.onScene => 'On Scene',
    ReportStatus.resolved => 'Resolved',
    ReportStatus.completed => 'Completed',
  };
}
