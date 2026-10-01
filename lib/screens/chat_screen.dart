import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/offline_cache.dart' show isNetworkError;
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.service});

  final ResponderService service;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  String? _reportId;
  final _controller = TextEditingController();

  /// Load state of the selected report's chat, so a failed or unfinished
  /// load never reads as "No chat messages yet".
  bool _loading = false;
  String? _loadError;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final reports = widget.service.reports;
    _reportId = reports.isNotEmpty ? reports.first.id : null;
    if (_reportId != null) _load(_reportId!);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load(String reportId) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await widget.service.loadMessages(reportId);
      if (!mounted || reportId != _reportId) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted || reportId != _reportId) return;
      setState(() {
        _loading = false;
        _loadError = isNetworkError(e)
            ? "You're offline. Messages can't be loaded until you reconnect."
            : "Couldn't load messages. Please try again.";
      });
    }
  }

  Future<void> _send(IncidentReport report, int receiverId) async {
    final value = _controller.text.trim();
    if (value.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.service.sendResponderMessage(reportId: report.id, receiverId: receiverId, text: value);
      _controller.clear();
    } catch (_) {
      if (!mounted) return;
      // The text stays in the box so it can be sent again.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't send the message. Check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = widget.service.reports;
    IncidentReport? selectedReport;
    for (final r in reports) {
      if (r.id == _reportId) {
        selectedReport = r;
        break;
      }
    }
    // A guest's report has no account to message.
    final receiverId = selectedReport?.reporterUserId;

    return StreamBuilder<List<ChatMessage>>(
      stream: widget.service.chatStream,
      builder: (context, snapshot) {
        final messages = _reportId == null ? const <ChatMessage>[] : widget.service.messagesFor(_reportId!);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            const ScreenHeader(
              title: 'Responder Chat to Reporter',
              subtitle: 'Coordinate directly with reporter for location and safety updates.',
            ),
            const SizedBox(height: 12),
            if (reports.isEmpty)
              const GlassCard(child: Text('No assigned reports to chat about.'))
            else ...[
              GlassCard(
                child: DropdownButton<String>(
                  value: selectedReport?.id,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: reports
                      .map((r) => DropdownMenuItem(value: r.id, child: Text('${r.id} - ${r.reporterName}')))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _reportId = value);
                    _load(value);
                  },
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  children: [
                    SizedBox(
                      height: 320,
                      child: _messagesArea(messages, guestReport: selectedReport != null && receiverId == null),
                    ),
                    if (_loadError != null && messages.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 16, color: RapidAlertColors.warning),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              "Couldn't refresh messages; showing the last ones loaded.",
                              style: TextStyle(fontSize: 12, color: RapidAlertColors.warning),
                            ),
                          ),
                          TextButton(onPressed: () => _load(_reportId!), child: const Text('Retry')),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            enabled: receiverId != null,
                            decoration: const InputDecoration(
                              hintText: 'Send location or rescue instruction...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Send message',
                          onPressed: selectedReport == null || receiverId == null || _sending
                              ? null
                              : () => _send(selectedReport!, receiverId),
                          style: IconButton.styleFrom(backgroundColor: RapidAlertColors.operationsBlue),
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _messagesArea(List<ChatMessage> messages, {required bool guestReport}) {
    if (guestReport) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            "Chat isn't available for this report: it was sent without a Rapid Alert account, "
            'so the reporter has no inbox to receive messages.',
            textAlign: TextAlign.center,
            style: TextStyle(color: RapidAlertColors.lightText),
          ),
        ),
      );
    }
    if (messages.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (messages.isEmpty && _loadError != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorRetry(message: _loadError!, onRetry: () => _load(_reportId!)),
        ),
      );
    }
    if (messages.isEmpty) {
      return const Center(child: Text('No chat messages yet.'));
    }
    return ListView.builder(
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return Align(
          alignment: msg.isResponder ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: msg.isResponder ? RapidAlertColors.operationsBlue : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg.message, style: TextStyle(color: msg.isResponder ? Colors.white : RapidAlertColors.darkText)),
                const SizedBox(height: 4),
                Text(
                  DateFormat('h:mm a').format(msg.time.toLocal()),
                  style: TextStyle(fontSize: 11, color: msg.isResponder ? Colors.white70 : RapidAlertColors.lightText),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
