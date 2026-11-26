package app.subspace

import android.content.Context
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.subspace.core.BillingInterval
import app.subspace.core.BillingUnit
import app.subspace.core.Category
import app.subspace.core.SubscriptionRecord
import app.subspace.data.SubscriptionStore
import app.subspace.ui.MainActivity
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId

@RunWith(AndroidJUnit4::class)
class AppFlowTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private var scenario: ActivityScenario<MainActivity>? = null

    @Before fun reset() {
        File(context.filesDir, SubscriptionStore.FILE_NAME).delete()
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().clear().commit()
    }
    @After fun close() { scenario?.close() }
    /** Launches and waits for the subscriptions to load (it happens off the main thread). */
    private fun shell(command: String): String =
        android.os.ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)).use { it.readBytes().decodeToString() }

    private fun launch(readyTag: String = "tab-overview") {
        scenario = ActivityScenario.launch(MainActivity::class.java)
        compose.waitUntil(15_000) { compose.onAllNodesWithTag(readyTag).fetchSemanticsNodes().isNotEmpty() }
    }

    @Test fun addSubscriptionFromPresetAndSeeTotals() {
        launch()
        compose.onNodeWithTag("addSubscription").performClick()
        compose.onNodeWithTag("presetSearch").performTextInput("Netflix")
        compose.onNodeWithTag("preset-Netflix").performClick()
        compose.onNodeWithTag("paymentAmount").performTextInput("12.99")
        compose.onNodeWithTag("saveSubscription").performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("monthlyAverage").assertIsDisplayed()
        compose.onNodeWithTag("monthlyAverage").assert(hasText("12.99", substring = true))
        compose.onNodeWithTag("tab-subscriptions").performClick()
        compose.onNodeWithTag("row-Netflix").assertIsDisplayed()
    }

    @Test fun editorRejectsInvalidAmount() {
        launch()
        compose.onNodeWithTag("addSubscription").performClick()
        compose.onNodeWithTag("createCustom").performClick()
        compose.onNodeWithTag("serviceName").performTextInput("Custom plan")
        compose.onNodeWithTag("paymentAmount").performTextInput("12.99 CAD")
        compose.onNodeWithTag("saveSubscription").performClick()
        compose.onNodeWithTag("validation").assertIsDisplayed().assert(hasText("Enter a valid payment amount."))
    }

    /** 300 plans across currencies and intervals: every tab must render and scroll to its end. */
    @Test fun largeDataSetScrollsEveryTab() {
        seedLargeDataSet()
        launch(readyTag = "overviewList")
        compose.onNodeWithTag("overviewList").performScrollToNode(hasTestTag("overviewBottom"))
        compose.onNodeWithTag("tab-subscriptions").performClick()
        compose.onNodeWithTag("subscriptionsList").performScrollToNode(hasText("Plan 300", substring = true))
        compose.onNodeWithTag("subscriptionsList").performScrollToNode(hasTestTag("subscriptionsBottom"))
        compose.onNodeWithTag("tab-analytics").performClick()
        compose.onNodeWithTag("analyticsList").performScrollToNode(hasTestTag("analyticsBottom"))
        compose.onNodeWithTag("analyticsBottom").performClick()
        compose.onNodeWithTag("paymentCalendar").assertIsDisplayed()
    }

    /**
     * Smoothness: real finger swipes through Android's input system (not test-clock jumps) over 300
     * plans on each tab, then the renderer's own frame statistics. CI prints them. Run against the
     * non-debuggable "benchmark" build; debuggable builds are much slower by design.
     */
    @Test fun swipeScrollingFrameStatistics() {
        seedLargeDataSet()
        launch(readyTag = "overviewList")
        val metrics = context.resources.displayMetrics
        val x = metrics.widthPixels / 2
        val (low, high) = (metrics.heightPixels * 0.72).toInt() to (metrics.heightPixels * 0.30).toInt()
        fun swipes() {
            repeat(12) { shell("input swipe $x $low $x $high 180"); Thread.sleep(350) }
            repeat(12) { shell("input swipe $x $high $x $low 180"); Thread.sleep(350) }
        }
        Thread.sleep(1_000)
        shell("dumpsys gfxinfo ${context.packageName} reset")
        swipes()
        compose.onNodeWithTag("tab-subscriptions").performClick(); Thread.sleep(800); swipes()
        compose.onNodeWithTag("tab-analytics").performClick(); Thread.sleep(800); swipes()
        val stats = shell("dumpsys gfxinfo ${context.packageName}").lines()
            .filter { line -> listOf("Total frames rendered", "Janky frames", "50th percentile", "90th percentile", "95th percentile", "99th percentile", "Number Slow UI thread", "Number Frame deadline missed").any { line.trim().startsWith(it) } }
        stats.forEach { android.util.Log.i("SubspaceFrames", it.trim()) }
    }

    private fun seedLargeDataSet() {
        val zone = ZoneId.systemDefault()
        val start = LocalDate.now().withDayOfYear(1)
        val intervals = listOf(BillingInterval.WEEKLY, BillingInterval.MONTHLY, BillingInterval.ANNUAL, BillingInterval.QUARTERLY, BillingInterval(10, BillingUnit.DAY))
        val records = (1..300).map { i ->
            val first = LocalDate.now().plusDays((i % 40).toLong())
            SubscriptionRecord(name = "Plan %03d".format(i), amount = BigDecimal(i).divide(BigDecimal(4)).add(BigDecimal.ONE), currency = listOf("CAD", "USD", "EUR")[i % 3],
                interval = intervals[i % intervals.size], startDate = start.atStartOfDay(zone).toInstant(), nextRenewal = first.atStartOfDay(zone).toInstant(),
                category = Category.entries[i % Category.entries.size], reminderDays = 3)
        }
        SubscriptionStore(context).save(records)
    }
}
