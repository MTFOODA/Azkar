package com.azkar.azkar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker
import dev.fluttercommunity.workmanager.SharedPreferenceHelper

/// Re-evaluate local wall-clock reminders after timezone, date and DST changes.
class ReminderRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (SharedPreferenceHelper.getCallbackHandle(context) == -1L) return
        val data = Data.Builder().putString(BackgroundWorker.DART_TASK_KEY,
            "com.azkar.azkar.refresh-reminders").build()
        WorkManager.getInstance(context).enqueueUniqueWork("azkar-clock-refresh",
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<BackgroundWorker>().setInputData(data).build())
    }
}
