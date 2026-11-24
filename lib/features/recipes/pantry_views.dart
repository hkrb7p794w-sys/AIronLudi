import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../nutrition/capture_views.dart';
import 'pantry_controller.dart';
import 'recipe_views.dart';

/// „Was koche ich daraus?“ – Foto von Kühlschrank oder Vorratsschrank, die KI erkennt die Lebensmittel und schlägt
/// Gerichte vor. Fehlen für ein naheliegendes Gericht nur ein, zwei kleine Standardzutaten, fragt die App nach
/// („Ist noch Butter da?“), statt das Gericht zu verwerfen.
class PantryRecipesScreen extends ConsumerStatefulWidget {
  const PantryRecipesScreen({super.key, this.pickPhoto = pickMealPhoto});

  final Future<Uint8List?> Function(ImageSource source) pickPhoto;

  @override
  ConsumerState<PantryRecipesScreen> createState() => _PantryRecipesScreenState();
}

class _PantryRecipesScreenState extends ConsumerState<PantryRecipesScreen> {
  late final PantryController _controller = PantryController(
    ai: ref.read(aiClientProvider),
    settings: ref.read(coachSettingsProvider),
  )..addListener(_changed);
  final _addField = TextEditingController();

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    _addField.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _pick(ImageSource source) async {
    final photo = await widget.pickPhoto(source);
    if (photo == null || !mounted) return;
    _controller.setPhoto(photo);
    await _controller.suggest();
  }

  void _add() {
    _controller.addDetected(_addField.text);
    _addField.clear();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final theme = Theme.of(context);
    final secondary = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final result = controller.result;
    final questions = controller.questions;
    final recipes = [...controller.recipes]
      ..sort((a, b) => controller.status(a).index.compareTo(controller.status(b).index));
    return Scaffold(
      appBar: AppBar(title: const Text('Aus dem Kühlschrank')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              FormSection(
                footer:
                    'Foto von Kühlschrank, Vorratsschrank oder Arbeitsplatte. Ernährungsweise, Allergene und dein Vorrat '
                    'aus der Einkaufsliste werden berücksichtigt; das Foto geht ohne Metadaten an deinen KI-Worker.',
                children: [
                  if (controller.photo case final photo?)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(photo, height: 180, fit: BoxFit.cover),
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.photo_camera),
                    title: Text(controller.photo == null ? 'Foto aufnehmen' : 'Neues Foto'),
                    enabled: controller.canAsk && !controller.isWorking,
                    onTap: () => unawaited(_pick(ImageSource.camera)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_outlined),
                    title: const Text('Aus der Mediathek'),
                    enabled: controller.canAsk && !controller.isWorking,
                    onTap: () => unawaited(_pick(ImageSource.gallery)),
                  ),
                  if (!controller.canAsk)
                    ListTile(
                      title: Text(
                        'Dafür muss der KI-Worker eingerichtet und die KI für Pläne und Rezepte erlaubt sein '
                        '(Einstellungen › KI).',
                        style: secondary,
                      ),
                    ),
                ],
              ),
              if (controller.errorMessage case final message?)
                FormSection(
                  children: [
                    ListTile(
                      leading: Icon(Icons.error_outline, color: AppColors.of(context).caution),
                      title: Text(message),
                    ),
                  ],
                ),
              if (questions.isNotEmpty)
                FormSection(
                  header: 'Kurze Rückfrage',
                  footer: 'Nur kleine Standardzutaten – mit „Ja“ ist das Gericht komplett.',
                  children: [
                    for (final ingredient in questions)
                      ListTile(
                        title: Text(PantryRecipes.question(ingredient)),
                        subtitle: Text(
                          'Für ${PantryRecipes.neededFor(ingredient, controller.recipes).join(', ')}',
                          style: secondary,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => controller.answer(ingredient, available: false),
                              child: const Text('Nein'),
                            ),
                            FilledButton.tonal(
                              onPressed: () => controller.answer(ingredient, available: true),
                              child: const Text('Ja'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              if (recipes.isNotEmpty)
                FormSection(
                  header: 'Vorschläge',
                  children: [
                    for (final recipe in recipes) _RecipeTile(recipe: recipe, status: controller.status(recipe)),
                  ],
                ),
              if (result != null)
                FormSection(
                  header: 'Erkannt',
                  footer: 'Falsches entfernen, Fehlendes ergänzen – dann neu vorschlagen lassen.',
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final item in controller.detected)
                            InputChip(label: Text(item), onDeleted: () => controller.removeDetected(item)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _addField,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Lebensmittel ergänzen',
                          suffixIcon: IconButton(tooltip: 'Ergänzen', icon: const Icon(Icons.add), onPressed: _add),
                        ),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.refresh),
                      title: Text(
                        controller.allBlocked ? 'Mit deinen Antworten neu vorschlagen' : 'Neu vorschlagen',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: controller.allBlocked ? FontWeight.w600 : null,
                        ),
                      ),
                      enabled: !controller.isWorking,
                      onTap: () => unawaited(controller.suggest()),
                    ),
                  ],
                ),
              if (result != null && result.notes.isNotEmpty)
                FormSection(
                  header: 'Von den Regeln aussortiert',
                  children: [
                    for (final note in result.notes)
                      ListTile(dense: true, leading: const Icon(Icons.verified_user_outlined), title: Text(note)),
                  ],
                ),
            ],
          ),
          if (controller.isWorking)
            const ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _RecipeTile extends StatelessWidget {
  const _RecipeTile({required this.recipe, required this.status});

  final PantryRecipe recipe;
  final PantryRecipeStatus status;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final kcal = PantryRecipes.kilocalories(recipe).round();
    final base = '${recipe.recipe.minutes} min · $kcal kcal';
    final (icon, color, detail) = switch (status) {
      PantryRecipeStatus.ready => (Icons.check_circle, AppColors.of(context).good, base),
      PantryRecipeStatus.waiting => (
        Icons.help_outline,
        AppColors.of(context).caution,
        '$base · braucht ${recipe.missing.join(', ')}',
      ),
      PantryRecipeStatus.blocked => (Icons.block, secondary, 'Fehlt: ${recipe.missing.join(', ')}'),
    };
    final blocked = status == PantryRecipeStatus.blocked;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        recipe.recipe.title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: blocked ? secondary : null,
          decoration: blocked ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(detail),
      trailing: const DisclosureChevron(),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => RecipeDetailScreen(recipe: recipe.recipe))),
    );
  }
}
