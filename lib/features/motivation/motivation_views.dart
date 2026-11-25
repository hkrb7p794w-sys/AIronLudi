import 'dart:async';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/ai/ai_client.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/symbols.dart';
import '../../ui/tokens.dart';
import '../evidence/evidence_views.dart';
import 'daisy_avatar.dart';

IconData companionIcon(CompanionKind kind) => switch (kind) {
  CompanionKind.dog || CompanionKind.daisy => Icons.pets,
  CompanionKind.cat => Icons.cruelty_free,
  CompanionKind.coach => Icons.sports,
};

IconData moodIcon(CompanionMood mood) => switch (mood) {
  CompanionMood.happy => Icons.favorite,
  CompanionMood.proud => Icons.star,
  CompanionMood.excited => Icons.auto_awesome,
  CompanionMood.resting => Icons.bedtime,
  CompanionMood.cozy => Icons.coffee,
  CompanionMood.hopeful => Icons.wb_sunny,
};

/// Avatar des Begleiters: Foto, gezeichnete Daisy oder Symbol (Port von `CompanionAvatar`).
class CompanionAvatar extends StatelessWidget {
  const CompanionAvatar({
    super.key,
    required this.companion,
    this.photo,
    this.mood = CompanionMood.proud,
    this.size = 64,
  });

  final CompanionSettings companion;
  final Uint8List? photo;
  final CompanionMood mood;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: switch ((photo, companion.kind)) {
            (final bytes?, _) => Image.memory(bytes, fit: BoxFit.cover),
            (null, CompanionKind.daisy) => DaisyAvatar(mood: mood, size: size),
            _ => ColoredBox(
              color: AppColors.of(context).caution,
              child: Icon(companionIcon(companion.kind), color: AppPalette.onColor, size: size * 0.45),
            ),
          },
        ),
      ),
    );
  }
}

/// Begleiter unter „Heute“: Avatar mit Stimmung und freundlicher Nachricht (Port von `CompanionSection`).
class CompanionSection extends ConsumerStatefulWidget {
  const CompanionSection({super.key, required this.companion, required this.message});

  final CompanionSettings companion;
  final CompanionMessage message;

  @override
  ConsumerState<CompanionSection> createState() => _CompanionSectionState();
}

class _CompanionSectionState extends ConsumerState<CompanionSection> {
  Uint8List? _photo;

  @override
  void initState() {
    super.initState();
    ref.read(companionPhotoProvider).load().then((photo) {
      if (mounted) setState(() => _photo = photo);
    });
  }

