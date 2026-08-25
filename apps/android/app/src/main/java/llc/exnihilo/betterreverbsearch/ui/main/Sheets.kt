package llc.exnihilo.betterreverbsearch.ui.main

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import llc.exnihilo.betterreverbsearch.data.ApiKeyStore
import llc.exnihilo.betterreverbsearch.data.BypassCode
import llc.exnihilo.betterreverbsearch.data.Condition
import llc.exnihilo.betterreverbsearch.data.ListingFilters
import llc.exnihilo.betterreverbsearch.data.ProductType
import llc.exnihilo.betterreverbsearch.data.SearchQuery
import llc.exnihilo.betterreverbsearch.data.Sort

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FiltersSheet(
  query: SearchQuery,
  filters: ListingFilters,
  onDismiss: () -> Unit,
  /** Client-side cuts apply to the listings already loaded — no re-search needed. */
  onFilters: (ListingFilters) -> Unit,
  onApply: (SearchQuery) -> Unit,
) {
  var draft by remember { mutableStateOf(query) }
  var cuts by remember { mutableStateOf(filters) }

  fun setCuts(next: ListingFilters) {
    cuts = next
    onFilters(next)
  }

  ModalBottomSheet(onDismissRequest = onDismiss) {
    Column(
      Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Text("Filters", style = MaterialTheme.typography.titleLarge)

      OutlinedTextField(
        value = draft.make,
        onValueChange = { draft = draft.copy(make = it) },
        label = { Text("Make") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
      )
      OutlinedTextField(
        value = draft.model,
        onValueChange = { draft = draft.copy(model = it) },
        label = { Text("Model") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
      )

      Dropdown("Category", draft.productType, ProductType.entries, "All", { it.label }) {
        draft = draft.copy(productType = it)
      }
      // Buckets first, then the grades — grades are a slice of `used`, not a parallel axis.
      Dropdown(
        "Condition",
        draft.condition,
        Condition.buckets + Condition.grades,
        "Any",
        { if (it in Condition.buckets) it.label else "used — ${it.label}" },
      ) {
        draft = draft.copy(condition = it)
      }
      Dropdown("Sort", draft.sort, Sort.entries, "Newest first", { it.label }) {
        draft = draft.copy(sort = it)
      }

      Text("Price", style = MaterialTheme.typography.titleSmall)
      Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        NumberField("Min", draft.priceMin, Modifier.weight(1f)) { draft = draft.copy(priceMin = it) }
        NumberField("Max", draft.priceMax, Modifier.weight(1f)) { draft = draft.copy(priceMax = it) }
      }

      Text("Year", style = MaterialTheme.typography.titleSmall)
      Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        NumberField("Min", draft.yearMin, Modifier.weight(1f)) { draft = draft.copy(yearMin = it) }
        NumberField("Max", draft.yearMax, Modifier.weight(1f)) { draft = draft.copy(yearMax = it) }
      }

      Dropdown("Per page", draft.perPage, listOf(12, 24, 50), "24", { it.toString() }) {
        draft = draft.copy(perPage = it ?: 24)
      }

      Text("Blacklist / whitelist", style = MaterialTheme.typography.titleSmall)
      OutlinedTextField(
        value = cuts.blacklist,
        onValueChange = { setCuts(cuts.copy(blacklist = it)) },
        label = { Text("Hide titles matching") },
        placeholder = { Text("relic, mini, copy") },
        modifier = Modifier.fillMaxWidth(),
      )
      OutlinedTextField(
        value = cuts.whitelist,
        onValueChange = { setCuts(cuts.copy(whitelist = it)) },
        label = { Text("Keep only titles matching") },
        placeholder = { Text("strat(ocaster)?, tele") },
        modifier = Modifier.fillMaxWidth(),
      )
      Text(
        "Comma-separated, matched against the listing title as case-insensitive regexes.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
      val bad = ListingFilters.invalidTerms(cuts.blacklist) + ListingFilters.invalidTerms(cuts.whitelist)
      if (bad.isNotEmpty()) {
        Text(
          "Ignored (invalid regex): ${bad.joinToString(", ")}",
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.error,
        )
      }

      Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("Sold comps", Modifier.weight(1f))
        Switch(
          checked = draft.showOnlySold,
          onCheckedChange = { draft = draft.copy(showOnlySold = it) },
        )
      }

      Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        TextButton(onClick = onDismiss) { Text("Close") }
        Button(onClick = { onApply(draft) }) { Text("Search") }
      }
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> Dropdown(
  label: String,
  selected: T?,
  options: List<T>,
  noneLabel: String,
  optionLabel: (T) -> String,
  onSelect: (T?) -> Unit,
) {
  var expanded by remember { mutableStateOf(false) }
  ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
    OutlinedTextField(
      value = selected?.let(optionLabel) ?: noneLabel,
      onValueChange = {},
      readOnly = true,
      label = { Text(label) },
      trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
      modifier =
        Modifier.fillMaxWidth()
          .menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable),
    )
    ExposedDropdownMenu(
      expanded = expanded,
      onDismissRequest = { expanded = false },
    ) {
      DropdownMenuItem(
        text = { Text(noneLabel) },
        onClick = {
          onSelect(null)
          expanded = false
        },
      )
      options.forEach { option ->
        DropdownMenuItem(
          text = { Text(optionLabel(option)) },
          onClick = {
            onSelect(option)
            expanded = false
          },
        )
      }
    }
  }
}

