import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'symbols.dart';

/// Symbol in einer farbigen, abgerundeten Fläche (wie in den Einstellungen von iOS).
class SportIcon extends StatelessWidget {
  const SportIcon({super.key, required this.symbol, required this.color, this.size = 32});

  final String symbol;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.85), color],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(AppSymbols.of(symbol), color: Colors.white, size: size * 0.55),
    ),
  );
}

/// Große, gut tippbare Auswahlkarte.
class SelectionCard extends StatelessWidget {
  const SelectionCard({
    super.key,
    required this.title,
    this.detail,
    required this.symbol,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String? detail;
  final String symbol;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isSelected ? scheme.primary : Colors.transparent, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  SportIcon(symbol: symbol, color: color, size: 40),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: text.titleMedium),
                        if (detail case final detail?)
                          Text(detail, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isSelected ? scheme.primary : scheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mehrfachauswahl als Chips, die umbrechen.
class FlowChips<T> extends StatelessWidget {
  const FlowChips({
    super.key,
    required this.items,
    required this.label,
    required this.isSelected,
    required this.onToggle,
  });

  final List<T> items;
  final String Function(T item) label;
  final bool Function(T item) isSelected;
  final void Function(T item) onToggle;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final item in items)
        FilterChip(
          label: Text(label(item)),
          selected: isSelected(item),
          showCheckmark: false,
          onSelected: (_) => onToggle(item),
        ),
    ],
  );
}

/// Kleine farbige Marke („Heute“, „Praxisregel“).
class AppChip extends StatelessWidget {
  const AppChip({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
    ),
  );
}

/// Gruppierter Abschnitt wie `Section` in einem `Form`: Überschrift, Inhalt in einer Karte, Fußnote.
class FormSection extends StatelessWidget {
  const FormSection({super.key, this.header, this.footer, required this.children});

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header case final header?)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(header.toUpperCase(), style: muted?.copyWith(letterSpacing: 0.4)),
            ),
          if (children.isNotEmpty)
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          if (footer case final footer?)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(footer, style: muted),
            ),
        ],
      ),
    );
  }
}

/// Zeile mit Titel und Wert (wie `LabeledContent`).
class LabeledRow extends StatelessWidget {
  const LabeledRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    trailing: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
      child: Text(
        value,
        textAlign: TextAlign.end,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

/// Zahlenfeld mit deutscher Tastatur (Komma).
class NumberField extends StatelessWidget {
  const NumberField({super.key, required this.label, required this.controller, this.decimal = true});

  final String label;
  final TextEditingController controller;
  final bool decimal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: label, border: InputBorder.none),
    ),
  );
}

/// Liest eine Zahl mit Komma oder Punkt.
double? parseNumber(String text) => double.tryParse(text.trim().replaceAll(',', '.'));
