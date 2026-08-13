package llc.exnihilo.betterreverbsearch.data

import android.content.Context
import android.content.SharedPreferences
import java.util.Calendar
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

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

  /** A verified promo code raises it; see [BypassCode]. */
  val dailyLimit: Int
    get() = if (BypassCode.isActive) BypassCode.RAISED_LIMIT else 5

  val used: Int
    get() = if (Prefs.get().getInt(DAY_KEY, -1) == today()) Prefs.get().getInt(COUNT_KEY, 0) else 0

  val remaining: Int
    get() = (dailyLimit - used).coerceAtLeast(0)

  /**
   * A promo code buys a quiet app: no upgrade pitch until half the day's quota is spent. Without
   * one, the pitch is always available.
   */
  val offerUpgrade: Boolean
    get() = !BypassCode.isActive || used >= dailyLimit / 2

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

/**
 * Promo code that raises the free daily limit. The server owns the answer — the app only caches the
 * code and the last verdict.
 */
object BypassCode {
  const val ENDPOINT = "https://reverb-search.diablo.guitars/api/bypass-limit"
  const val RAISED_LIMIT = 1000

  private const val KEY = "bypassCode"

  /**
   * The raised limit is live only once the server has confirmed the code this launch — an
   * unreachable server means the default limit, not a free pass. Not persisted, so every launch has
   * to earn it again.
   */
  @Volatile var verified = false

  val isActive: Boolean
    get() = verified

  /** A code is stored, whether or not it's been confirmed yet. */
  val hasCode: Boolean
    get() = Prefs.get().getString(KEY, null) != null

  enum class Check {
    NO_CODE,
    VALID,
    INVALID,
    UNREACHABLE,
  }

  /**
   * Re-checks the stored code. Rejection drops it; an unreachable server keeps it but leaves the
   * limit at the default.
   */
  suspend fun refresh(): Check {
    val code = Prefs.get().getString(KEY, null) ?: return Check.NO_CODE
    val valid = verify(code) ?: return Check.UNREACHABLE
    verified = valid
    if (!valid) Prefs.get().edit().remove(KEY).apply()
    return if (valid) Check.VALID else Check.INVALID
  }

  /**
   * Stores the code if the server accepts it. Returns whether it did; throws when the endpoint
   * couldn't be reached.
   */
  suspend fun submit(code: String): Boolean {
    val valid = verify(code) ?: throw RevException.Other("Couldn't reach the server — try again.")
    if (valid) {
      Prefs.get().edit().putString(KEY, code).apply()
      verified = true
    }
    return valid
  }

  fun remove() {
    Prefs.get().edit().remove(KEY).apply()
    verified = false
  }

  /** null means "couldn't tell" — never treat that as a rejection. */
  private suspend fun verify(code: String): Boolean? {
    val body =
      json.encodeToString(kotlinx.serialization.serializer<Map<String, String>>(), mapOf("key" to code))
    val request =
      Request.Builder()
        .url(ENDPOINT)
        .post(body.toRequestBody("application/json".toMediaType()))
        .header("User-Agent", ReverbApi.USER_AGENT)
        .build()

    val raw = runCatching { ReverbApi.execute(request) }.getOrNull() ?: return null
    if (raw.status != 200) return null
    return runCatching {
      (json.parseToJsonElement(raw.body) as JsonObject)["valid"]!!.jsonPrimitive.content.toBoolean()
    }.getOrNull()
  }
}