@Composable
private fun NumberField(label: String, value: Int?, modifier: Modifier, onChange: (Int?) -> Unit) {
  OutlinedTextField(
    value = value?.toString() ?: "",
    onValueChange = { onChange(it.filter(Char::isDigit).toIntOrNull()) },
    label = { Text(label) },
    singleLine = true,
    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
    modifier = modifier,
  )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PromoCodeSheet(onDismiss: () -> Unit) {
  var draft by remember { mutableStateOf("") }
  var applied by remember { mutableStateOf(BypassCode.hasCode) }
  var working by remember { mutableStateOf(false) }
  var message by remember { mutableStateOf<String?>(null) }
  val scope = rememberCoroutineScope()
  val code = draft.trim()

  ModalBottomSheet(onDismissRequest = onDismiss) {
    Column(
      Modifier.padding(horizontal = 16.dp).padding(bottom = 32.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Text("Promo code", style = MaterialTheme.typography.titleLarge)
      OutlinedTextField(
        value = draft,
        onValueChange = { draft = it },
        label = { Text(if (applied) "Applied — enter to replace" else "Promo code") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
      )
      if (applied) {
        TextButton(
          onClick = {
            BypassCode.remove()
            applied = false
          }
        ) {
          Text("Remove code", color = MaterialTheme.colorScheme.error)
        }
      }
      message?.let { Text(it, color = MaterialTheme.colorScheme.error) }
      Text(
        if (applied) "${BypassCode.RAISED_LIMIT} searches a day while the code stays valid."
        else "Have a code? It raises your daily search limit.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
      Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
        if (working) CircularProgressIndicator(Modifier.padding(end = 12.dp))
        TextButton(onClick = onDismiss) { Text("Close") }
        Button(
          enabled = !working && code.isNotEmpty(),
          onClick = {
            working = true
            message = null
            scope.launch {
              try {
                if (BypassCode.submit(code)) onDismiss() else message = "That code isn't valid."
              } catch (e: Exception) {
                message = e.message
              }
              working = false
            }
          },
        ) {
          Text("Apply")
        }
      }
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ApiKeySheet(onDismiss: () -> Unit) {
  var draft by remember { mutableStateOf("") }
  var saved by remember { mutableStateOf(ApiKeyStore.load() != null) }

  ModalBottomSheet(onDismissRequest = onDismiss) {
    Column(
      Modifier.padding(horizontal = 16.dp).padding(bottom = 32.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Text("API key", style = MaterialTheme.typography.titleLarge)
      OutlinedTextField(
        value = draft,
        onValueChange = { draft = it },
        label = { Text(if (saved) "Stored — enter to replace" else "Reverb API token") },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        modifier = Modifier.fillMaxWidth(),
      )
      if (saved) {
        TextButton(
          onClick = {
            ApiKeyStore.remove()
            saved = false
          }
        ) {
          Text("Remove key", color = MaterialTheme.colorScheme.error)
        }
      }
      Text(
        "Optional. Search works unauthenticated; a key just raises your rate limit.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
      Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        TextButton(onClick = onDismiss) { Text("Close") }
        Button(
          enabled = draft.trim().isNotEmpty(),
          onClick = {
            ApiKeyStore.save(draft.trim())
            onDismiss()
          },
        ) {
          Text("Save")
        }
      }
    }
  }
}
