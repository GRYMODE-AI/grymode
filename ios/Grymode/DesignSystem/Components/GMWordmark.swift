import SwiftUI

struct GMWordmark: View {
    var body: some View {
        Text("Grymode")
            .gmTextStyle(.wordmark)
            .foregroundStyle(GMColor.textPrimary)
            .accessibilityLabel("Grymode")
            .accessibilityAddTraits(.isHeader)
    }
}
