package llc.exnihilo.betterreverbsearch.data

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * The subscription. There is no backend — the app talks to Reverb directly — so entitlement lives
 * on-device, on what Play reports for this account.
 *
 * ponytail: no server-side receipt verification, because there is no server. Play's own purchase
 * state is the check. Add signature verification against a backend if entitlement ever guards
 * something expensive.
 */
object Billing {
  const val PRODUCT_ID = "unlimited_monthly"

  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
  private var client: BillingClient? = null

  private val _isSubscribed = MutableStateFlow(false)
  val isSubscribed: StateFlow<Boolean> = _isSubscribed.asStateFlow()

  private val _product = MutableStateFlow<ProductDetails?>(null)
  val product: StateFlow<ProductDetails?> = _product.asStateFlow()

  fun init(context: Context) {
    if (client != null) return
    client =
      BillingClient.newBuilder(context.applicationContext)
        .setListener { _, purchases -> scope.launch { purchases?.forEach { grant(it) }; refresh() } }
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    client!!.startConnection(
      object : BillingClientStateListener {
        override fun onBillingSetupFinished(result: BillingResult) {
          scope.launch {
            _product.value = queryProduct()
            refresh()
          }
        }

        override fun onBillingServiceDisconnected() = Unit
      }
    )
  }

  /** Re-reads what Play says this account owns. Doubles as "restore purchases". */
  suspend fun refresh() {
    val client = client ?: return
    if (!client.isReady) return
    val purchases =
      billingCall<List<Purchase>> { resume ->
        client.queryPurchasesAsync(
          QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()
        ) { _, list ->
          resume(list)
        }
      }
    purchases.forEach { grant(it) }
    _isSubscribed.value =
      purchases.any {
        PRODUCT_ID in it.products && it.purchaseState == Purchase.PurchaseState.PURCHASED
      }
  }

  /** Returns false if the flow couldn't be launched; the result itself arrives via the listener. */
  fun purchase(activity: Activity): Boolean {
    val client = client ?: return false
    val product = _product.value ?: return false
    val offerToken = bestOffer(product)?.offerToken ?: return false
    val params =
      BillingFlowParams.newBuilder()
        .setProductDetailsParamsList(
          listOf(
            BillingFlowParams.ProductDetailsParams.newBuilder()
              .setProductDetails(product)
              .setOfferToken(offerToken)
              .build()
          )
        )
        .build()
    return client.launchBillingFlow(activity, params).responseCode == BillingClient.BillingResponseCode.OK
  }

  /**
   * Play only returns offers this account is still eligible for, so the cheapest first phase wins —
   * that is the intro offer when there is one, the base plan otherwise.
   */
  fun bestOffer(product: ProductDetails): ProductDetails.SubscriptionOfferDetails? =
    product.subscriptionOfferDetails?.minByOrNull {
      it.pricingPhases.pricingPhaseList.firstOrNull()?.priceAmountMicros ?: Long.MAX_VALUE
    }

  /** The recurring price — the last phase of the offer, once any intro phase has run out. */
  fun basePhase(product: ProductDetails): ProductDetails.PricingPhase? =
    bestOffer(product)?.pricingPhases?.pricingPhaseList?.lastOrNull()

  /** Non-null only while this account can still claim a cheaper first period. */
  fun introPhase(product: ProductDetails): ProductDetails.PricingPhase? {
    val phases = bestOffer(product)?.pricingPhases?.pricingPhaseList ?: return null
    return if (phases.size > 1) phases.first() else null
  }

  /** Play auto-refunds a purchase that is never acknowledged. */
  private suspend fun grant(purchase: Purchase) {
    val client = client ?: return
    if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED || purchase.isAcknowledged) return
    billingCall<Unit> { resume ->
      client.acknowledgePurchase(
        AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
      ) {
        resume(Unit)
      }
    }
  }

  private suspend fun queryProduct(): ProductDetails? {
    val client = client ?: return null
    val params =
      QueryProductDetailsParams.newBuilder()
        .setProductList(
          listOf(
            QueryProductDetailsParams.Product.newBuilder()
              .setProductId(PRODUCT_ID)
              .setProductType(BillingClient.ProductType.SUBS)
              .build()
          )
        )
        .build()
    return billingCall { resume ->
      client.queryProductDetailsAsync(params) { _, result ->
        resume(result.productDetailsList.firstOrNull())
      }
    }
  }

  /**
   * Play invokes a response listener more than once when it reconnects or retries, and from
   * different threads — resuming a continuation twice is a crash, so every callback goes through
   * here. The latch has to be atomic: checking `cont.isActive` first loses the race.
   */
  private suspend fun <T> billingCall(block: ((T) -> Unit) -> Unit): T =
    suspendCancellableCoroutine { cont ->
      val done = AtomicBoolean()
      block { value -> if (done.compareAndSet(false, true)) cont.resume(value) }
    }
}

/** ISO-8601 subscription period ("P1M") as words, for the offer disclosure. */
fun billingPeriodLabel(period: String): String {
  val match = Regex("P(\\d+)([DWMY])").find(period) ?: return period
  val value = match.groupValues[1].toInt()
  val unit =
    when (match.groupValues[2]) {
      "D" -> "day"
      "W" -> "week"
      "M" -> "month"
      "Y" -> "year"
      else -> "period"
    }
  return if (value == 1) unit else "$value ${unit}s"
}
