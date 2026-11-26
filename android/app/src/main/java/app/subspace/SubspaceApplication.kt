package app.subspace

import android.app.Application
import app.subspace.reminders.Reminders

class SubspaceApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Reminders.createChannel(this)
    }
}
