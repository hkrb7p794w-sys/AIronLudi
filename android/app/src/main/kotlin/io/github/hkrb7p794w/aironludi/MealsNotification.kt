package io.github.hkrb7p794w.aironludi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * „Mahlzeiten heute“ als dauerhafte, lautlose Mitteilung – Gegenstück zur Live-Aktivität unter iOS (Kanal
 * `aironludi/activities`, Methode `updateMeals`). Den Inhalt rechnet Dart (`MealsLiveState`): Kopfzeile, Kalorien je
 * Mahlzeit und – mit „Erinnerung auf dem Sperrbildschirm“ – die nächste Mahlzeit statt einer Mitteilung mit Ton.
 * Während einer Gym-Einheit tritt sie zurück (`WorkoutNotification`).
 */
object MealsNotification {
    private const val CHANNEL_ID = "meals"
    private const val NOTIFICATION_ID = 4712

    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)

    fun cancel(context: Context) = manager(context).cancel(NOTIFICATION_ID)

    fun update(context: Context, state: Map<*, *>?) {
        val manager = manager(context)
        if (state == null) {
            manager.cancel(NOTIFICATION_ID)
            return
        }
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Mahlzeiten heute", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Mahlzeiten des Tages und nächste Mahlzeit auf dem Sperrbildschirm, ohne Ton"
                setShowBadge(false)
            },
        )
        val meals = (state["meals"] as? List<*>).orEmpty().mapNotNull { it as? Map<*, *> }
        val now = System.currentTimeMillis()
        val nextAt = (state["nextMealAt"] as? Number)?.toDouble()?.let { (it * 1000).toLong() }
        val nextID = state["nextMealID"] as? String
        val nextTitle = state["nextMealTitle"] as? String
        // Zur Essenszeit wie unter iOS „Zeit fürs …“, sonst die Kopfzeile des Tages.
        val due = nextAt != null && nextTitle != null && now >= nextAt
        val title = when {
            due && (nextID == "snack" || nextID == "sonstiges") -> "Zeit für einen Snack – eintragen?"
            due -> "Zeit fürs $nextTitle – jetzt eintragen?"
            else -> state["headline"] as? String ?: "Mahlzeiten heute"
        }
        val text = meals.joinToString(" · ") { meal ->
            val kcal = (meal["kcal"] as? Number)?.toInt() ?: 0
            "${meal["title"]} ${if (kcal > 0) "$kcal kcal" else "–"}"
        }
        val remaining = (state["kcalRemaining"] as? Number)?.toInt()
        val subText = listOfNotNull(
            remaining?.let { if (it >= 0) "noch $it kcal" else "${-it} kcal über Ziel" },
            if (!due) state["nextMealText"] as? String else null,
        ).joinToString(" · ")

        val open = PendingIntent.getActivity(
            context,
            10,
            Intent(Intent.ACTION_VIEW, Uri.parse("coach://open/nutrition"), context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(open)
        if (subText.isNotEmpty()) builder.setSubText(subText)
        // Ein Knopf zum Eintragen: die fällige bzw. nächste Mahlzeit, sonst allgemein.
        val target = nextID ?: meals.firstOrNull { ((it["kcal"] as? Number)?.toInt() ?: 0) == 0 }?.get("id") as? String
        val log = Uri.parse(if (target != null) "coach://open/logMeal?mahlzeit=$target" else "coach://open/logMeal")
        val logIntent = PendingIntent.getActivity(
            context,
            11,
            Intent(Intent.ACTION_VIEW, log, context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val label = if (target != null) {
            "${meals.firstOrNull { it["id"] == target }?.get("title") ?: nextTitle ?: "Mahlzeit"} eintragen"
        } else {
            "Mahlzeit eintragen"
        }
        builder.addAction(Notification.Action.Builder(null, label, logIntent).build())
        manager.notify(NOTIFICATION_ID, builder.build())
    }
}
