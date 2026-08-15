import SwiftUI
import Charts

/// Drill-down for a single category: the months it was spent across, and the
/// transactions behind them.
///
/// The month chart is interactive — tapping a bar narrows the list to that
/// month, and tapping more adds them. Before that, this screen dumped every
/// transaction in the category for the whole range with no way to cut it down,
/// which for a big category like Groceries is hundreds of rows.
struct AnalysisCategoryDetailView: View {
    let category: SpendCategory
    let transactions: [TransactionRecord]
    let rules: [CategoryRule]

    @State private var detail: TransactionRecord?
    /// Empty means "every month" — the chart starts unfiltered.
    @State private var selectedMonths: Set<Date> = []
    @State private var sortOrder: SortOrder = .dateDesc
    @State private var search = ""

    enum SortOrder: String, CaseIterable, Identifiable {
        case dateDesc = "Newest first"
        case dateAsc = "Oldest first"
        case amountDesc = "Largest first"
        case amountAsc = "Smallest first"
        var id: String { rawValue }
    }

    /// Everything the screen shows, derived in one pass.
    ///
    /// `months` is deliberately computed from *all* of the category's
    /// transactions rather than the filtered ones: the chart is the control
    /// you filter with, so it has to keep every bar you might want to tap —
    /// and keep its shape while you tap them.
    private struct Content {
        let months: [MerchantAnalytics.CategoryMonth]
        let visible: [TransactionRecord]
        let total: Double
        let isFiltered: Bool
    }

    private var content: Content {
        let calendar = Calendar.current
        // Positive amounts only, matching what the Analysis screen counted to
        // produce the row you tapped. Including refunds here made the
        // drill-down's total disagree with the average it came from.
        let all = transactions.filter {
            $0.amount > 0 && $0.resolvedCategory(using: rules) == category
        }

        var buckets: [Date: Double] = [:]
        for txn in all {
            guard let monthStart = calendar.dateInterval(of: .month, for: txn.date)?.start else { continue }
            buckets[monthStart, default: 0] += txn.amount
        }
        let months = buckets
            .map { MerchantAnalytics.CategoryMonth(category: category, monthStart: $0.key, amount: $0.value) }
            .sorted { $0.monthStart < $1.monthStart }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = all.filter { txn in
            if !selectedMonths.isEmpty {
                guard let monthStart = calendar.dateInterval(of: .month, for: txn.date)?.start,
                      selectedMonths.contains(monthStart)
                else { return false }
            }
            if !query.isEmpty {
                return txn.title.localizedCaseInsensitiveContains(query)
                    || txn.name.localizedCaseInsensitiveContains(query)
            }
            return true
        }

        return Content(
            months: months,
            visible: sort(visible),
            total: visible.reduce(0) { $0 + $1.amount },
            isFiltered: !selectedMonths.isEmpty || !query.isEmpty
        )
    }

    private func sort(_ items: [TransactionRecord]) -> [TransactionRecord] {
        switch sortOrder {
        case .dateDesc: return items.sorted { $0.date > $1.date }
        case .dateAsc: return items.sorted { $0.date < $1.date }
        // By size, not by sign. Positive is money out and negative is money
        // in, so ordering on the raw value filed the largest refunds under
        // "Largest first" — the opposite of what the label promises.
        case .amountDesc: return items.sorted { abs($0.amount) > abs($1.amount) }
        case .amountAsc: return items.sorted { abs($0.amount) < abs($1.amount) }
        }
    }

    var body: some View {
        // Read once: every section below needs it, and recomputing per
        // reference would re-resolve a category for every transaction.
        list(content)
    }