  @override
  Widget build(BuildContext context) {
    final companion = widget.companion;
    final message = widget.message;
    return FormSection(
      children: [
        Semantics(
          container: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 14,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CompanionAvatar(
                      companion: companion,
                      photo: companion.kind == CompanionKind.daisy ? null : _photo,
                      mood: message.mood,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: ExcludeSemantics(
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: AppPalette.pink,
                          child: Icon(moodIcon(message.mood), size: 13, color: AppPalette.onColor),
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(companion.displayName, style: AppText.headline(context)),
                      Text(message.text),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Rangliste der Liga (Port von `LeagueSection`).
class LeagueSection extends ConsumerStatefulWidget {
  const LeagueSection({super.key, required this.summary});

  final MotivationSummary summary;

  @override
  ConsumerState<LeagueSection> createState() => _LeagueSectionState();
}

class _LeagueSectionState extends ConsumerState<LeagueSection> {
  String? _synced;

  @override
  Widget build(BuildContext context) {
    final league = ref.watch(leagueServiceProvider);
    final settings = ref.watch(coachSettingsProvider);
    final summary = widget.summary;
    final key = '${summary.weekPoints}-${summary.totalPoints}-${settings.league.code}';
    if (_synced != key) {
      _synced = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(league.sync(summary));
      });
    }
    final me = settings.league.memberID;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Rangliste diese Woche',
      footer:
          'Punkte gibt es für Einheiten aus deinem Plan (${ScoreRules.pointsPerSession} je Einheit, '
          '+${ScoreRules.completeWeekBonus} für die ganze Woche). Mehr Training zählt nicht extra – Ruhetage gehören '
          'dazu. Stufe ${summary.level}.',
      children: [
        if (league.members.isEmpty)
          ListTile(
            title: Text('Deine Woche: ${summary.weekPoints} Punkte'),
            trailing: league.isLoading
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
          ),
        for (final (index, member) in league.members.indexed)
          Semantics(
            container: true,
            child: ListTile(
              leading: SizedBox(
                width: 64,
                child: Row(
                  spacing: 8,
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        index == 0 && member.weekPoints > 0 ? '🏆' : '${index + 1}.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(AppSymbols.of(member.avatar), size: 20, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
              title: Text(
                member.id == me ? '${member.name} (du)' : member.name,
                style: TextStyle(fontWeight: member.id == me ? FontWeight.bold : null),
              ),
              subtitle: Text('${member.done} von ${member.planned} Einheiten · Serie ${member.streak} Wo.'),
              trailing: Text(
                '${member.weekPoints}',
                style: AppText.body(context).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        if (league.lastError case final error?)
          ListTile(
            title: Text(error, style: AppText.footnote(context).copyWith(color: AppColors.of(context).caution)),
          ),
        if (league.members.isEmpty && !league.isLoading && league.lastError == null)
          ListTile(
            dense: true,
            title: Text('Noch keine anderen Einträge.', style: TextStyle(color: secondary)),
          ),
        const EvidenceDisclosure(ruleIDs: ['motivation.gamification']),
      ],
    );
  }
}

/// Einstellungen für Begleiter und Rangliste (Port von `MotivationSettingsView`).
class MotivationSettingsScreen extends ConsumerStatefulWidget {
  const MotivationSettingsScreen({super.key});

  @override
  ConsumerState<MotivationSettingsScreen> createState() => _MotivationSettingsScreenState();
}

class _MotivationSettingsScreenState extends ConsumerState<MotivationSettingsScreen> {
  Uint8List? _photo;
  final _joinCode = TextEditingController();
  late final _companionName = TextEditingController(text: ref.read(coachSettingsProvider).companion.name);
  late final _leagueName = TextEditingController(text: ref.read(coachSettingsProvider).league.name);
  Uri? _invite;
  String? _inviteError;
  bool _creatingInvite = false;
  String? _code;

  @override
  void initState() {
    super.initState();
    _joinCode.addListener(() => setState(() {}));
    unawaited(_loadPhoto());
  }

  @override
  void dispose() {
    _joinCode.dispose();
    _companionName.dispose();
    _leagueName.dispose();
    super.dispose();
  }

  Future<void> _loadPhoto() async {
    final photo = await ref.read(companionPhotoProvider).load();
    if (mounted) setState(() => _photo = photo);
  }

  void _companion(void Function(CompanionSettings companion) change) {
    final settings = ref.read(coachSettingsProvider);
    final companion = settings.companion;
    change(companion);
    settings.companion = companion;
  }

  void _league(void Function(LeagueSettings league) change) {
    final settings = ref.read(coachSettingsProvider);
    final league = settings.league;
    change(league);
    settings.league = league;
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (file == null) return;
    await ref.read(companionPhotoProvider).save(await file.readAsBytes());
    await _loadPhoto();
  }

  Future<void> _createInvite() async {
    setState(() => _creatingInvite = true);
    try {
      final invite = await ref.read(leagueServiceProvider).makeInvite();
      setState(() {
        _invite = invite;
        _inviteError = null;
      });
    } on Object catch (error) {
      setState(() => _inviteError = 'Einladung nicht erstellt: ${error is AIClientError ? error.message : error}');
    } finally {
      if (mounted) setState(() => _creatingInvite = false);
    }
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rangliste verlassen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Verlassen', style: TextStyle(color: AppColors.of(context).alert)),
          ),
        ],
      ),
    );
    if (ok ?? false) await ref.read(leagueServiceProvider).leave();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final league = ref.watch(leagueServiceProvider);
    final companion = settings.companion;
    final isDaisy = companion.kind == CompanionKind.daisy;
    // Neuer Code: Einladungslink gehört zur alten Rangliste.
    if (_code != settings.league.code) {
      _code = settings.league.code;
      _invite = null;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Begleiter & Rangliste')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Begleiter',
            footer:
                '„Daisy (animiert)“ bewegt sich je nach Stimmung: Geschirr zum Losgehen, Zunge raus nach dem Training, '
                '„Zzz“ am Ruhetag, Halstuch, wenn die Woche geschafft ist. Der Begleiter kommentiert deinen Tag '
                'freundlich und erinnert dich an Einheiten. Er richtet sich nach denselben Regeln wie die Empfehlung: '
                'Bei schlechter Erholung lobt er das Ausruhen. Das Foto bleibt auf diesem Gerät.',
            children: [
              SwitchListTile.adaptive(
                title: const Text('Begleiter anzeigen'),
                value: companion.enabled,
                onChanged: (on) => _companion((companion) => companion.enabled = on),
              ),
              if (companion.enabled) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    spacing: 14,
                    children: [
                      CompanionAvatar(companion: companion, photo: isDaisy ? null : _photo, size: 56),
                      Expanded(
                        child: TextField(
                          controller: _companionName,
                          decoration: const InputDecoration(labelText: 'Name, z. B. Daisy'),
                          onChanged: (name) => _companion((companion) => companion.name = name),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<CompanionKind>(
                    initialValue: companion.kind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Art'),
                    items: [
                      for (final kind in CompanionKind.values)
                        DropdownMenuItem(
                          value: kind,
                          child: Row(spacing: 8, children: [Icon(companionIcon(kind), size: 18), Text(kind.label)]),
                        ),
                    ],
                    onChanged: (kind) => _companion((companion) => companion.kind = kind ?? companion.kind),
                  ),
                ),
                if (isDaisy)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 10,
                      children: [
                        for (final mood in const [
                          CompanionMood.excited,
                          CompanionMood.happy,
                          CompanionMood.resting,
                          CompanionMood.proud,
                        ])
                          CompanionAvatar(companion: companion, mood: mood, size: 52),
                      ],
                    ),
                  )
                else ...[
                  ListTile(
                    leading: const Icon(Icons.photo_outlined),
                    title: Text(_photo == null ? 'Foto auswählen' : 'Anderes Foto'),
                    onTap: _pickPhoto,
                  ),
                  if (_photo != null)
                    ListTile(
                      title: Text('Foto entfernen', style: TextStyle(color: AppColors.of(context).alert)),
                      onTap: () async {
                        await ref.read(companionPhotoProvider).remove();
                        setState(() => _photo = null);
                      },
                    ),
                ],
              ],
            ],
          ),
          FormSection(
            header: 'Rangliste',
            footer: !league.canUse
                ? 'Für die Rangliste muss der KI-Worker eingerichtet sein (Einstellungen › KI-Worker).'
                : league.canInvite
                ? 'Geteilt werden nur Name, Symbol und Punkte – keine Gesundheitsdaten. Jeder Einladungslink enthält '
                      'einen eigenen Gastzugang zu deinem Worker (KI, Rangliste, geteilte Mahlzeiten), nicht dein '
                      'App-Token. Erstelle für jede Person einen eigenen Link. Jede Person richtet in ihrer App eigenes '
                      'Profil und eigene Datenquellen ein.'
                : 'Geteilt werden nur Name, Symbol und Punkte – keine Gesundheitsdaten. Gib zum Einladen den Code '
                      'weiter; Einladungslinks erstellt, wer den Worker betreibt.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _leagueName,
                  decoration: const InputDecoration(labelText: 'Dein Name in der Rangliste'),
                  onChanged: (name) => _league((league) => league.name = name),
                ),
              ),
              if (settings.league.isJoined) ...[
                LabeledRow(label: 'Code', value: settings.league.code),
                if (_invite case final invite?)
                  ListTile(
                    leading: const Icon(Icons.ios_share),
                    title: const Text('Einladungslink teilen'),
                    onTap: () => SharePlus.instance.share(
                      ShareParams(
                        subject: 'AIronLudi-Rangliste',
                        text: 'Mach mit in meiner AIronLudi-Rangliste! $invite',
                      ),
                    ),
                  )
                else if (league.canInvite)
                  ListTile(
                    enabled: !_creatingInvite,
                    leading: const Icon(Icons.add_link),
                    title: const Text('Einladungslink erstellen'),
                    onTap: _createInvite,
                  ),
                if (_inviteError case final error?)
                  ListTile(
                    title: Text(error, style: AppText.footnote(context).copyWith(color: AppColors.of(context).alert)),
                  ),
                ListTile(
                  title: Text('Rangliste verlassen', style: TextStyle(color: AppColors.of(context).alert)),
                  onTap: _confirmLeave,
                ),
              ] else ...[
                ListTile(
                  enabled: league.canUse,
                  title: const Text('Neue Rangliste erstellen'),
                  textColor: Theme.of(context).colorScheme.primary,
                  onTap: league.create,
                ),
                ListTile(
                  title: TextField(
                    controller: _joinCode,
                    autocorrect: false,
                    decoration: const InputDecoration(hintText: 'Code eingeben'),
                  ),
                  trailing: TextButton(
                    onPressed: LeagueCode.isValid(_joinCode.text.toLowerCase()) && league.canUse
                        ? () => league.join(_joinCode.text)
                        : null,
                    child: const Text('Beitreten'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Aus einem Einladungslink geöffnet (Port von `JoinLeagueSheet`).
class JoinLeagueScreen extends ConsumerStatefulWidget {
  const JoinLeagueScreen({super.key, required this.invite});

  final LeagueInvite invite;

  @override
  ConsumerState<JoinLeagueScreen> createState() => _JoinLeagueScreenState();
}

class _JoinLeagueScreenState extends ConsumerState<JoinLeagueScreen> {
  late final _name = TextEditingController(text: ref.read(coachSettingsProvider).league.name)
    ..addListener(() => setState(() {}));
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final settings = ref.read(coachSettingsProvider);
    settings.league = settings.league..name = _name.text;
    try {
      await ref.read(leagueServiceProvider).accept(widget.invite);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      setState(() => _error = error is AIClientError ? error.message : '$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Rangliste beitreten'),
      leading: BarTextButton('Abbrechen', onPressed: () => Navigator.of(context).pop()),
      leadingWidth: 100,
      actions: [TextButton(onPressed: _name.text.trim().isEmpty ? null : _join, child: const Text('Beitreten'))],
    ),
    body: ListView(
      children: [
        FormSection(
          footer:
              'Tritt nur bei, wenn du die Person kennst und der Server stimmt. Die App nutzt den KI-Worker aus der '
              'Einladung. Dein Profil, deine Zugänge und alle Daten bleiben auf deinem Gerät; geteilt werden nur Name '
              'und Punkte.',
          children: [
            const ListTile(title: Text('Du wurdest in eine AIronLudi-Rangliste eingeladen.')),
            LabeledRow(label: 'Server', value: widget.invite.host ?? widget.invite.workerURL),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Dein Name in der Rangliste'),
              ),
            ),
          ],
        ),
        if (_error case final error?)
          FormSection(
            children: [
              ListTile(
                title: Text(error, style: TextStyle(color: AppColors.of(context).alert)),
              ),
            ],
          ),
      ],
    ),
  );
}
