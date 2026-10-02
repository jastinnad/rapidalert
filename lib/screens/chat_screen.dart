import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/offline_cache.dart' show isNetworkError;
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.service, this.initialReportId});

  final ResponderService service;

  /// Report to open on (e.g. from the map's Message button); defaults to the
  /// first assigned report.
  final String? initialReportId;

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

  /// The backend has no push for chat, so the open conversation is fetched
  /// again on this interval (the reporter's chat screen does the same).
  static const _refreshEvery = Duration(seconds: 5);
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _select(widget.service.reports, widget.initialReportId);
    _pollTimer = Timer.periodic(_refreshEvery, (_) => _poll());
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requested = widget.initialReportId;
    if (requested != null && requested != oldWidget.initialReportId && requested != _reportId) {
      _select(widget.service.reports, requested);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Picks [wanted] when it is assigned, else the first report, and loads it.
  void _select(List<IncidentReport> reports, String? wanted) {
    if (reports.isEmpty) return;
    final id = reports.any((r) => r.id == wanted) ? wanted! : reports.first.id;
    _reportId = id;
    _load(id);
  }

  Future<void> _load(String reportId) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      await widget.service.loadMessages(reportId);
      if (!mounted || reportId != _reportId) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted || reportId != _reportId) return;
      setState(() {
        _loading = false;
        _loadError = _errorText(e);
      });
    }
  }

  /// Background refresh: quiet while it works; a failure shows the
  /// "couldn't refresh" line over the messages already loaded.
  Future<void> _poll() async {
    final reportId = _reportId;
    if (reportId == null || _loading || _sending) return;
    IncidentReport? report;
    for (final r in widget.service.reports) {
      if (r.id == reportId) report = r;
    }
    if (report == null || report.isGuestReport) return;
    try {
      await widget.service.loadMessages(reportId);
      if (mounted && reportId == _reportId && _loadError != null) setState(() => _loadError = null);
    } catch (e) {
      if (mounted && reportId == _reportId) setState(() => _loadError = _errorText(e));
    }
  }

  static String _errorText(Object e) => isNetworkError(e)
      ? "You're offline. Messages can't be loaded until you reconnect."
      : "Couldn't load messages. Please try again.";

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final chatHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * 0.5).clamp(260.0, 520.0)
            : 320.0;
        return StreamBuilder<List<IncidentReport>>(
          stream: widget.service.reportsStream,
          initialData: widget.service.reports,
          builder: (context, reportsSnapshot) {
            final reports = reportsSnapshot.data ?? const <IncidentReport>[];
            // The list loaded after this screen opened, or the open report
            // left it: move to an assigned one.
            if (reports.isNotEmpty && !reports.any((r) => r.id == _reportId)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // _select's load rebuilds the screen.
                if (mounted && !reports.any((r) => r.id == _reportId)) _select(reports, null);
              });
            }
            return _buildChat(reports, chatHeight);
          },
        );
      },
    );
  }

  Widget _buildChat(List<IncidentReport> reports, double chatHeight) {
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
              subtitle: 'Each conversation belongs to one report and its reporter.',
            ),
            const SizedBox(height: 12),
            if (reports.isEmpty)
              const GlassCard(child: Text('No assigned reports to chat about.'))
            else ...[
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButton<String>(
                      value: selectedReport?.id,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: reports
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.id,
                              child: Text('${r.displayId} - ${r.reporterName}', overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null || value == _reportId) return;
                        setState(() => _reportId = value);
                        _load(value);
                      },
                    ),
                    if (selectedReport != null) _ConversationHeader(report: selectedReport),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  children: [
                    SizedBox(
                      height: chatHeight,
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
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                              hintText: 'Send location or rescue instruction...',
                              border: OutlineInputBorder(),
                              counterText: '',
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
    final today = DateUtils.dateOnly(DateTime.now());
    // Newest at the bottom, and the list starts there.
    return ListView.builder(
      reverse: true,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[messages.length - 1 - index];
        final local = msg.time.toLocal();
        final time = DateUtils.dateOnly(local) == today
            ? DateFormat('h:mm a').format(local)
            : DateFormat('MMM d, h:mm a').format(local);
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
                if (!msg.isResponder && msg.sender.isNotEmpty)
                  Text(
                    msg.sender,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: RapidAlertColors.labelText),
                  ),
                Text(msg.message, style: TextStyle(color: msg.isResponder ? Colors.white : RapidAlertColors.darkText)),
                const SizedBox(height: 4),
                Text(
                  time,
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

/// Which report and which reporter this conversation is with, and whether
/// the backend says that reporter is online (never guessed).
class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({required this.report});

  final IncidentReport report;

  @override
  Widget build(BuildContext context) {
    final online = report.reporterOnline;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.trackingId.isNotEmpty ? 'Report ${report.trackingId}' : 'Report ${report.id}',
            key: const Key('responder-chat-tracking-id'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Row(
            key: const Key('responder-chat-presence'),
            children: [
              if (!report.isGuestReport && online != null) ...[
                Icon(
                  Icons.circle,
                  size: 10,
                  color: online ? RapidAlertColors.success : RapidAlertColors.lightText,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  report.isGuestReport
                      ? '${report.reporterName} · Guest report (no account)'
                      : online == null
                      ? report.reporterName
                      : '${report.reporterName} · ${online ? 'Online' : 'Not online right now'}',
                  style: const TextStyle(fontSize: 12, color: RapidAlertColors.lightText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