    private func list(_ content: Content) -> some View {
        List {
            Section {
                summary(content)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if content.months.count > 1 {
                Section {
                    chart(content.months)
                } header: {
                    Text("Spend over time")
                } footer: {
                    Text(selectedMonths.isEmpty
                         ? "Tap a bar to see just that month."
                         : "Tap a highlighted bar to remove it.")
                }
            }

            if !selectedMonths.isEmpty {
                Section { selectedMonthsRow }
            }

            Section {
                ForEach(content.visible) { txn in
                    Button { detail = txn } label: {
                        TransactionRow(txn: txn, category: category)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            } header: {
                Text("\(content.visible.count) transaction\(content.visible.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.plain)
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search in \(category.displayName)"
        )
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu(content) }
        .animation(.default, value: selectedMonths)
        .overlay {
            if content.visible.isEmpty {
                ContentUnavailableView {
                    Label("Nothing here", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No \(category.displayName) transactions match these filters.")
                } actions: {
                    Button("Clear Filters") { clearFilters() }
                }
            }
        }
        .sheet(item: $detail) { txn in
            TransactionDetailView(txn: txn, currentCategory: category)
        }
    }

    // MARK: - Controls

    @ToolbarContentBuilder
    private func toolbarMenu(_ content: Content) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                // A submenu, not a bare Picker: this menu has other rows, and a
                // bare Picker draws its options expanded in place, which made
                // the menu open as one long list.
                Menu("Sort") {
                    Picker("Sort", selection: $sortOrder) {
                        // No icons: the picker draws its own checkmark against
                        // the selection, so an icon column would be a second,
                        // competing meaning in the same row.
                        ForEach(SortOrder.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }
                // A VoiceOver-reachable equivalent of tapping the bars, which
                // are not individually focusable.
                if content.months.count > 1 {
                    Menu("Months") {
                        // A toggle rather than a button with a swapped icon: the
                        // icon column cannot mean "this row is selected" and
                        // "this row is a month" at the same time.
                        ForEach(content.months) { month in
                            Toggle(
                                monthLabel(month.monthStart),
                                isOn: Binding(
                                    get: { selectedMonths.contains(month.monthStart) },
                                    set: { _ in toggle(month.monthStart) }
                                )
                            )
                        }
                    }
                }
                if content.isFiltered {
                    Divider()
                    Button(role: .destructive) { clearFilters() } label: {
                        Label("Clear Filters", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(systemName: content.isFiltered
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter and sort")
        }
    }

    private var selectedMonthsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedMonths.sorted(), id: \.self) { month in
                    Button { toggle(month) } label: {
                        HStack(spacing: 4) {
                            Text(monthLabel(month))
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(category.tint.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(monthLabel(month)) filter")
                }
                Button("Clear") { clearFilters() }
                    .font(.caption.weight(.medium))
            }
            .padding(.vertical, 2)
        }
    }

    private func summary(_ content: Content) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                statTile(title: "Transactions", value: "\(content.visible.count)")
                statTile(title: "Total", value: CurrencyFormatter.compact(content.total))
                statTile(
                    title: "Avg",
                    value: CurrencyFormatter.compact(
                        content.visible.isEmpty ? 0 : content.total / Double(content.visible.count)
                    )
                )
            }
            if content.isFiltered {
                Text("Filtered")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func chart(_ months: [MerchantAnalytics.CategoryMonth]) -> some View {
        Chart(months) { entry in
            BarMark(
                x: .value("Month", entry.monthStart, unit: .month),
                y: .value("Spent", entry.amount)
            )
            .foregroundStyle(category.tint)
            // Dim the months a filter is excluding, so the selection is
            // legible without changing the chart's shape.
            .opacity(selectedMonths.isEmpty || selectedMonths.contains(entry.monthStart) ? 1 : 0.25)
            .cornerRadius(4)
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let relativeX = location.x - geo[plotFrame].origin.x
                        guard let tapped: Date = proxy.value(atX: relativeX),
                              let monthStart = Calendar.current.dateInterval(of: .month, for: tapped)?.start,
                              months.contains(where: { $0.monthStart == monthStart })
                        else { return }
                        toggle(monthStart)
                    }
            }
        }
        .chartYAxis {
            AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
        }
        .frame(height: 160)
        .accessibilityLabel("Monthly \(category.displayName) spending")
        .accessibilityHint("Use the filter menu to pick months")
    }

    // MARK: - Actions

    private func toggle(_ monthStart: Date) {
        if selectedMonths.contains(monthStart) {
            selectedMonths.remove(monthStart)
        } else {
            selectedMonths.insert(monthStart)
        }
    }

    private func clearFilters() {
        selectedMonths = []
        search = ""
    }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).year())
    }
}
