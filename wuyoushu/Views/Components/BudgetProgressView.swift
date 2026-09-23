import SwiftUI

struct BudgetProgressView: View {
    let categoryName: String
    let categoryEmoji: String
    let spent: Double
    let budget: Double

    private var progress: Double {
        guard budget > 0 else { return 0 }
        return min(spent / budget, 1.0)
    }

    private var progressColor: Color {
        let ratio = budget > 0 ? spent / budget : 0
        if ratio >= 1.0 { return .warmCoral }
        if ratio >= 0.8 { return .warningOrange }
        return .warmTeal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(categoryEmoji)
                    .font(.body)
                Text(categoryName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                if spent > budget {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.warmCoral)
                        .font(.system(size: 12))
                }
                Text("\(spent.currencyString) / \(budget.currencyString)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.warmMint)
                        .frame(height: 6)
                        .cornerRadius(3)

                    Rectangle()
                        .fill(progressColor)
                        .frame(width: geometry.size.width * CGFloat(progress), height: 6)
                        .cornerRadius(3)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        BudgetProgressView(categoryName: "餐饮", categoryEmoji: "🍽️", spent: 1200, budget: 2000)
        BudgetProgressView(categoryName: "交通", categoryEmoji: "🚗", spent: 400, budget: 500)
        BudgetProgressView(categoryName: "购物", categoryEmoji: "🛍️", spent: 3100, budget: 2000)
    }
    .padding()
}
