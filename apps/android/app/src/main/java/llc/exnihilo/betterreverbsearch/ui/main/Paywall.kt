package llc.exnihilo.betterreverbsearch.ui.main

import android.app.Activity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.activity.compose.LocalActivity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import llc.exnihilo.betterreverbsearch.R
import llc.exnihilo.betterreverbsearch.data.Billing
import llc.exnihilo.betterreverbsearch.data.QueryQuota
import llc.exnihilo.betterreverbsearch.data.billingPeriodLabel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallSheet(onDismiss: () -> Unit) {
  val subscribed by Billing.isSubscribed.collectAsStateWithLifecycle()
  val product by Billing.product.collectAsStateWithLifecycle()
  var working by remember { mutableStateOf(false) }
  var errorMessage by remember { mutableStateOf<String?>(null) }
  val scope = rememberCoroutineScope()
  val activity = LocalActivity.current
  val uriHandler = LocalUriHandler.current

  // The purchase result arrives asynchronously from Play, not from the launch call.
  LaunchedEffect(subscribed) { if (subscribed) onDismiss() }

  /**
   * Falls back to the configured price only if Play is unreachable — the storefront's own formatted
   * price is the one that's correct abroad.
   */
  val price = product?.let { Billing.basePhase(it)?.formattedPrice } ?: "$49.99"
  val intro = product?.let { Billing.introPhase(it) }
  val introPeriod = intro?.let { billingPeriodLabel(it.billingPeriod) }

  val pitch =
    if (intro == null)
      "${QueryQuota.dailyLimit} searches a day are free. Go unlimited for $price per month."
    else
      "${QueryQuota.dailyLimit} searches a day are free. Go unlimited for ${intro.formattedPrice} your first $introPeriod, then $price per month."

  val callToAction =
    if (intro == null) "Subscribe — $price/month" else "Start for ${intro.formattedPrice}"

  val disclosure =
    if (intro == null)
      "Auto-renews monthly until cancelled. Manage or cancel in Google Play › Payments & subscriptions."
    else
      "${intro.formattedPrice} for your first $introPeriod, then $price per month. Auto-renews until cancelled. Manage or cancel in Google Play › Payments & subscriptions."

  ModalBottomSheet(onDismissRequest = onDismiss) {
    Column(
      Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 32.dp),
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      Icon(
        painterResource(R.drawable.ic_glyph),
        contentDescription = null,
        tint = MaterialTheme.colorScheme.primary,
        modifier = Modifier.size(64.dp),
      )
      Text("Unlimited Queries", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
      Text(
        pitch,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
      )

      Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Benefit(R.drawable.ic_infinity, "Unlimited searches, every day")
        Benefit(R.drawable.ic_tag, "Sold comps — what gear actually clears for")
        Benefit(R.drawable.ic_chart, "Low / median / high on every result set")
      }

      errorMessage?.let {
        Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
      }

      Button(
        enabled = !working && product != null && activity != null,
        onClick = {
          errorMessage = null
          if (!Billing.purchase(activity as Activity)) {
            errorMessage = "Couldn't start the purchase — try again."
          }
        },
        modifier = Modifier.fillMaxWidth(),
      ) {
        Text(callToAction, fontWeight = FontWeight.SemiBold)
      }

      Row(verticalAlignment = Alignment.CenterVertically) {
        if (working) CircularProgressIndicator(Modifier.padding(end = 12.dp))
        // On Play, restoring is just re-reading what the account already owns.
        TextButton(
          enabled = !working,
          onClick = {
            working = true
            errorMessage = null
            scope.launch {
              Billing.refresh()
              if (!Billing.isSubscribed.value) {
                errorMessage = "No active subscription found on this account."
              }
              working = false
            }
          },
        ) {
          Text("Restore purchases")
        }
      }

      Text(
        disclosure,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
      )

      Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        TextButton(onClick = { uriHandler.openUri(TERMS) }) { Text("Terms") }
        TextButton(onClick = { uriHandler.openUri(PRIVACY) }) { Text("Privacy") }
      }

      TextButton(onClick = onDismiss) { Text("Not now") }

      Text(
        AFFILIATION_DISCLAIMER,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
      )
    }
  }
}

@Composable
private fun Benefit(icon: Int, text: String) {
  Row(
    horizontalArrangement = Arrangement.spacedBy(12.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      painterResource(icon),
      contentDescription = null,
      tint = MaterialTheme.colorScheme.primary,
      modifier = Modifier.size(20.dp),
    )
    Text(text, style = MaterialTheme.typography.bodyMedium)
  }
}

private const val TERMS = "https://play.google.com/about/play-terms/"
private const val PRIVACY = "https://ex-nihilo.llc/privacy"
