import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/preparedness_content.dart';

/// Opens the preparedness assistant — a native port of the website's guided
/// "Rapid Preparedness AI" widget (public/js/chatbot.js + css/chatbot.css).
Future<void> showPreparednessAssistant(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const PreparednessAssistantSheet(),
  );
}

class _ChatEntry {
  const _ChatEntry({required this.fromBot, required this.text});

  final bool fromBot;
  final String text;
}

/// Survives closing and reopening the sheet, like the web widget's
/// localStorage history. The web restores the last 8 messages on each page
/// load; reopening the sheet does the same.
class _Conversation {
  static final entries = <_ChatEntry>[];
  static String? selectedHazard;
}

class PreparednessAssistantSheet extends StatefulWidget {
  const PreparednessAssistantSheet({super.key});

  @override
  State<PreparednessAssistantSheet> createState() => _PreparednessAssistantSheetState();
}

class _PreparednessAssistantSheetState extends State<PreparednessAssistantSheet> {
  static const _typingDelay = Duration(milliseconds: 900);
  static const _tapCooldown = Duration(milliseconds: 350);

  final _latestKey = GlobalKey();
  Timer? _typingTimer;
  bool _typing = false;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final entries = _Conversation.entries;
    if (entries.length > 8) {
      entries.removeRange(0, entries.length - 8);
    }
    if (entries.isEmpty) {
      entries.add(const _ChatEntry(fromBot: true, text: preparednessGreeting));
    }
    _scrollToLatest();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    super.dispose();
  }

  bool _acceptTap() {
    final now = DateTime.now();
    if (now.difference(_lastTapAt) < _tapCooldown) return false;
    _lastTapAt = now;
    return true;
  }

  void _add(bool fromBot, String text) {
    _Conversation.entries.add(_ChatEntry(fromBot: fromBot, text: text));
  }

  /// Scrolls the newest message's top into view, like the web's
  /// scrollIntoView({block: 'start'}), so long tip lists read from the top.
  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _latestKey.currentContext;
      if (target == null || !mounted) return;
      Scrollable.ensureVisible(target, alignment: 0, duration: const Duration(milliseconds: 200));
    });
  }

  void _selectHazard(HazardCard card) {
    final response = hazardResponses[card.key];
    if (response == null || !_acceptTap()) return;

    setState(() {
      _Conversation.selectedHazard = card.key;
      _add(false, card.label);
      _typing = true;
    });
    _scrollToLatest();

    _typingTimer?.cancel();
    _typingTimer = Timer(_typingDelay, () {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _add(true, '${response.title}: ${response.body}');
      });
      _scrollToLatest();
    });
  }

  void _showInfo(PreparednessFollowUp followUp) {
    final content = preparednessInfo[followUp.infoKey];
    if (content == null || !_acceptTap()) return;

    setState(() {
      _add(false, followUp.label);
      _add(true, content);
    });
    _scrollToLatest();
  }

  void _backToHazards() {
    if (!_acceptTap()) return;
    _typingTimer?.cancel();
    setState(() {
      _typing = false;
      _Conversation.selectedHazard = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _Conversation.entries;
    final selected = hazardResponses[_Conversation.selectedHazard];

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF9FAFB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: RapidAlertColors.border)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const _Header(),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFF9FAFB), Colors.white],
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    children: [
                      for (var i = 0; i < entries.length; i++)
                        _MessageRow(
                          key: i == entries.length - 1 ? _latestKey : null,
                          entry: entries[i],
                        ),
                      if (_typing) const _TypingIndicator(),
                    ],
                  ),
                ),
              ),
              _ChoicesPanel(
                selected: selected,
                selectedKey: _Conversation.selectedHazard,
                showFollowUps: selected != null && !_typing,
                onHazard: _selectHazard,
                onFollowUp: _showInfo,
                onBack: _backToHazards,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 12),
      decoration: const BoxDecoration(
        color: Color(0xF5FFFFFF),
        border: Border(bottom: BorderSide(color: RapidAlertColors.border)),
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: const Color(0xFFD1D5DB), borderRadius: BorderRadius.circular(2)),
          ),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PREPAREDNESS ASSISTANT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.9,
                        color: RapidAlertColors.primaryRed,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Rapid Preparedness AI',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 34,
                height: 34,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Close',
                  style: IconButton.styleFrom(
                    shape: const CircleBorder(),
                    foregroundColor: RapidAlertColors.lightText,
                    hoverColor: const Color(0xFFFEF2F2),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({super.key, required this.entry});

  final _ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final bot = entry.fromBot;
    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: bot ? const Color(0xFFF3F4F6) : const Color(0xFFFEF2F2),
          border: bot ? null : Border.all(color: const Color(0xFFFECACA)),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(bot ? 6 : 16),
            topRight: Radius.circular(bot ? 16 : 6),
            bottomLeft: const Radius.circular(16),
            bottomRight: const Radius.circular(16),
          ),
        ),
        child: Text(
          entry.text,
          style: TextStyle(
            fontSize: 14,
            height: 1.55,
            color: bot ? const Color(0xFF1F2937) : const Color(0xFF7F1D1D),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: bot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: bot
            ? [const _Avatar.bot(), const SizedBox(width: 8), bubble, const SizedBox(width: 42)]
            : [const SizedBox(width: 42), bubble, const SizedBox(width: 8), const _Avatar.user()],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar.bot()
      : label = 'AI',
        background = Colors.white,
        foreground = RapidAlertColors.primaryRed,
        borderColor = const Color(0xFFFECACA);

  const _Avatar.user()
      : label = 'You',
        background = const Color(0xFFFFF5F5),
        foreground = RapidAlertColors.linkRed,
        borderColor = const Color(0xFFF5C2C7);

  final String label;
  final Color background;
  final Color foreground;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle, border: Border.all(color: borderColor)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: foreground)),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rapid Preparedness AI is typing',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const _Avatar.bot(),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Opacity(
                          opacity: _dotOpacity(i),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: RapidAlertColors.primaryRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _dotOpacity(int index) {
    final phase = (_controller.value * 3 - index) % 3;
    return phase < 1 ? 1 : 0.35;
  }
}

