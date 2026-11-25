import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/ai/ai_client.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';

String _errorText(Object error) => error is AIClientError ? error.message : '$error';

enum AccountAuthMode {
  login('Anmelden'),
  register('Registrieren'),
  recover('Vergessen');

  const AccountAuthMode(this.title);

  final String title;
}

/// Anmeldefenster öffnen (Einstellungen, Freunde, Einladungslink).
Future<void> presentAccountAuth(BuildContext context, AccountAuthMode mode, {AccountInvite? invite}) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AccountAuthScreen(initialMode: mode, invite: invite),
      ),
    );

/// Abschnitt „Konto“ in den Einstellungen (Port von `AccountSettingsSection`).
class AccountSettingsSection extends ConsumerWidget {
  const AccountSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountServiceProvider);
    final info = account.account;
    return FormSection(
      header: 'Konto',
      footer: account.isSignedIn
          ? null
          : 'Mit einem eigenen Konto findest du Freunde über den Benutzernamen. Nur du kennst dein Passwort; deine '
                'Gesundheitsdaten bleiben auf diesem Gerät.',
      children: [
        if (account.isSignedIn && info != null)
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(info.displayName),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('@${info.username}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const DisclosureChevron(),
              ],
            ),
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountDetailScreen())),
          )
        else ...[
          if (account.notice case final notice?)
            ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: AppColors.of(context).caution),
              title: Text(notice, style: TextStyle(color: AppColors.of(context).caution)),
            ),
          ListTile(
            title: const Text('Anmelden'),
            textColor: Theme.of(context).colorScheme.primary,
            onTap: () => presentAccountAuth(context, AccountAuthMode.login),
          ),
          ListTile(
            title: const Text('Konto erstellen'),
            textColor: Theme.of(context).colorScheme.primary,
            onTap: () => presentAccountAuth(context, AccountAuthMode.register),
          ),
        ],
      ],
    );
  }
}

/// Anmelden, Registrieren oder Passwort mit dem Wiederherstellungscode zurücksetzen (Port von `AccountAuthView`).
class AccountAuthScreen extends ConsumerStatefulWidget {
  const AccountAuthScreen({super.key, required this.initialMode, this.invite});

  final AccountAuthMode initialMode;
  final AccountInvite? invite;

  @override
  ConsumerState<AccountAuthScreen> createState() => _AccountAuthScreenState();
}

class _AccountAuthScreenState extends ConsumerState<AccountAuthScreen> {
  late AccountAuthMode _mode = widget.invite == null ? widget.initialMode : AccountAuthMode.register;
  late final _server = TextEditingController(text: widget.invite?.workerURL ?? '');
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _repeated = TextEditingController();
  late final _inviteCode = TextEditingController(text: widget.invite?.code ?? '');
  final _recovery = TextEditingController();
  bool _working = false;
  String? _error;
  String? _recoveryCode;

