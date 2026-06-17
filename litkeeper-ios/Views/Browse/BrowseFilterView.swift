import SwiftUI

struct BrowseFilterView: View {
    @Binding var minScore: Double
    @Binding var minViews: Int
    @Binding var seriesFilter: String
    @Binding var dateRange: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Quality") {
                    Stepper(value: $minScore, in: 0...5, step: 0.1) {
                        HStack {
                            Text("Min Score")
                            Spacer()
                            Text(String(format: "%.1f", minScore))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Picker("Min Views", selection: $minViews) {
                        Text("Any").tag(0)
                        Text("100+").tag(100)
                        Text("500+").tag(500)
                        Text("1,000+").tag(1000)
                        Text("5,000+").tag(5000)
                        Text("10,000+").tag(10000)
                    }
                }

                Section("Date Range") {
                    Picker("Date Range", selection: $dateRange) {
                        Text("All Time").tag("all")
                        Text("Last 12 Months").tag("12mo")
                        Text("Last 30 Days").tag("30d")
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
