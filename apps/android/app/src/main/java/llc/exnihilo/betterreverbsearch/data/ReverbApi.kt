package llc.exnihilo.betterreverbsearch.data

import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/**
 * Port of `error.ts` — the arms that survive without a CLI (no auth/schema paths are reachable here:
 * search answers unauthenticated and the only endpoint used is `GET /api/listings`).
 */
sealed class RevException(message: String) : Exception(message) {
  class Api(val code: Int, val detail: String) : RevException("API error $code: $detail")

  class Validation(detail: String) : RevException("Validation error: $detail")

  class Other(detail: String) : RevException(detail)
}

object ReverbApi {
  const val BASE_URL = "https://api.reverb.com/api/listings"
  const val USER_AGENT = "revcli-android/0.1.0"
  const val REQUEST_TIMEOUT_SECONDS = 30L

  internal val client =
    OkHttpClient.Builder()
      .callTimeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
      .readTimeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
      .build()

  suspend fun search(query: SearchQuery, apiKey: String? = null): SearchResult {
    val url =
      BASE_URL.toHttpUrl().newBuilder().apply {
        query.queryParams().forEach { (name, value) -> addQueryParameter(name, value) }
      }.build()

    val request =
      Request.Builder()
        .url(url)
        .header("Accept", "application/hal+json")
        .header("Accept-Version", "3.0")
        .header("User-Agent", USER_AGENT)
        .apply { if (!apiKey.isNullOrEmpty()) header("Authorization", "Bearer $apiKey") }
        .build()

    val (status, body) = sendWithRetry(request)
    if (status !in 200..299) {
      val message =
        runCatching {
          val root = json.parseToJsonElement(body) as JsonObject
          (root["message"] ?: root["Error"])?.jsonPrimitive?.content
        }.getOrNull() ?: "unknown error"
      throw RevException.Api(status, message)
    }

    val result =
      runCatching { parsePage(body) }
        .getOrElse { throw RevException.Other("failed to parse response: ${it.message}") }
    return result.copy(listings = SoldPrices.apply(result.listings))
  }

  /**
   * Exponential backoff on 429, honouring `retry-after`. 5 attempts, 60s cap — same policy as
   * `client.ts`.
   */
  private suspend fun sendWithRetry(request: Request): Pair<Int, String> {
    var delayMs = 1000L
    repeat(5) { attempt ->
      val (status, body, retryAfter) = execute(request)
      if (status != 429 || attempt == 4) return status to body

      val header = retryAfter?.toDoubleOrNull()?.let { (it * 1000).toLong().coerceAtLeast(0) }
      delay(header ?: delayMs)
      delayMs = (delayMs * 2).coerceAtMost(60_000)
    }
    throw RevException.Api(429, "rate limit exceeded after retries")
  }

  internal data class Raw(val status: Int, val body: String, val retryAfter: String?)

  internal suspend fun execute(request: Request): Raw =
    suspendCancellableCoroutine { cont ->
      val call = client.newCall(request)
      cont.invokeOnCancellation { call.cancel() }
      call.enqueue(
        object : Callback {
          override fun onFailure(call: Call, e: java.io.IOException) {
            cont.resumeWithException(RevException.Other(e.message ?: "network error"))
          }

          override fun onResponse(call: Call, response: Response) {
            response.use {
              cont.resume(Raw(it.code, it.body.string(), it.header("retry-after")))
            }
          }
        }
      )
    }
}

/**
 * Port of `applySoldPrices` in `search.ts`. The REST API reports a sold listing's last *ask* as
 * `price` — an accepted offer's amount never appears there. The real sale lives in Reverb's
 * undocumented GraphQL `priceRecordsSearch`; one aliased query per 50 listings, newest record wins (a
 * listing can sell twice). Best effort: any failure keeps the REST ask.
 */
object SoldPrices {
  const val URL = "https://gql.reverb.com/graphql"

  @Serializable data class Timestamp(val seconds: Long? = null)

  /** camelCase on this wire, unlike REST's [Money]. */
  @Serializable
  data class Amount(val amountCents: Int? = null, val currency: String? = null, val display: String? = null)

  @Serializable data class Record(val createdAt: Timestamp? = null, val amountProduct: Amount? = null)

  @Serializable data class Records(val priceRecords: List<Record>? = null)

  internal val recordsMap = MapSerializer(String.serializer(), Records.serializer().nullable)

  suspend fun apply(listings: List<Listing>): List<Listing> {
    val ids = listings.filter { it.state?.slug == "sold" }.map { it.id }
    if (ids.isEmpty()) return listings
    val found = coroutineScope {
      ids.chunked(50).map { chunk -> async { fetchOrNull(chunk).orEmpty() } }.awaitAll()
    }.fold(emptyMap<String, Records?>()) { a, b -> a + b }
    return merge(found, listings)
  }

  fun merge(found: Map<String, Records?>, listings: List<Listing>): List<Listing> =
    listings.map { l ->
      val newest =
        found["l${l.id}"]?.priceRecords?.maxByOrNull { it.createdAt?.seconds ?: 0 }?.amountProduct
      val cents = newest?.amountCents
      val display = newest?.display
      if (cents == null || cents <= 0 || display == null) return@map l
      l.copy(
        price =
          Money(
            amount = String.format(Locale.US, "%.2f", cents / 100.0),
            amountCents = cents,
            currency = newest.currency ?: l.price?.currency,
            display = display,
          ),
        originalPrice = l.originalPrice ?: l.price,
      )
    }

  private suspend fun fetchOrNull(ids: List<Int>): Map<String, Records?>? =
    try {
      withTimeoutOrNull(10_000) { fetch(ids) }
    } catch (e: CancellationException) {
      throw e
    } catch (e: Exception) {
      null
    }

  private suspend fun fetch(ids: List<Int>): Map<String, Records?>? {
    val fields =
      ids.joinToString(" ") {
        "l$it: priceRecordsSearch(input: {listingId: \"$it\"}) { priceRecords { createdAt { seconds } amountProduct { amountCents currency display } } }"
      }
    // The gateway rejects anonymous operations with GW-001.
    val payload = buildJsonObject {
      put("operationName", "SoldPrices")
      put("query", "query SoldPrices { $fields }")
    }
    val request =
      Request.Builder()
        .url(URL)
        .post(payload.toString().toRequestBody("application/json".toMediaType()))
        .build()
    val raw = ReverbApi.execute(request)
    if (raw.status !in 200..299) return null
    val data = (json.parseToJsonElement(raw.body) as JsonObject)["data"] as? JsonObject ?: return null
    return json.decodeFromJsonElement(recordsMap, data)
  }
}
