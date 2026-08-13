package llc.exnihilo.betterreverbsearch.data

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
    BypassCode.verified = false
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

  @Test
  fun onlyAServerConfirmedCodeRaisesTheLimit() {
    // A stored code alone doesn't raise the limit, so an unreachable service leaves the user at
    // the default.
    assertFalse(BypassCode.isActive)
    assertEquals(5, QueryQuota.dailyLimit)

    Prefs.get().edit().putString("bypassCode", "code").apply()
    assertTrue(BypassCode.hasCode)
    assertFalse(BypassCode.isActive)
    assertEquals(5, QueryQuota.dailyLimit)

    BypassCode.verified = true
    assertTrue(BypassCode.isActive)
    assertEquals(BypassCode.RAISED_LIMIT, QueryQuota.dailyLimit)

    BypassCode.remove()
    assertFalse(BypassCode.isActive)
    assertEquals(5, QueryQuota.dailyLimit)
  }

  @Test
  fun upgradePitchHidesUntilHalfTheRaisedQuotaIsSpent() {
    Prefs.get().edit().putString("bypassCode", "code").apply()
    BypassCode.verified = true
    assertFalse(QueryQuota.offerUpgrade)

    repeat(BypassCode.RAISED_LIMIT / 2) { QueryQuota.consume() }
    assertTrue(QueryQuota.offerUpgrade)

    // Without a code it's always available.
    BypassCode.remove()
    assertTrue(QueryQuota.offerUpgrade)
  }
}
