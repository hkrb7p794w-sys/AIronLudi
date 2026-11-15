package io.github.hkrb7p794w.aironludi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Laufende Gym-Einheit als dauerhafte Mitteilung – Gegenstück zur Live-Aktivität unter iOS (Kanal
 * `aironludi/activities`). Den Inhalt rechnet Dart (`WorkoutLiveState`); die Knöpfe gehen als `workoutAction` an Dart
 * zurück. Läuft die App gerade nicht, merkt sich der Empfänger den Knopf, und Dart holt ihn beim Öffnen ab.
 */
object WorkoutNotification {
    private const val CHANNEL_ID = "workout"
    private const val NOTIFICATION_ID = 4711
    private const val PREFERENCES = "aironludi.activities"
    private const val PENDING_KEY = "pendingWorkoutActions"
    const val ACTION = "io.github.hkrb7p794w.aironludi.WORKOUT_ACTION"

    /** Kanal zur laufenden Flutter-Engine; `null`, solange keine läuft. */
    var channel: MethodChannel? = null

    fun handle(context: Context, method: String, arguments: Map<*, *>?): Any? = when (method) {
        "updateWorkout" -> {
            update(context, arguments?.get("state") as? Map<*, *>)
            null
        }
        "updateMeals" -> {
            MealsNotification.update(context, arguments?.get("state") as? Map<*, *>)
            null
        }
        "takePendingActions" -> takePending(context)
        else -> throw IllegalArgumentException(method)
    }

    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)

    private fun update(context: Context, state: Map<*, *>?) {
        val manager = manager(context)
        if (state == null) {
            manager.cancel(NOTIFICATION_ID)
            return
        }
        // Vorrang der Einheit: „Mahlzeiten heute“ tritt zurück (Dart startet sie nach der Einheit neu).
        MealsNotification.cancel(context)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Laufende Einheit", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Pause und nächster Satz während einer Gym-Einheit"
                setShowBadge(false)
            },
        )
        val exercise = state["exercise"] as? String ?: ""
        val detail = state["detail"] as? String ?: ""
        val allDone = state["allDone"] as? Boolean ?: false
        val weight = state["weight"] as? String
        val reps = state["reps"] as? String
        val next = state["next"] as? String
        val restEndsAt = (state["restEndsAt"] as? Number)?.toDouble()?.let { (it * 1000).toLong() }
        // Ansicht aus den Einstellungen: nur Pause, nur Übung und Satz oder beides (Standard).
        val layout = state["layout"] as? String ?: "combined"
        val showsTimer = layout != "exercise"
        val showsExercise = layout != "timer"
        val resting = showsTimer && restEndsAt != null && restEndsAt > System.currentTimeMillis()
        val values = listOfNotNull(weight, reps).joinToString(" × ")
        val text = if (showsExercise) {
            listOf(detail, values).filter { it.isNotEmpty() }.joinToString(" · ")
        } else if (resting) {
            "Gleich: $exercise"
        } else {
            detail
        }

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(Intent.ACTION_VIEW, Uri.parse("coach://open/gym"), context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(if (resting) (if (showsExercise) "Pause · $exercise" else "Pause") else exercise)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(resting)
            .setCategory(Notification.CATEGORY_WORKOUT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(open)
        if (next != null && showsExercise) builder.setSubText(next)
        if (resting) {
            builder.setWhen(restEndsAt!!).setUsesChronometer(true).setChronometerCountDown(true)
        }
        // Android zeigt höchstens drei Knöpfe: Satz erledigt, Pause überspringen bzw. Gewicht ±.
        if (!allDone) builder.addAction(action(context, "completeSet", 0, "Satz erledigt"))
        if (resting) {
            builder.addAction(action(context, "skipRest", 0, "Pause überspringen"))
        } else if (!allDone && weight != null && showsExercise) {
            val step = state["weightStep"] as? String ?: ""
            builder.addAction(action(context, "weight", -1, "− $step kg"))
            builder.addAction(action(context, "weight", 1, "+ $step kg"))
        }
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    private fun action(context: Context, name: String, steps: Int, title: String): Notification.Action {
        val intent = Intent(context, WorkoutActionReceiver::class.java)
            .setAction(ACTION)
            .putExtra("action", name)
            .putExtra("steps", steps)
        val code = (name + steps).hashCode()
        val pending = PendingIntent.getBroadcast(
            context,
            code,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(null, title, pending).build()
    }

    /** Knopf an Dart; ohne laufende Engine für später merken. */
    fun deliver(context: Context, name: String, steps: Int) {
        val arguments = mapOf("action" to name, "steps" to steps)
        val current = channel
        if (current != null) {
            Handler(Looper.getMainLooper()).post { current.invokeMethod("workoutAction", arguments) }
            return
        }
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val pending = JSONArray(preferences.getString(PENDING_KEY, "[]"))
        pending.put(JSONObject(arguments))
        preferences.edit().putString(PENDING_KEY, pending.toString()).apply()
    }

    private fun takePending(context: Context): List<Map<String, Any>> {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val pending = JSONArray(preferences.getString(PENDING_KEY, "[]"))
        preferences.edit().remove(PENDING_KEY).apply()
        return (0 until pending.length()).map { index ->
            val item = pending.getJSONObject(index)
            mapOf("action" to item.optString("action"), "steps" to item.optInt("steps"))
        }
    }
}

/** Knöpfe der laufenden Mitteilung. */
class WorkoutActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WorkoutNotification.ACTION) return
        val name = intent.getStringExtra("action") ?: return
        WorkoutNotification.deliver(context, name, intent.getIntExtra("steps", 0))
    }
}
