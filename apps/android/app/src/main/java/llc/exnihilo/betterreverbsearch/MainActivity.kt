package llc.exnihilo.betterreverbsearch

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import llc.exnihilo.betterreverbsearch.data.Billing
import llc.exnihilo.betterreverbsearch.data.Prefs
import llc.exnihilo.betterreverbsearch.theme.ReverbSearchTheme
import llc.exnihilo.betterreverbsearch.ui.main.MainScreen

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    // Both read-only singletons; init before anything can compose against them.
    Prefs.init(this)
    Billing.init(this)

    enableEdgeToEdge()
    setContent {
      ReverbSearchTheme {
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
          MainScreen()
        }
      }
    }
  }

  override fun onResume() {
    super.onResume()
    // Renewals, refunds, and purchases made on another device land here.
    lifecycleScope.launch { Billing.refresh() }
  }
}
