import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'liquid.dart';
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
          colors: LiquidGradients.of(color).take(2).toList(),
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: size * 0.35, offset: Offset(0, size * 0.1)),
        ],
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
      child: LiquidPressable(
        child: AnimatedContainer(
          duration: LiquidMotion.of(context, LiquidMotion.medium),
          curve: LiquidMotion.settle,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LiquidRadii.card - 4),
            border: Border.all(color: isSelected ? scheme.primary : Colors.transparent, width: 2),
            boxShadow: isSelected
                ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.25), blurRadius: 18, spreadRadius: -4)]
                : const [],
          ),
          child: LiquidSurface(
            radius: LiquidRadii.card - 6,
            shadow: false,
            tint: isSelected ? scheme.primary : null,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(LiquidRadii.card - 6),
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
                        AnimatedSwitcher(
                          duration: LiquidMotion.of(context, LiquidMotion.quick),
                          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                          child: Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            key: ValueKey(isSelected),
                            color: isSelected ? scheme.primary : scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(LiquidRadii.pill),
      border: Border.all(color: color.withValues(alpha: 0.22), width: 0.5),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
    ),
  );
}

/// Gruppierter Abschnitt wie `Section` in einem `Form`: Überschrift, Inhalt auf einer Glasfläche ([LiquidSurface]) mit
/// Trennlinien zwischen den Zeilen (eingerückt bis zum Text, wie bei iOS), Fußnote.
class FormSection extends StatelessWidget {
  const FormSection({super.key, this.header, this.footer, required this.children});

  final String? header;
  final String? footer;
  final List<Widget> children;

  /// Einzug der Trennlinie: bis zum Text, bei Zeilen mit Symbol hinter das Symbol.
  static double _indent(Widget child) {
    final hasLeading = switch (child) {
      ListTile(:final leading) => leading != null,
      SwitchListTile(:final secondary) => secondary != null,
      CheckboxListTile(:final secondary) => secondary != null,
      RadioListTile(:final secondary) => secondary != null,
      _ => false,
    };
    return hasLeading ? 58 : 16;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
      height: 1.35,
    );
    final rows = [
      for (final (index, child) in children.indexed) ...[
        if (index > 0) Divider(indent: _indent(child), height: 0.5, thickness: 0.5),
        child,
      ],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 14, LiquidSpacing.page, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header case final header?)
            Padding(
              padding: const EdgeInsets.only(left: 18, right: 18, bottom: 8),
              child: Text(header.toUpperCase(), style: LiquidText.sectionHeader(context)),
            ),
          if (children.isNotEmpty)
            LiquidSurface(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
            ),
          if (footer case final footer?)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Text(footer, style: muted),
            ),
        ],
      ),
    );
  }
}

/// Grauer Pfeil am Zeilenende (`NavigationLink`).
class DisclosureChevron extends StatelessWidget {
  const DisclosureChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
    CupertinoIcons.chevron_forward,
    size: 17,
    color: Theme.of(context).brightness == Brightness.dark ? const Color(0x4DEBEBF5) : const Color(0x4D3C3C43),
  );
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
