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
}
