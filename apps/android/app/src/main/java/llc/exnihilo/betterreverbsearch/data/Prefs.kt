package llc.exnihilo.betterreverbsearch.data

import android.content.Context
import android.content.SharedPreferences
import java.util.Calendar

/**
 * Every on-device preference lives here. Initialised once from the activity, before any composable
 * can read it.
 */
object Prefs {
  private lateinit var prefs: SharedPreferences

  fun init(context: Context) {
    if (!::prefs.isInitialized) {
      prefs = context.applicationContext.getSharedPreferences("reverb", Context.MODE_PRIVATE)
    }
  }

  internal fun get(): SharedPreferences = prefs

  /** Display preference, not part of the search — survives Clear. */
  var gridView: Boolean
    get() = prefs.getBoolean("gridView", false)
    set(value) = prefs.edit().putBoolean("gridView", value).apply()

  /** How more results are reached; see `Paging`. Stored by name, unknown values fall back. */
  var paging: String?
    get() = prefs.getString("paging", null)
    set(value) = prefs.edit().putString("paging", value).apply()
}

/**
 * Optional personal API key. Search answers unauthenticated; a key just buys rate-limit headroom.
 *
 * ponytail: app-private SharedPreferences, not EncryptedSharedPreferences. The file is already
 * unreadable by other apps on a non-rooted device, and the alternative is an alpha androidx library
 * to guard a token that only raises a rate limit. Encrypt it if the key ever buys something real.
 */
object ApiKeyStore {
  private const val KEY = "apiKey"

  fun load(): String? = Prefs.get().getString(KEY, null)

  fun save(key: String) = Prefs.get().edit().putString(KEY, key).apply()

  fun remove() = Prefs.get().edit().remove(KEY).apply()
}

/**
 * Free tier: five searches a day. Pagination and filter tweaks on an already loaded result are free
 * — only a new search spends.
 *
 * ponytail: SharedPreferences, so clearing app data resets the count. There is no server to ask, and
 * the honest fix is a backend. Move the counter server-side if freeloading ever shows up in the
 * numbers.
 */
object QueryQuota {
  private const val DAY_KEY = "quotaDay"
  private const val COUNT_KEY = "quotaCount"

  const val dailyLimit = 5

  val used: Int
    get() = if (Prefs.get().getInt(DAY_KEY, -1) == today()) Prefs.get().getInt(COUNT_KEY, 0) else 0

  val remaining: Int
    get() = (dailyLimit - used).coerceAtLeast(0)

  fun consume() {
    Prefs.get().edit().putInt(DAY_KEY, today()).putInt(COUNT_KEY, used + 1).apply()
  }

  /**
   * Day number in the user's own calendar — the reset lands at their midnight, and a timezone change
   * can only ever hand out an extra day, never revoke one.
   */
  private fun today(): Int {
    val cal = Calendar.getInstance()
    return cal.get(Calendar.YEAR) * 366 + cal.get(Calendar.DAY_OF_YEAR)
  }
}
