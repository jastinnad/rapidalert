import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/reporter_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class ReportChatScreen extends StatefulWidget {
  const ReportChatScreen({
    super.key,
    required this.service,
    required this.reportId,
    required this.receiverId,
    required this.receiverName,
    this.trackingId,
  });

  final ReporterService service;

  /// The report's internal ID, which binds the conversation (API only).
  final int reportId;
  final int receiverId;
  final String receiverName;

  /// Shown in the header so the person knows which report this is about.
  final String? trackingId;

  @override
  State<ReportChatScreen> createState() => _ReportChatScreenState();
}

class _ReportChatScreenState extends State<ReportChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;

  /// The last load failed; shown only while there are no messages, so a
  /// failed load isn't mistaken for an empty conversation.
  bool _loadFailed = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final messages = await widget.service.loadReportMessages(widget.reportId);
      if (!mounted) return;
      final grew = messages.length > _messages.length;
      setState(() {
        _messages = messages;
        _loading = false;
        _loadFailed = false;
      });
      if (grew) _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await widget.service.sendReportMessage(
        reportId: widget.reportId,
        receiverId: widget.receiverId,
        text: text,
      );
      _controller.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send message.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.receiverName),
            if (widget.trackingId != null && widget.trackingId!.isNotEmpty)
              Text(
                'Report ${widget.trackingId}',
                key: const Key('chat-tracking-id'),
                style: const TextStyle(fontSize: 12, color: RapidAlertColors.lightText),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty && _loadFailed
                ? Center(
                    child: ErrorRetry(
                      message: "Couldn't load messages. Check your connection and try again.",
                      onRetry: () {
                        setState(() => _loading = true);
                        _load();
                      },
                    ),
                  )
                : _messages.isEmpty
                ? const Center(child: Text('No messages yet — say hello.'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMine = !msg.isResponder;
                      return Align(
                        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(10),
                          constraints: const BoxConstraints(maxWidth: 280),
                          decoration: BoxDecoration(
                            color: isMine ? RapidAlertColors.primaryRed : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.message,
                                style: TextStyle(color: isMine ? Colors.white : RapidAlertColors.darkText),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('h:mm a').format(msg.time.toLocal()),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isMine ? Colors.white70 : RapidAlertColors.lightText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    tooltip: 'Send message',
                    style: IconButton.styleFrom(backgroundColor: RapidAlertColors.primaryRed),
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
            ),
          ),
        ],
      ),
    );
  }
}
