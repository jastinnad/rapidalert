import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class FollowUpBoardScreen extends StatefulWidget {
  const FollowUpBoardScreen({super.key, required this.service});

  final ResponderService service;

  @override
  State<FollowUpBoardScreen> createState() => _FollowUpBoardScreenState();
}

class _FollowUpBoardScreenState extends State<FollowUpBoardScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Follow-Up Board')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCreateSheet(context),
        backgroundColor: RapidAlertColors.primaryRed,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<FollowUp>>(
        stream: widget.service.followUpsStream,
        initialData: widget.service.followUps,
        builder: (context, snapshot) {
          final followUps = List<FollowUp>.from(snapshot.data ?? const [])
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const ScreenHeader(
                title: 'Upcoming Follow-Ups',
                subtitle: 'Scheduled check-ins on assigned reports for the next 7 days.',
              ),
              const SizedBox(height: 16),
              if (followUps.isEmpty)
                const GlassCard(child: Text('No follow-ups scheduled.'))
              else
                ...followUps.map(
                  (followUp) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FollowUpCard(
                      followUp: followUp,
                      onComplete: () => widget.service.completeFollowUp(followUp.id),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CreateFollowUpSheet(service: widget.service),
    );
  }
}

class _FollowUpCard extends StatelessWidget {
  const _FollowUpCard({required this.followUp, required this.onComplete});

  final FollowUp followUp;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${followUp.trackingId} - ${followUp.hazard}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              _PriorityChip(priority: followUp.priority),
            ],
          ),
          const SizedBox(height: 6),
          Text(followUp.reason),
          if (followUp.notes != null && followUp.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              followUp.notes!,
              style: const TextStyle(fontSize: 13, color: RapidAlertColors.lightText),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 15,
                color: followUp.isOverdue ? RapidAlertColors.primaryRed : RapidAlertColors.lightText,
              ),
              const SizedBox(width: 4),
              Text(
                DateFormat('MMM d, h:mm a').format(followUp.scheduledAt),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: followUp.isOverdue ? FontWeight.w700 : FontWeight.w400,
                  color: followUp.isOverdue ? RapidAlertColors.primaryRed : RapidAlertColors.lightText,
                ),
              ),
              if (followUp.isOverdue) ...[
                const SizedBox(width: 6),
                const Text(
                  'OVERDUE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: RapidAlertColors.primaryRed),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (!followUp.isCompleted)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onComplete,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Mark Complete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RapidAlertColors.success,
                  side: const BorderSide(color: RapidAlertColors.success),
                ),
              ),
            )
          else
            const Text(
              'Completed',
              style: TextStyle(color: RapidAlertColors.success, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final FollowUpPriority priority;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (priority) {
      FollowUpPriority.high => ('High', RapidAlertColors.primaryRed),
      FollowUpPriority.medium => ('Medium', RapidAlertColors.warning),
      FollowUpPriority.low => ('Low', RapidAlertColors.operationsBlue),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _CreateFollowUpSheet extends StatefulWidget {
  const _CreateFollowUpSheet({required this.service});

  final ResponderService service;

  @override
  State<_CreateFollowUpSheet> createState() => _CreateFollowUpSheetState();
}

class _CreateFollowUpSheetState extends State<_CreateFollowUpSheet> {
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  String? _reportId;
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 2));
  FollowUpPriority _priority = FollowUpPriority.medium;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final reports = widget.service.reports;
    _reportId = reports.isNotEmpty ? reports.first.id : null;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null) return;

    setState(() {
      _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (_reportId == null || _reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Select a report and enter a reason.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.service.createFollowUp(
        reportId: _reportId!,
        reason: _reasonController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        scheduledAt: _scheduledAt,
        priority: _priority,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Failed to create follow-up. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = widget.service.reports;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New Follow-Up', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _reportId,
            decoration: const InputDecoration(labelText: 'Report', border: OutlineInputBorder()),
            items: reports
                .map((r) => DropdownMenuItem(value: r.id, child: Text('${r.id} - ${r.location}')))
                .toList(),
            onChanged: (value) => setState(() => _reportId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDateTime,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Scheduled at', border: OutlineInputBorder()),
              child: Text(DateFormat('MMM d, yyyy h:mm a').format(_scheduledAt)),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<FollowUpPriority>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: FollowUpPriority.high, child: Text('High')),
              DropdownMenuItem(value: FollowUpPriority.medium, child: Text('Medium')),
              DropdownMenuItem(value: FollowUpPriority.low, child: Text('Low')),
            ],
            onChanged: (value) => setState(() => _priority = value ?? FollowUpPriority.medium),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: RapidAlertColors.primaryRed)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: RapidAlertColors.primaryRed,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Create Follow-Up', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
