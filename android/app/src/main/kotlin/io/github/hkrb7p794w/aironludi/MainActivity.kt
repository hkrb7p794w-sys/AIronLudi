package io.github.hkrb7p794w.aironludi

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity statt FlutterActivity: Health Connect fragt Berechtigungen über die
// Activity-Result-API an (Voraussetzung des Pakets `health`).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Laufende Gym-Einheit als dauerhafte Mitteilung (Gegenstück zur Live-Aktivität).
        val activities = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aironludi/activities")
        activities.setMethodCallHandler { call, result ->
            try {
                result.success(WorkoutNotification.handle(applicationContext, call.method, call.arguments as? Map<*, *>))
            } catch (error: IllegalArgumentException) {
                result.notImplemented()
            }
        }
        WorkoutNotification.channel = activities
        // Wecker zur Aufstehzeit (AlarmManager.setAlarmClock).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aironludi/alarm").setMethodCallHandler { call, result ->
            try {
                result.success(WakeAlarm.handle(applicationContext, call.method, call.arguments as? Map<*, *>))
            } catch (error: IllegalArgumentException) {
                result.notImplemented()
            }
        }
        // Homescreen-Widgets neu zeichnen, sobald die App einen neuen Stand geschrieben hat.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aironludi/widgets").setMethodCallHandler { call, result ->
            when (call.method) {
                "reload" -> {
                    WidgetData.updateAll(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        WorkoutNotification.channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
