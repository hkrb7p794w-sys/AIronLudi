import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/user_providers.dart';
import '../../app/user_session.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';

/// Benutzer dieses Geräts: wechseln, anlegen, umbenennen, löschen. Jeder Benutzer hat einen vollständig getrennten
/// Speicher (Trainings, Mahlzeiten, Rezepte, KI-Empfehlungen, Einstellungen, Zugänge zu Garmin, WHOOP und Konto).
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    final current = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Benutzer')),
      body: session == null
          ? ListView(
              children: [
                FormSection(
                  children: [LabeledRow(label: 'Angemeldet', value: current.title)],
                ),
              ],
            )
          : ListenableBuilder(
              listenable: session,
              builder: (context, _) => _UserList(session: session),
            ),
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({required this.session});

  final UserSession session;

  Future<void> _switch(BuildContext context, LocalUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Zu „${user.title}“ wechseln?'),
        content: const Text(
          'Die App schließt alle Daten des aktuellen Benutzers und öffnet die von '
          'diesem Benutzer. Laufende Live-Aktivitäten und geplante Mitteilungen enden.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Wechseln')),
        ],
      ),
    );
    // Nach dem Wechsel gehört dieser Bildschirm zum alten Benutzer und verschwindet – danach nichts mehr anfassen.
    if (ok == true) await session.switchTo(user.id);
  }

  Future<void> _add(BuildContext context) async {
    final result = await showDialog<({String username, String displayName})>(
      context: context,
      builder: (_) => _AddUserDialog(directory: session.directory),
    );
    if (result == null || !context.mounted) return;
    try {
      await session.add(username: result.username, displayName: result.displayName);
    } on UserDirectoryError catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _rename(BuildContext context, LocalUser user) async {
    final controller = TextEditingController(text: user.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anzeigename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(hintText: user.username),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Sichern')),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    try {
      await session.rename(user.id, name);
    } on UserDirectoryError catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _remove(BuildContext context, LocalUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('„${user.title}“ löschen?'),
        content: const Text(
          'Alle Daten dieses Benutzers auf diesem Gerät werden endgültig gelöscht: Trainings, Mahlzeiten, Rezepte, '
          'KI-Empfehlungen, Einstellungen und gespeicherte Zugänge. Eine Sicherung vorher geht über „Datensicherung“, '
          'solange dieser Benutzer aktiv ist.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.of(context).alert),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await session.remove(user.id);
    } on Object catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = session.user;
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        FormSection(
          header: 'Auf diesem Gerät',
          footer:
              'Jeder Benutzer hat einen eigenen, vollständig getrennten Speicher: eigene Datenbank, eigene Dateien und '
              'eigene Zugänge (Garmin, WHOOP, KI-Worker, Konto). Beim Wechsel wird alles des bisherigen Benutzers '
              'geschlossen und aus dem Arbeitsspeicher entfernt. Die Homescreen-Widgets zeigen immer den aktiven '
              'Benutzer.',
          children: [
            for (final user in session.users)
              ListTile(
                leading: CircleAvatar(child: Text(user.title.characters.first.toUpperCase())),
                title: Text(user.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('@${user.username}${user.id == active.id ? ' · aktiv' : ''}', style: secondary),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (user.id == active.id) Icon(Icons.check, color: AppColors.of(context).good),
                    PopupMenuButton<String>(
                      tooltip: 'Mehr',
                      onSelected: (action) => unawaited(switch (action) {
                        'rename' => _rename(context, user),
                        'remove' => _remove(context, user),
                        _ => _switch(context, user),
                      }),
                      itemBuilder: (_) => [
                        if (user.id != active.id) const PopupMenuItem(value: 'switch', child: Text('Wechseln')),
                        const PopupMenuItem(value: 'rename', child: Text('Anzeigename ändern')),
                        if (user.id != active.id && !user.isLegacy)
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Löschen', style: TextStyle(color: AppColors.of(context).alert)),
                          ),
                      ],
                    ),
                  ],
                ),
                onTap: user.id == active.id || session.isSwitching ? null : () => unawaited(_switch(context, user)),
              ),
          ],
        ),
        FormSection(
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Benutzer hinzufügen'),
              enabled: session.users.length < UserDirectory.maxUsers && !session.isSwitching,
              onTap: () => unawaited(_add(context)),
            ),
          ],
        ),
      ],
    );
  }
}

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog({required this.directory});

  final UserDirectory directory;

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    super.dispose();
  }

  void _check() => setState(
    () => _problem = _username.text.trim().isEmpty ? null : widget.directory.usernameProblem(_username.text),
  );

  @override
  Widget build(BuildContext context) {
    final valid = _username.text.trim().isNotEmpty && _problem == null;
    return AlertDialog(
      title: const Text('Neuer Benutzer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('username'),
            controller: _username,
            autofocus: true,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'Benutzername', errorText: _problem, errorMaxLines: 3),
            onChanged: (_) => _check(),
          ),
          TextField(
            key: const ValueKey('displayName'),
            controller: _displayName,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Anzeigename (optional)'),
          ),
          Text('Der neue Benutzer startet mit leerem Speicher und der Einrichtung.', style: AppText.caption(context)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop((username: _username.text, displayName: _displayName.text))
              : null,
          child: const Text('Anlegen und wechseln'),
        ),
      ],
    );
  }
}
