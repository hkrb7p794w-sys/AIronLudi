import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/ai/ai_client.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../evidence/evidence_views.dart';
import '../today/today_controller.dart';
import 'ai_data.dart';
import 'coach_facts.dart';

final class _Message {
  _Message({required this.fromCoach, required this.text, this.sources = const []});

  final bool fromCoach;
  final String text;
  final List<String> sources;
}

/// Chat mit dem Coach. Die App schickt nur Fakten aus ihren Regeln (im Modus „reduziert“ ohne Rohwerte); die KI
/// antwortet daraus. Antworten mit Zahlen, die nicht in den Fakten stehen, verwirft der Worker. Der Verlauf bleibt nur
/// im Speicher, solange der Chat offen ist (Port von `ChatView`).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.snapshot});

  final TodaySnapshot? snapshot;

  static const suggestions = [
    'Soll ich heute hart trainieren?',
    'Wie war mein Schlaf diese Woche?',
    'Wie viel sollte ich heute essen?',
    'Wie läuft meine Vorbereitung?',
  ];

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messages = <_Message>[];
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _draft.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _append(_Message message) {
    setState(() => _messages.add(message));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        unawaited(
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _sending) return;
    final history = [for (final message in _messages) (role: message.fromCoach ? 'coach' : 'user', text: message.text)];
    _append(_Message(fromCoach: false, text: question));
    _draft.clear();
    final ai = ref.read(aiClientProvider);
    if (!ai.isConfigured) {
      _append(
        _Message(
          fromCoach: true,
          text: 'Für den Chat brauche ich den KI-Worker – richte ihn in den Einstellungen ein.',
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final data = await loadAIData(ref);
      final facts = CoachFacts.chat(
        settings: ref.read(coachSettingsProvider),
        sync: ref.read(garminSyncServiceProvider),
        weights: data.weights,
        snapshot: widget.snapshot,
        metrics: data.metrics,
        activities: data.activities,
        meals: data.meals,
        gymDays: [for (final session in data.gym) session.day],
        gym: data.gym,
      );
      final input = ChatContext.focusedInput(facts, question: question, history: history, today: CalendarDay.today());
      final response = await ai.run('coach_chat', input: input);
      final answer = ChatContext.answer(response.output);
      _append(
        answer == null
            ? _Message(fromCoach: true, text: 'Dazu habe ich gerade keine belegte Antwort.')
            : _Message(fromCoach: true, text: answer.text, sources: answer.sources),
      );
    } on Object catch (error) {
      // Der Grund gehört in die Antwort: KI aus, offline oder überlastet sind etwas anderes als fehlende Daten.
      _append(_Message(fromCoach: true, text: error is AIClientError ? error.message : '$error'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coach fragen'),
        automaticallyImplyLeading: false,
        leading: BarTextButton('Schließen', onPressed: () => Navigator.of(context).pop()),
        leadingWidth: 100,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (_messages.isEmpty) ...[
                  Text(
                    'Frag mich zu Training, Erholung, Schlaf oder Ernährung. Ich antworte nur aus deinen Daten und den '
                    'Regeln der App.',
                    style: TextStyle(color: secondary),
                  ),
                  const SizedBox(height: 8),
                  for (final suggestion in ChatScreen.suggestions)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(onPressed: () => _send(suggestion), child: Text(suggestion)),
                    ),
                ],
                for (final message in _messages) _Bubble(message: message),
                if (_sending)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      spacing: 8,
                      children: [
                        const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        Text('Coach denkt nach …', style: TextStyle(color: secondary)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Material(
            color: theme.colorScheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _draft,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        decoration: const InputDecoration(hintText: 'Frage stellen', border: OutlineInputBorder()),
                        onSubmitted: _send,
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Senden',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: _draft.text.trim().isEmpty || _sending ? null : () => _send(_draft.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coach = message.fromCoach;
    return Align(
      alignment: coach ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: coach ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            spacing: 6,
            children: [
              GestureDetector(
                onLongPress: () => Clipboard.setData(ClipboardData(text: message.text)),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: coach
                        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.15)
                        : theme.colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(message.text),
                ),
              ),
              if (message.sources.isNotEmpty) EvidenceDisclosure(ruleIDs: message.sources, title: 'Belege'),
            ],
          ),
        ),
      ),
    );
  }
}