class _ChoicesPanel extends StatelessWidget {
  const _ChoicesPanel({
    required this.selected,
    required this.selectedKey,
    required this.showFollowUps,
    required this.onHazard,
    required this.onFollowUp,
    required this.onBack,
  });

  final HazardResponse? selected;
  final String? selectedKey;
  final bool showFollowUps;
  final ValueChanged<HazardCard> onHazard;
  final ValueChanged<PreparednessFollowUp> onFollowUp;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    // While a hazard's answer is still "typing", the web hides the grid and
    // hasn't drawn the follow-ups yet.
    if (selected != null && !showFollowUps) {
      return const SizedBox(height: 8);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: RapidAlertColors.border)),
      ),
      child: selected == null
          ? GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.9,
              children: [
                for (final card in hazardCards)
                  _HazardButton(card: card, selected: card.key == selectedKey, onTap: () => onHazard(card)),
              ],
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(label: 'Back to hazards', emphasized: true, onTap: onBack),
                for (final followUp in selected!.followUps)
                  _Pill(label: followUp.label, onTap: () => onFollowUp(followUp)),
              ],
            ),
    );
  }
}

class _HazardButton extends StatelessWidget {
  const _HazardButton({required this.card, required this.selected, required this.onTap});

  final HazardCard card;
  final bool selected;
  final VoidCallback onTap;

  // chatbot.css .ra-chatbot-button[data-tone] background / border pairs.
  static const _tones = {
    HazardTone.blue: (Color(0xFFF8FBFF), Color(0xFFDBEAFE)),
    HazardTone.orange: (Color(0xFFFFFAF3), Color(0xFFFED7AA)),
    HazardTone.violet: (Color(0xFFFBF8FF), Color(0xFFE9D5FF)),
    HazardTone.brown: (Color(0xFFFCFBF8), Color(0xFFE7D5C0)),
    HazardTone.slate: (Colors.white, Color(0xFFE5E7EB)),
  };

  @override
  Widget build(BuildContext context) {
    final (background, border) = _tones[card.tone]!;

    return Material(
      color: selected ? const Color(0xFFFEF2F2) : background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? RapidAlertColors.primaryRed : border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Inter has its own monochrome ⚠ glyph; pointing at the system
              // emoji font keeps these in colour like the website.
              Text(
                card.icon,
                style: const TextStyle(fontSize: 18, fontFamily: 'Noto Color Emoji', fontFamilyFallback: ['Noto Color Emoji']),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  card.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? const Color(0xFF991B1B) : RapidAlertColors.darkText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.emphasized = false});

  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasized ? const Color(0xFFFFF5F5) : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: emphasized ? RapidAlertColors.primaryRed : const Color(0xFFD1D5DB)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
              color: emphasized ? RapidAlertColors.linkRed : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}
