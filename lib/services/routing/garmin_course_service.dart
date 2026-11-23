import 'dart:convert';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';

import '../garmin/garmin_connect_session.dart';

/// Sendet JSON an Garmin Connect (in der App: [GarminConnectSession.sendJson]).
typedef GarminJsonSender = Future<Uint8List> Function({
  required String method,
  required String path,
  required List<int> json,
});

/// Ergebnis von „Direkt an Garmin senden“.
sealed class GarminCourseResult {
  const GarminCourseResult(this.message);

  final String message;
}

final class GarminCourseSent extends GarminCourseResult {
  const GarminCourseSent(this.courseID)
    : super(
        'Der Kurs ist in Garmin Connect (Training › Strecken). Dort „An Gerät senden“ – auf der Uhr dann unter '
        'Navigation › Kurse.',
      );

  final int courseID;
}

/// Nicht angemeldet oder von Garmin abgelehnt – die App bietet dann das Teilen der FIT-Datei an.
final class GarminCourseFailed extends GarminCourseResult {
  const GarminCourseFailed(super.message, {this.needsLogin = false});

  final bool needsLogin;
}

/// Legt die Route als Kurs in Garmin Connect an (inoffizieller Zugang, wie die Workouts). Schickt man dieselbe Route
/// erneut, wird der alte Kurs ersetzt. Die Kurs-ID merkt sich die Route; speichern muss der Aufrufer.
abstract final class GarminCourseService {
  static Future<GarminCourseResult> send(
    PlannedRoute route, {
    required bool isLoggedIn,
    required GarminJsonSender sender,
  }) async {
    if (!isLoggedIn) {
      return const GarminCourseFailed(
        'Dafür ist die Anmeldung mit dem Garmin-Konto nötig (Einstellungen › Garmin). Alternativ den FIT-Kurs teilen.',
        needsLogin: true,
      );
    }
    try {
      if (route.garminCourseID case final old?) {
        // Alten Kurs entfernen; scheitert das (z. B. in Garmin Connect schon gelöscht), bleibt er eben stehen.
        try {
          await sender(method: 'DELETE', path: GarminCourse.coursePath(old), json: const []);
        } on Object {
          // Bleibt stehen.
        }
      }
      final body = utf8.encode(jsonEncode(GarminCourse.payload(route)));
      final response = decodeGarminJson(await sender(method: 'POST', path: GarminCourse.createPath, json: body));
      final id = GarminCourse.courseID(response.raw);
      if (id == null) return const GarminCourseFailed('Garmin hat den Kurs nicht angenommen. Teile ihn als FIT-Datei.');
      route.garminCourseID = id;
      return GarminCourseSent(id);
    } on Object catch (error) {
      final detail = switch (error) {
        GarminAPIError(:final message) || GarminConnectError(:final message) => message,
        _ => '$error',
      };
      return GarminCourseFailed('Senden hat nicht geklappt: $detail. Teile den Kurs alternativ als FIT-Datei.');
    }
  }
}

/// Zugang zum Garmin-Konto für Kurse; in Tests überschreibbar.
final class GarminCourseTarget {
  const GarminCourseTarget({required this.isLoggedIn, required this.sender});

  final bool Function() isLoggedIn;
  final GarminJsonSender sender;

  Future<GarminCourseResult> send(PlannedRoute route) =>
      GarminCourseService.send(route, isLoggedIn: isLoggedIn(), sender: sender);
}
