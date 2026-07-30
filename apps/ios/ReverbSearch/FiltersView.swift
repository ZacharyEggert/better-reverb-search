import SwiftUI

struct FiltersView: View {
    @Binding var query: SearchQuery
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
                        ForEach(Condition.allCases) { Text($0.label).tag(Condition?.some($0)) }
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

                Section {
                    Picker("Per page", selection: $query.perPage) {
                        ForEach([12, 24, 50, 90], id: \.self) { Text("\($0)") }
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

    private func number(_ label: String, _ value: Binding<Int?>) -> some View {
        TextField(label, value: value, format: .number)
            .keyboardType(.numberPad)
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
