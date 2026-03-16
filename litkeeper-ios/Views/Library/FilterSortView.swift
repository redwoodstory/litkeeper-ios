import SwiftUI

struct FilterSortView: View {
    @Binding var selectedCategory: String?
    @Binding var sortBy: LibraryViewModel.SortOption
    @Binding var sortAscending: Bool
    @Binding var showQueueOnly: Bool
    let categories: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort") {
                    Picker("Sort by", selection: $sortBy) {
                        ForEach(LibraryViewModel.SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    Toggle("Ascending", isOn: $sortAscending)
                }

                Section("Filter") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(String?.none)
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(String?.some(cat))
                        }
                    }
                    Toggle("Reading Queue Only", isOn: $showQueueOnly)
                }

                Section {
                    Button("Reset Filters") {
                        selectedCategory = nil
                        sortBy = .dateAdded
                        sortAscending = false
                        showQueueOnly = false
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
