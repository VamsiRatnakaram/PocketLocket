import XCTest
import SwiftUI
@testable import BudgetApp

/// Renders the ring components with sample data using `ImageRenderer`, which
/// both verifies they build/lay out without crashing and produces PNGs in /tmp
/// for visual inspection.
final class UISnapshotTests: XCTestCase {

    private let sampleSpends: [CategorySpend] = [
        CategorySpend(category: .housing, amount: 1100),
        CategorySpend(category: .food, amount: 620),
        CategorySpend(category: .transport, amount: 210),
        CategorySpend(category: .entertainment, amount: 180),
        CategorySpend(category: .shopping, amount: 140),
    ]
    private let total: Double = 2250
    private let budget: Double = 3000

    @MainActor
    func testRenderDonutRing() {
        renderAndSave(
            SpendRingView(spends: sampleSpends, totalSpent: total, monthlyBudget: budget),
            name: "donut",
            size: CGSize(width: 320, height: 260)
        )
    }

    @MainActor
    func testRenderProgressRing() {
        renderAndSave(
            SpendRingProgress(totalSpent: total, monthlyBudget: budget),
            name: "progress",
            size: CGSize(width: 280, height: 280)
        )
    }

    @MainActor
    func testRenderProgressRingOverBudget() {
        renderAndSave(
            SpendRingProgress(totalSpent: 4200, monthlyBudget: budget),
            name: "progress_over",
            size: CGSize(width: 280, height: 280)
        )
    }

    @MainActor
    func testRenderHomeComposition() {
        let composition = VStack(spacing: 24) {
            SpendRingView(spends: sampleSpends, totalSpent: total, monthlyBudget: budget)
            CategoryBreakdownList(spends: sampleSpends, total: total)
                .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(width: 390)
        .background(Color(.systemBackground))

        renderAndSave(composition, name: "home", size: CGSize(width: 390, height: 720))
    }

    @MainActor
    func testRenderCategoryChips() {
        let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]
        let grid = LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(SpendCategory.allCases.enumerated()), id: \.element) { index, category in
                CategoryChip(category: category, isSelected: index == 0)
            }
        }
        .padding()
        .frame(width: 390)
        .background(Color(.systemBackground))

        renderAndSave(grid, name: "category_chips", size: CGSize(width: 390, height: 560))
    }

    @MainActor
    func testRenderBudgetBreakdown() {
        UserDefaults.standard.set(
            CategoryBudgetStore.encode([.food: 700, .housing: 900]),
            forKey: CategoryBudgetStore.key
        )
        defer { UserDefaults.standard.removeObject(forKey: CategoryBudgetStore.key) }

        let view = CategoryBreakdownList(spends: sampleSpends, total: total, showBudgets: true)
            .padding()
            .frame(width: 390)
            .background(Color(.systemBackground))

        renderAndSave(view, name: "budget_breakdown", size: CGSize(width: 390, height: 420))
    }

    // MARK: - Helper

    @MainActor
    private func renderAndSave<V: View>(_ view: V, name: String, size: CGSize) {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .background(Color(.systemBackground))
        )
        renderer.scale = 3

        guard let image = renderer.uiImage else {
            XCTFail("ImageRenderer produced no image for \(name)")
            return
        }
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)

        if let data = image.pngData() {
            let url = URL(fileURLWithPath: "/tmp/ring_\(name).png")
            try? data.write(to: url)
        }
    }
}
