import 'package:coach_core/coach_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Benutzer, dem dieser Provider-Container gehört. Je Benutzer gibt es einen eigenen Container: Ein Wechsel verwirft
/// ihn samt allen Controllern, Zwischenspeichern und geöffneter Datenbank (`UserSession.switchTo`). In Tests der
/// ursprüngliche Benutzer.
final currentUserProvider = Provider<LocalUser>((ref) => UserDirectory.initial().active);