  @override
  void initState() {
    super.initState();
    for (final controller in [_server, _username, _displayName, _password, _repeated, _inviteCode, _recovery]) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final controller in [_server, _username, _displayName, _password, _repeated, _inviteCode, _recovery]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Server-Feld nur, wenn keiner gespeichert ist oder die Einladung einen anderen nennt.
  bool get _showsServer {
    final saved = AIClient.normalizedURL(ref.read(accountServiceProvider).workerURL);
    if (saved == null) return true;
    final host = widget.invite?.host;
    if (host == null) return false;
    return saved.host.toLowerCase() != host;
  }

  String get _serverURL => _showsServer ? _server.text : ref.read(accountServiceProvider).workerURL;

  bool get _needsInvite =>
      _mode == AccountAuthMode.register && (ref.read(accountServiceProvider).needsInviteCode || _showsServer);

  String? get _usernameHint =>
      _username.text.isEmpty || _mode == AccountAuthMode.login ? null : AccountRules.usernameProblem(_username.text);

  String? get _passwordHint {
    if (_mode == AccountAuthMode.login || _password.text.isEmpty) return null;
    if (AccountRules.passwordProblem(_password.text, username: _username.text) case final problem?) return problem;
    if (_repeated.text.isNotEmpty && _repeated.text != _password.text) return 'Die Passwörter stimmen nicht überein.';
    return null;
  }

  bool get _canSubmit {
    if (_working || AIClient.normalizedURL(_serverURL) == null || _username.text.isEmpty || _password.text.isEmpty) {
      return false;
    }
    final passwordOK =
        AccountRules.passwordProblem(_password.text, username: _username.text) == null &&
        _repeated.text == _password.text;
    return switch (_mode) {
      AccountAuthMode.login => true,
      AccountAuthMode.register =>
        AccountRules.usernameProblem(_username.text) == null &&
            passwordOK &&
            AccountRules.displayName(_displayName.text) != null &&
            (!_needsInvite || AccountRules.normalizeCode(_inviteCode.text).length == 10),
      AccountAuthMode.recover => passwordOK && AccountRules.normalizeCode(_recovery.text).length == 16,
    };
  }

  Future<void> _submit() async {
    final account = ref.read(accountServiceProvider);
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (_showsServer) await account.useServer(_server.text);
      switch (_mode) {
        case AccountAuthMode.login:
          await account.login(username: _username.text, password: _password.text);
          if (mounted) Navigator.of(context).pop();
        case AccountAuthMode.register:
          final code = await account.register(
            username: _username.text,
            displayName: _displayName.text,
            password: _password.text,
            invite: _inviteCode.text,
          );
          setState(() => _recoveryCode = code);
        case AccountAuthMode.recover:
          final code = await account.recover(
            username: _username.text,
            recoveryCode: _recovery.text,
            newPassword: _password.text,
          );
          setState(() => _recoveryCode = code);
      }
    } on Object catch (error) {
      setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_recoveryCode case final code?) {
      return RecoveryCodeScreen(code: code, onDone: () => Navigator.of(context).pop());
    }
    final title = switch (_mode) {
      AccountAuthMode.login => 'Anmelden',
      AccountAuthMode.register => 'Konto erstellen',
      AccountAuthMode.recover => 'Passwort vergessen',
    };
    final hints = [
      ?_usernameHint,
      ?_passwordHint,
      if (_mode == AccountAuthMode.register && _usernameHint == null && _passwordHint == null)
        'Freunde finden dich über den Benutzernamen. Passwort: mindestens 10 Zeichen.',
      if (_mode == AccountAuthMode.recover)
        'Den Wiederherstellungscode hast du bei der Registrierung erhalten. Ohne Code kann die Person, die den Server '
            'betreibt, dir einen neuen ausstellen.',
    ];
    Widget field(TextEditingController controller, String label, {bool secret = false, bool code = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: !secret && !code,
        textCapitalization: code ? TextCapitalization.characters : TextCapitalization.none,
        style: code ? const TextStyle(fontFamily: 'monospace') : null,
        decoration: InputDecoration(labelText: label),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BarTextButton('Abbrechen', onPressed: () => Navigator.of(context).pop()),
        leadingWidth: 100,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer: widget.invite == null
                ? null
                : 'Du wurdest eingeladen. Lege dein eigenes Konto an – nur du kennst dein Passwort.',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AccountAuthMode>(
                    segments: [
                      for (final mode in AccountAuthMode.values) ButtonSegment(value: mode, label: Text(mode.title)),
                    ],
                    selected: {_mode},
                    showSelectedIcon: false,
                    onSelectionChanged: widget.invite != null
                        ? null
                        : (selection) => setState(() {
                            _mode = selection.first;
                            _error = null;
                          }),
                  ),
                ),
              ),
            ],
          ),
          if (_showsServer)
            FormSection(
              header: 'Server',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _server,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(hintText: 'https://coach-ai.<name>.workers.dev'),
                  ),
                ),
              ],
            ),
          FormSection(
            footer: hints.isEmpty ? null : hints.join('\n'),
            children: [
              field(_username, 'Benutzername'),
              if (_mode == AccountAuthMode.register) field(_displayName, 'Anzeigename (z. B. Vorname)'),
              if (_mode == AccountAuthMode.recover) field(_recovery, 'Wiederherstellungscode', code: true),
              field(_password, _mode == AccountAuthMode.recover ? 'Neues Passwort' : 'Passwort', secret: true),
              if (_mode != AccountAuthMode.login) field(_repeated, 'Passwort wiederholen', secret: true),
              if (_needsInvite) field(_inviteCode, 'Einladungscode', code: true),
            ],
          ),
          FormSection(
            footer: _error,
            children: [
              ListTile(
                enabled: _canSubmit,
                title: Text(switch (_mode) {
                  AccountAuthMode.login => 'Anmelden',
                  AccountAuthMode.register => 'Konto erstellen',
                  AccountAuthMode.recover => 'Passwort zurücksetzen',
                }),
                textColor: Theme.of(context).colorScheme.primary,
                trailing: _working
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
                onTap: _submit,
              ),
            ],
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(error, style: TextStyle(color: AppColors.of(context).alert)),
            ),
        ],
      ),
    );
  }
}

