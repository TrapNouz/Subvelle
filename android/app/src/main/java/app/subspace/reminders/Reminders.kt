package app.subspace.reminders

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.subspace.R
import app.subspace.core.Money
import app.subspace.core.RecurrenceEngine
import app.subspace.core.SubscriptionRecord
import app.subspace.data.Settings
import app.subspace.data.SubscriptionStore
import app.subspace.ui.MainActivity
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.concurrent.TimeUnit

/**
 * Renewal reminders. Instead of a long queue of exact alarms (which Android restricts), one daily job
 * runs around 9 AM and posts a notification for each payment whose reminder falls on that day.
 * WorkManager keeps it scheduled across reboots and app updates.
 */
object Reminders {
    const val CHANNEL_ID = "renewal_reminders"
    private const val WORK_NAME = "daily_renewal_reminders"

    /** Payments due for a reminder on [today]: their date minus the reminder offset. */
    fun dueToday(records: List<SubscriptionRecord>, today: LocalDate): List<Pair<SubscriptionRecord, LocalDate>> {
        val engine = RecurrenceEngine()
        return records.mapNotNull { record ->
            val days = record.reminderDays ?: return@mapNotNull null
            val target = today.plusDays(days.toLong())
            engine.payments(record, target, target.plusDays(1)).firstOrNull()?.let { record to it.date }
        }
    }

    fun createChannel(context: Context) {
        val channel = NotificationChannel(CHANNEL_ID, context.getString(R.string.reminder_channel), NotificationManager.IMPORTANCE_DEFAULT)
            .apply { description = context.getString(R.string.reminder_channel_description) }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun canNotify(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** (Re)schedules the next run for 9 AM local time, or cancels when reminders are off. */
    fun schedule(context: Context, enabled: Boolean, now: LocalDateTime = LocalDateTime.now()) {
        val manager = WorkManager.getInstance(context)
        if (!enabled) { manager.cancelUniqueWork(WORK_NAME); return }
        val nineToday = now.toLocalDate().atTime(LocalTime.of(9, 0))
        val next = if (now.isBefore(nineToday)) nineToday else nineToday.plusDays(1)
        val request = OneTimeWorkRequestBuilder<ReminderWorker>()
            .setInitialDelay(Duration.between(now, next).toMillis(), TimeUnit.MILLISECONDS)
            .build()
        manager.enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
    }

    /** Posts today's reminders once per day. Returns how many were posted. */
    fun postDue(context: Context, today: LocalDate = LocalDate.now()): Int {
        val settings = Settings(context)
        if (!settings.remindersEnabled || settings.lastReminderDay == today.toString() || !canNotify(context)) return 0
        val records = runCatching { SubscriptionStore(context).load() }.getOrNull() ?: return 0
        val due = dueToday(records, today)
        val manager = NotificationManagerCompat.from(context)
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val formatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
        for ((record, date) in due) {
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_launcher_foreground)
                .setContentTitle("${record.name} renews soon")
                .setContentText("${Money.format(record.amount, record.currency)} on ${date.format(formatter)}.")
                .setContentIntent(open).setAutoCancel(true)
                .build()
            try { manager.notify("${record.id}-$date".hashCode(), notification) } catch (_: SecurityException) { return 0 }
        }
        settings.lastReminderDay = today.toString()
        return due.size
    }
}

class ReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        Reminders.postDue(applicationContext)
        // Chain the next day's run; this keeps the time anchored to 9 AM across DST changes.
        Reminders.schedule(applicationContext, Settings(applicationContext).remindersEnabled)
        return Result.success()
    }
}
