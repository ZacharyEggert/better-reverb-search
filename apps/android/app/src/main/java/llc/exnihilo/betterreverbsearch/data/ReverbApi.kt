package llc.exnihilo.betterreverbsearch.data

import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
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

    return runCatching { parsePage(body) }
      .getOrElse { throw RevException.Other("failed to parse response: ${it.message}") }
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
