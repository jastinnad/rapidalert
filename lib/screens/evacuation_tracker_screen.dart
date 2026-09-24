import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class EvacuationTrackerScreen extends StatefulWidget {
  const EvacuationTrackerScreen({super.key, required this.service});

  final ResponderService service;

  @override
  State<EvacuationTrackerScreen> createState() => _EvacuationTrackerScreenState();
}

class _EvacuationTrackerScreenState extends State<EvacuationTrackerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Evacuation Tracker')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => _EvacuationFormSheet(service: widget.service),
        ),
        backgroundColor: RapidAlertColors.primaryRed,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<EvacuationRecordEntry>>(
        stream: widget.service.evacuationRecordsStream,
        initialData: widget.service.evacuationRecords,
        builder: (context, snapshot) {
          final records = snapshot.data ?? const <EvacuationRecordEntry>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const ScreenHeader(
                title: 'Evacuation Centers',
                subtitle: 'Demographics and status updates for centers you are tracking.',
              ),
              const SizedBox(height: 16),
              if (records.isEmpty)
                const GlassCard(child: Text('No evacuation records yet.'))
              else
                ...records.map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EvacuationCard(record: record),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EvacuationCard extends StatelessWidget {
  const _EvacuationCard({required this.record});

  final EvacuationRecordEntry record;

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
                  record.centerName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              _StatusChip(status: record.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${record.trackingId} · ${record.barangay} · ${record.hazardType}',
            style: const TextStyle(fontSize: 12.5, color: RapidAlertColors.lightText),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _StatItem(label: 'Total', value: record.totalEvacuees),
              _StatItem(label: 'Male', value: record.maleCount),
              _StatItem(label: 'Female', value: record.femaleCount),
              _StatItem(label: 'Vulnerable', value: record.vulnerableCount),
            ],
          ),
          if (record.fieldNotes != null && record.fieldNotes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(record.fieldNotes!, style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 8),
          Text(
            'Updated ${DateFormat('MMM d, h:mm a').format(record.updatedAt)}',
            style: const TextStyle(fontSize: 11.5, color: RapidAlertColors.lightText),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(fontSize: 11, color: RapidAlertColors.lightText)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final EvacStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      EvacStatus.preparing => ('Preparing', RapidAlertColors.operationsBlue),
      EvacStatus.ongoing => ('Ongoing', RapidAlertColors.warning),
      EvacStatus.completed => ('Completed', RapidAlertColors.success),
      EvacStatus.needsSupport => ('Needs Support', RapidAlertColors.primaryRed),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

class _EvacuationFormSheet extends StatefulWidget {
  const _EvacuationFormSheet({required this.service});

  final ResponderService service;

  @override
  State<_EvacuationFormSheet> createState() => _EvacuationFormSheetState();
}

class _EvacuationFormSheetState extends State<_EvacuationFormSheet> {
  final _trackingIdController = TextEditingController();
  final _barangayController = TextEditingController();
  final _notesController = TextEditingController();
  final _countControllers = {
    'total': TextEditingController(text: '0'),
    'male': TextEditingController(text: '0'),
    'female': TextEditingController(text: '0'),
    'children': TextEditingController(text: '0'),
    'seniors': TextEditingController(text: '0'),
    'pregnant': TextEditingController(text: '0'),
    'pwd': TextEditingController(text: '0'),
  };

  String _hazardType = evacuationHazardTypes.first;
  String _centerName = evacuationCenterNames.first;
  EvacStatus _status = EvacStatus.preparing;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _trackingIdController.dispose();
    _barangayController.dispose();
    _notesController.dispose();
    for (final c in _countControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _count(String key) => int.tryParse(_countControllers[key]!.text.trim()) ?? 0;

  Future<void> _submit() async {
    if (_trackingIdController.text.trim().isEmpty || _barangayController.text.trim().isEmpty) {
      setState(() => _error = 'Tracking ID and barangay are required.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.service.saveEvacuationRecord(
        trackingId: _trackingIdController.text.trim().toUpperCase(),
        hazardType: _hazardType,
        barangay: _barangayController.text.trim(),
        centerName: _centerName,
        status: _status,
        totalEvacuees: _count('total'),
        maleCount: _count('male'),
        femaleCount: _count('female'),
        childrenCount: _count('children'),
        seniorsCount: _count('seniors'),
        pregnantCount: _count('pregnant'),
        pwdCount: _count('pwd'),
        fieldNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Failed to save record. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Center Update', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _trackingIdController,
              decoration: const InputDecoration(labelText: 'Tracking ID', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _hazardType,
              decoration: const InputDecoration(labelText: 'Hazard Type', border: OutlineInputBorder()),
              items: evacuationHazardTypes
                  .map((h) => DropdownMenuItem(value: h, child: Text(h[0].toUpperCase() + h.substring(1))))
                  .toList(),
              onChanged: (value) => setState(() => _hazardType = value ?? _hazardType),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _barangayController,
              decoration: const InputDecoration(labelText: 'Barangay', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _centerName,
              decoration: const InputDecoration(labelText: 'Evacuation Center', border: OutlineInputBorder()),
              items: evacuationCenterNames
                  .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) => setState(() => _centerName = value ?? _centerName),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<EvacStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: EvacStatus.preparing, child: Text('Preparing')),
                DropdownMenuItem(value: EvacStatus.ongoing, child: Text('Ongoing Evacuation')),
                DropdownMenuItem(value: EvacStatus.completed, child: Text('Completed')),
                DropdownMenuItem(value: EvacStatus.needsSupport, child: Text('Needs Support')),
              ],
              onChanged: (value) => setState(() => _status = value ?? _status),
            ),
            const SizedBox(height: 16),
            const Text('Headcount', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.6,
              children: [
                _countField('total', 'Total'),
                _countField('male', 'Male'),
                _countField('female', 'Female'),
                _countField('children', 'Children'),
                _countField('seniors', 'Seniors'),
                _countField('pregnant', 'Pregnant'),
                _countField('pwd', 'PWD'),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Field Notes (optional)', border: OutlineInputBorder()),
              maxLines: 3,
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
                    : const Text('Save Update', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countField(String key, String label) {
    return TextField(
      controller: _countControllers[key],
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
    );
  }
}
