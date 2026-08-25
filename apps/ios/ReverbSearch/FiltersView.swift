import SwiftUI

struct FiltersView: View {
    @Binding var query: SearchQuery
    /// Client-side cuts. They apply to the listings already loaded, so unlike
    /// `query` they take effect the moment they change — no re-search needed.
    @Binding var filters: ListingFilters
    var onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Make", text: $query.make)
                    TextField("Model", text: $query.model)
                    Picker("Category", selection: $query.productType) {
                        Text("All").tag(ProductType?.none)
                        ForEach(ProductType.allCases) { Text($0.label).tag(ProductType?.some($0)) }
                    }
                    Picker("Condition", selection: $query.condition) {
                        Text("Any").tag(Condition?.none)
                        ForEach(Condition.buckets) { Text($0.label).tag(Condition?.some($0)) }
                        // Grades are a slice of `used`, so they read as a sub-list.
                        Section("Used — by grade") {
                            ForEach(Condition.grades) { Text($0.label).tag(Condition?.some($0)) }
                        }
                    }
                    Picker("Sort", selection: $query.sort) {
                        Text("Newest first").tag(Sort?.none)
                        ForEach(Sort.allCases) { Text($0.label).tag(Sort?.some($0)) }
                    }
                }

                Section("Price") {
                    number("Min", $query.priceMin)
                    number("Max", $query.priceMax)
                }

                Section("Year") {
                    number("Min", $query.yearMin)
                    number("Max", $query.yearMax)
                }

                Section("Listed date range") {
                    Picker("Newest", selection: $filters.newestMonths) {
                        ForEach(ListingFilters.monthOptions, id: \.self) { months in
                            Text(months == 0 ? "now" : "\(months) mo ago").tag(months)
                        }
                    }
                    Picker("Oldest", selection: $filters.oldestMonths) {
                        Text("any").tag(Int?.none)
                        ForEach(ListingFilters.monthOptions.dropFirst(), id: \.self) { months in
                            Text("\(months) mo ago").tag(Int?.some(months))
                        }
                    }
                }

                Section {
                    terms("Blacklist — hide titles matching", "relic, mini, copy", $filters.blacklist)
                    terms("Whitelist — keep only titles matching", "strat(ocaster)?, tele", $filters.whitelist)
                } header: {
                    Text("Blacklist / whitelist")
                } footer: {
                    let bad =
                        ListingFilters.invalidTerms(filters.blacklist)
                        + ListingFilters.invalidTerms(filters.whitelist)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            "Comma-separated, matched against the listing title as case-insensitive regexes."
                        )
                        if !bad.isEmpty {
                            Text("Ignored (invalid regex): \(bad.joined(separator: ", "))")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Picker("Per page", selection: $query.perPage) {
                        ForEach([12, 24, 50], id: \.self) { Text("\($0)") }
                    }
                    Toggle("Sold comps", isOn: $query.showOnlySold)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") {
                        dismiss()
                        onApply()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func terms(
        _ label: String, _ placeholder: String, _ value: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: value, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func number(_ label: String, _ value: Binding<Int?>) -> some View {
        TextField(label, value: value, format: .number)
            .keyboardType(.numberPad)
    }
}

struct PromoCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var applied = BypassCode.hasCode
    @State private var working = false
    @State private var message: String?

    private var code: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(applied ? "Applied — enter to replace" : "Promo code", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if applied {
                        Button("Remove code", role: .destructive) {
                            BypassCode.remove()
                            applied = false
                        }
                    }
                    if let message {
                        Text(message).font(.callout).foregroundStyle(.red)
                    }
                } footer: {
                    Text(
                        applied
                            ? "\(BypassCode.raisedLimit) searches a day while the code stays valid."
                            : "Have a code? It raises your daily search limit.")
                }
            }
            .navigationTitle("Promo code")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if working { ProgressView() } }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .disabled(working || code.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func apply() {
        working = true
        message = nil
        Task {
            do {
                if try await BypassCode.submit(code) { dismiss() }
                else { message = "That code isn't valid." }
            } catch {
                message = error.localizedDescription
            }
            working = false
        }
    }
}

struct APIKeyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var saved = APIKeyStore.load() != nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(saved ? "Stored — enter to replace" : "Reverb API token", text: $draft)
                    if saved {
                        Button("Remove key", role: .destructive) {
                            APIKeyStore.remove()
                            saved = false
                        }
                    }
                } footer: {
                    Text("Optional. Search works unauthenticated; a key just raises your rate limit.")
                }
            }
            .navigationTitle("API key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        APIKeyStore.save(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
