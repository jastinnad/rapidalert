import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reports = widget.service.reports;
    _reportId ??= reports.isNotEmpty ? reports.first.id : null;
    IncidentReport? selectedReport;
    for (final r in reports) {
      if (r.id == _reportId) {
        selectedReport = r;
        break;
      }
    }

    return StreamBuilder<List<ChatMessage>>(
      stream: widget.service.chatStream,
      builder: (context, snapshot) {
        final messages = _reportId == null
            ? const <ChatMessage>[]
            : widget.service.messagesFor(_reportId!);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            const ScreenHeader(
              title: 'Responder Chat to Reporter',
              subtitle: 'Coordinate directly with reporter for location and safety updates.',
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: DropdownButton<String>(
                value: _reportId,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: reports
                    .map(
                      (r) => DropdownMenuItem(
                        value: r.id,
                        child: Text('${r.id} - ${r.reporterName}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _reportId = value),
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                children: [
                  SizedBox(
                    height: 320,
                    child: messages.isEmpty
                        ? const Center(child: Text('No chat messages yet.'))
                        : ListView.builder(
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final msg = messages[index];
                              return Align(
                                alignment: msg.isResponder
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  padding: const EdgeInsets.all(10),
                                  constraints: const BoxConstraints(
                                    maxWidth: 260,
                                  ),
                                  decoration: BoxDecoration(
                                    color: msg.isResponder
                                        ? RapidAlertColors.operationsBlue
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        msg.message,
                                        style: TextStyle(
                                          color: msg.isResponder
                                              ? Colors.white
                                              : RapidAlertColors.darkText,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('h:mm a').format(msg.time),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: msg.isResponder
                                              ? Colors.white70
                                              : RapidAlertColors.lightText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: 'Send location or rescue instruction...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () {
                          final value = _controller.text.trim();
                          final receiverId = selectedReport?.reporterUserId;
                          if (_reportId == null || value.isEmpty || receiverId == null) {
                            return;
                          }
                          widget.service.sendResponderMessage(
                            reportId: _reportId!,
                            receiverId: receiverId,
                            text: value,
                          );
                          _controller.clear();
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: RapidAlertColors.operationsBlue,
                        ),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
