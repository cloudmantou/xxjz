import SwiftUI

struct FundAccountPickerView: View {
    @Binding var selectedKey: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FundAccount.all) { account in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedKey = selectedKey == account.key ? nil : account.key
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(account.emoji)
                                .font(.system(size: 14))
                            Text(account.name)
                                .font(.system(size: 12, weight: selectedKey == account.key ? .semibold : .regular))
                        }
                        .foregroundColor(selectedKey == account.key ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedKey == account.key ? Color.warmTeal : Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
