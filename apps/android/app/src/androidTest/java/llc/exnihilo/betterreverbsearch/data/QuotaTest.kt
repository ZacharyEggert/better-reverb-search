package llc.exnihilo.betterreverbsearch.data

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Port of the quota half of apps/ios/Tests/main.swift. Instrumented rather than local because the
 * counter lives in SharedPreferences, which needs a real Context.
 */
@RunWith(AndroidJUnit4::class)
class QuotaTest {

  @Before
  fun setUp() {
    Prefs.init(ApplicationProvider.getApplicationContext())
    Prefs.get().edit().clear().apply()
  }

  @Test
  fun countsDownClampsAtZeroAndResetsOnAStaleDay() {
    assertEquals(QueryQuota.dailyLimit, QueryQuota.remaining)
    repeat(QueryQuota.dailyLimit) { QueryQuota.consume() }
    assertEquals(QueryQuota.dailyLimit, QueryQuota.used)
    assertEquals(0, QueryQuota.remaining)
    QueryQuota.consume()
    assertEquals(0, QueryQuota.remaining)

    Prefs.get().edit().putInt("quotaDay", 1).putInt("quotaCount", 99).apply()
    assertEquals(QueryQuota.dailyLimit, QueryQuota.remaining)
  }
}