/// Wiederherstellungscode einmalig zeigen; erst nach Bestätigung schließen (Port von `RecoveryCodeView`).
class RecoveryCodeScreen extends StatefulWidget {
  const RecoveryCodeScreen({super.key, required this.code, required this.onDone});

  final String code;
  final VoidCallback onDone;

  @override
  State<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends State<RecoveryCodeScreen> {
  bool _saved = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _saved,
    child: Scaffold(
      appBar: AppBar(title: const Text('Konto bereit'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Dein Wiederherstellungscode',
            footer:
                'Mit diesem Code setzt du dein Passwort zurück, falls du es vergisst. Er wird nur jetzt angezeigt. '
                'Bewahre ihn sicher auf, z. B. im Passwort-Manager, und gib ihn niemandem.',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Semantics(
                    label: 'Wiederherstellungscode ${widget.code.split('').join(' ')}',
                    child: SelectableText(
                      widget.code,
                      style: AppText.title(context).copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: Icon(_copied ? Icons.check : Icons.copy),
                title: Text(_copied ? 'Kopiert' : 'Kopieren'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: widget.code));
                  setState(() => _copied = true);
                },
              ),
            ],
          ),
          FormSection(
            children: [
              SwitchListTile.adaptive(
                title: const Text('Ich habe den Code sicher aufbewahrt'),
                value: _saved,
                onChanged: (on) => setState(() => _saved = on),
              ),
              ListTile(
                enabled: _saved,
                title: const Text('Fertig'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: widget.onDone,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Konto verwalten: Anzeigename, Einladungen, Geräte, Passwort, Abmelden, Löschen (Port von `AccountDetailView`).
class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({super.key});

  /// „14. Nov. 2026“ aus einer Zeit des Workers (`toISOString()`).
  static String shortDate(String iso) {
    final date = DateTime.tryParse(iso);
    return date == null ? iso : DateFormat('d. MMM y', 'de_DE').format(date.toLocal());
  }

  @override
  ConsumerState<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  late final _displayName = TextEditingController(text: ref.read(accountServiceProvider).account?.displayName ?? '')
    ..addListener(() => setState(() {}));
  String? _error;
  AccountInvite? _newInvite;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final account = ref.read(accountServiceProvider);
    try {
      await account.refresh();
      await account.loadInvites();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
    if (mounted && !account.isSignedIn) Navigator.of(context).pop();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  Future<void> _confirmLogoutEverywhere() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auf allen Geräten abmelden?'),
        content: const Text('Du musst dich danach auf jedem Gerät neu anmelden.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Überall abmelden', style: TextStyle(color: AppColors.of(context).alert)),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await _run(() => ref.read(accountServiceProvider).logout(everywhere: true));
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konto löschen?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            const Text(
              'Konto, Anmeldungen und offene Einladungen werden auf dem Server gelöscht. Deine Daten auf diesem Gerät '
              'bleiben.',
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passwort'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Endgültig löschen', style: TextStyle(color: AppColors.of(context).alert)),
          ),
        ],
      ),
    );
    final text = password.text;
    password.dispose();
    if (!(ok ?? false)) return;
    try {
      await ref.read(accountServiceProvider).deleteAccount(text);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountServiceProvider);
    final info = account.account;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final link = _newInvite?.shareURL;
    return Scaffold(
      appBar: AppBar(title: const Text('Konto')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (info != null)
            FormSection(
              header: 'Profil',
              footer: 'Freunde sehen Benutzernamen und Anzeigenamen.',
              children: [
                LabeledRow(label: 'Benutzername', value: '@${info.username}'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _displayName,
                    decoration: const InputDecoration(labelText: 'Anzeigename'),
                    onSubmitted: (name) => _run(() => account.updateDisplayName(name)),
                  ),
                ),
                if (_displayName.text != info.displayName && AccountRules.displayName(_displayName.text) != null)
                  ListTile(
                    title: const Text('Anzeigenamen speichern'),
                    textColor: Theme.of(context).colorScheme.primary,
                    onTap: () => _run(() => account.updateDisplayName(_displayName.text)),
                  ),
              ],
            ),
          if (info != null)
            FormSection(
              footer:
                  'Neue Trainings von Uhr und Gym erscheinen von selbst bei deinen Freunden im Reiter „Aktivitäten“ – '
                  'Sportart, Dauer, Strecke, Höhenmeter, Sätze. Puls, Kalorien, Gewicht und Schlaf bleiben auf deinem '
                  'Gerät. Ältere Trainings werden nicht nachträglich geteilt.',
              children: [
                SwitchListTile.adaptive(
                  title: const Text('Trainings automatisch teilen'),
                  value: ref.read(socialAutoShareProvider).isEnabled,
                  onChanged: (on) async {
                    await ref.read(socialAutoShareProvider).setEnabled(on);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          FormSection(
            header: 'Freunde und Familie einladen',
            footer: 'Jede Einladung gilt einmal und 14 Tage. Höchstens 5 offene Einladungen.',
            children: [
              ListTile(
                enabled: !_working,
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Neue Einladung erstellen'),
                onTap: () async {
                  setState(() => _working = true);
                  await _run(() async {
                    final invite = await account.createInvite();
                    if (mounted) setState(() => _newInvite = invite);
                  });
                  if (mounted) setState(() => _working = false);
                },
              ),
              if (_newInvite != null && link != null)
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: Text('Einladung ${_newInvite!.code} teilen'),
                  onTap: () => SharePlus.instance.share(
                    ShareParams(
                      text:
                          'Komm zu AIronLudi! Mit diesem Link legst du dein Konto an (14 Tage gültig, einmalig): $link',
                    ),
                  ),
                ),
              for (final invite in account.invites)
                ListTile(
                  title: Text(invite.code, style: const TextStyle(fontFamily: 'monospace')),
                  subtitle: Text('bis ${AccountDetailScreen.shortDate(invite.expiresAt)}'),
                  trailing: IconButton(
                    tooltip: 'Löschen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _run(() => account.deleteInvite(invite.code)),
                  ),
                ),
            ],
          ),
          FormSection(
            header: 'Angemeldete Geräte',
            children: [
              for (final session in account.sessions)
                ListTile(
                  title: Text('${session.device}${session.current ? ' · dieses Gerät' : ''}'),
                  subtitle: Text('Zuletzt aktiv ${AccountDetailScreen.shortDate(session.lastUsed)}'),
                ),
              ListTile(
                title: Text('Auf allen Geräten abmelden', style: TextStyle(color: AppColors.of(context).alert)),
                onTap: _confirmLogoutEverywhere,
              ),
            ],
          ),
          FormSection(
            header: 'Sicherheit',
            children: [
              ListTile(
                title: const Text('Passwort ändern'),
                trailing: const DisclosureChevron(),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen())),
              ),
              ListTile(
                title: const Text('Auf diesem Gerät abmelden'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: () async {
                  await _run(account.logout);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: Text('Konto löschen', style: TextStyle(color: AppColors.of(context).alert)),
                onTap: _delete,
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
          if (account.sessions.isEmpty && info == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Wird geladen …', style: TextStyle(color: secondary)),
            ),
        ],
      ),
    );
  }
}

/// Passwort ändern; andere Geräte werden danach abgemeldet (Port von `ChangePasswordView`).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _repeated = TextEditingController();
  String? _error;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [_old, _new, _repeated]) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final controller in [_old, _new, _repeated]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(accountServiceProvider).account?.username ?? '';
    final hint = _new.text.isEmpty
        ? null
        : AccountRules.passwordProblem(_new.text, username: username) ??
              (_repeated.text.isEmpty || _repeated.text == _new.text ? null : 'Die Passwörter stimmen nicht überein.');
    final enabled =
        !_working && _old.text.isNotEmpty && hint == null && _repeated.text == _new.text && _new.text.isNotEmpty;
    Widget field(TextEditingController controller, String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        obscureText: true,
        decoration: InputDecoration(labelText: label),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Passwort ändern')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer: hint ?? 'Andere Geräte werden danach abgemeldet.',
            children: [
              field(_old, 'Bisheriges Passwort'),
              field(_new, 'Neues Passwort'),
              field(_repeated, 'Neues Passwort wiederholen'),
            ],
          ),
          FormSection(
            footer: _error,
            children: [
              ListTile(
                enabled: enabled,
                title: const Text('Passwort ändern'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: () async {
                  setState(() => _working = true);
                  try {
                    await ref.read(accountServiceProvider).changePassword(old: _old.text, newPassword: _new.text);
                    if (context.mounted) Navigator.of(context).pop();
                  } on Object catch (error) {
                    setState(() => _error = _errorText(error));
                  } finally {
                    if (mounted) setState(() => _working = false);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Einladungslink geöffnet, obwohl schon ein Konto angemeldet ist (Port von `AlreadySignedInSheet`).
class AlreadySignedInScreen extends StatelessWidget {
  const AlreadySignedInScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
    ),
    body: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 12,
        children: [
          Icon(Icons.verified_user_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
          Text(
            'Schon angemeldet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Die Einladung ist für eine Person ohne Konto. Gib den Link an die Person weiter, für die er gedacht ist.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
