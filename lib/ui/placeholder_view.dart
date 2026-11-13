import 'package:flutter/material.dart';

/// Hinweis für Bereiche, die noch übertragen werden (nur während der Migration).
class PlaceholderView extends StatelessWidget {
  const PlaceholderView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Dieser Bereich wird gerade aus der iPhone-App übertragen.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
