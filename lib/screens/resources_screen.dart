import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key, required this.service});

  final ResponderService service;

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resources')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => _ResourceFormSheet(service: widget.service),
        ),
        backgroundColor: RapidAlertColors.primaryRed,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<ResourceRequestEntry>>(
        stream: widget.service.resourceRequestsStream,
        initialData: widget.service.resourceRequests,
        builder: (context, snapshot) {
          final requests = List<ResourceRequestEntry>.from(snapshot.data ?? const [])
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const ScreenHeader(
                title: 'Resource Requests',
                subtitle: 'Request supplies or equipment for your assigned reports.',
              ),
              const SizedBox(height: 16),
              if (requests.isEmpty)
                const GlassCard(child: Text('No resource requests yet.'))
              else
                ...requests.map(
                  (request) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ResourceCard(request: request),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.request});

  final ResourceRequestEntry request;

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
                  request.itemName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              _PriorityChip(priority: request.priority),
              const SizedBox(width: 6),
              _StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${request.trackingId} · ${_categoryLabel(request.category)}'
            '${request.locationHint != null ? ' · ${request.locationHint}' : ''}',
            style: const TextStyle(fontSize: 12.5, color: RapidAlertColors.lightText),
          ),
          const SizedBox(height: 8),
          Text(
            'Qty: ${request.quantityFulfilled}/${request.quantityRequested}'
            '${request.unit != null ? ' ${request.unit}' : ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (request.notes != null && request.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(request.notes!, style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 8),
          Text(
            'Requested ${DateFormat('MMM d, h:mm a').format(request.createdAt)}',
            style: const TextStyle(fontSize: 11.5, color: RapidAlertColors.lightText),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(String category) =>
      category.isEmpty ? 'Other' : category[0].toUpperCase() + category.substring(1);
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final ResourcePriority priority;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (priority) {
      ResourcePriority.critical => ('Critical', RapidAlertColors.primaryRed),
      ResourcePriority.high => ('High', RapidAlertColors.warning),
      ResourcePriority.normal => ('Normal', RapidAlertColors.operationsBlue),
      ResourcePriority.low => ('Low', RapidAlertColors.lightText),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ResourceStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ResourceStatus.pending => ('Pending', RapidAlertColors.lightText),
      ResourceStatus.approved => ('Approved', RapidAlertColors.operationsBlue),
      ResourceStatus.inProgress => ('In Progress', RapidAlertColors.warning),
      ResourceStatus.fulfilled => ('Fulfilled', RapidAlertColors.success),
      ResourceStatus.cancelled => ('Cancelled', RapidAlertColors.primaryRed),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _ResourceFormSheet extends StatefulWidget {
  const _ResourceFormSheet({required this.service});

  final ResponderService service;

  @override
  State<_ResourceFormSheet> createState() => _ResourceFormSheetState();
}

class _ResourceFormSheetState extends State<_ResourceFormSheet> {
  final _itemNameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _unitController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  String? _reportId;
  String _category = resourceCategories.first;
  ResourcePriority _priority = ResourcePriority.normal;
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
    _itemNameController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
    if (_reportId == null || _itemNameController.text.trim().isEmpty || quantity < 1) {
      setState(() => _error = 'Select a report, item name, and a quantity of at least 1.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.service.createResourceRequest(
        reportId: _reportId!,
        category: _category,
        itemName: _itemNameController.text.trim(),
        quantityRequested: quantity,
        unit: _unitController.text.trim().isEmpty ? null : _unitController.text.trim(),
        priority: _priority,
        locationHint: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Failed to submit request. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = widget.service.reports;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Resource Request', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
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
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: resourceCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c[0].toUpperCase() + c.substring(1))))
                  .toList(),
              onChanged: (value) => setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _itemNameController,
              decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _unitController,
                    decoration: const InputDecoration(labelText: 'Unit (optional)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ResourcePriority>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: ResourcePriority.low, child: Text('Low')),
                DropdownMenuItem(value: ResourcePriority.normal, child: Text('Normal')),
                DropdownMenuItem(value: ResourcePriority.high, child: Text('High')),
                DropdownMenuItem(value: ResourcePriority.critical, child: Text('Critical')),
              ],
              onChanged: (value) => setState(() => _priority = value ?? _priority),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location Hint (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
              maxLines: 2,
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
                    : const Text('Submit Request', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
