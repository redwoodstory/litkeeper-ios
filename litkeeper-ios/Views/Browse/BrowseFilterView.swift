import SwiftUI

struct BrowseFilterView: View {
    @Binding var minScore: Double
    @Binding var minViews: Int
    @Binding var minFaves: Int
    @Binding var seriesFilter: String
    @Binding var dateRange: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Quality") {
                    Picker("Min Score", selection: $minScore) {
                        Text("Any").tag(0.0)
                        Text("4.0+").tag(4.0)
                        Text("4.25+").tag(4.25)
                        Text("4.5+").tag(4.5)
                        Text("4.75+").tag(4.75)
                    }
                    Picker("Min Views", selection: $minViews) {
                        Text("Any").tag(0)
                        Text("100+").tag(100)
                        Text("500+").tag(500)
                        Text("1,000+").tag(1000)
                        Text("5,000+").tag(5000)
                        Text("10,000+").tag(10000)
                    }
                    Picker("Min Favorites", selection: $minFaves) {
                        Text("Any").tag(0)
                        Text("10+").tag(10)
                        Text("25+").tag(25)
                        Text("50+").tag(50)
                        Text("100+").tag(100)
                        Text("500+").tag(500)
                    }
                }

                Section("Date Range") {
                    Picker("Date Range", selection: $dateRange) {
                        Text("All Time").tag("all")
                        Text("Last 12 Months").tag("12mo")
                        Text("Last 30 Days").tag("30d")
                        Text("Older than 30 Days").tag("older_30d")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Series") {
                    Picker("Series", selection: $seriesFilter) {
                        Text("All").tag("all")
                        Text("Series Only").tag("only")
                        Text("Singles Only").tag("exclude")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
