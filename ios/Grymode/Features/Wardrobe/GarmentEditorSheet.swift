import SwiftUI

/// Lets the user set a category (required before confirm) and remove a draft piece.
struct GarmentEditorSheet: View {
    let garment: WardrobeGarment
    @Bindable var model: WardrobeModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: GarmentCategory
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var error: AppError?
    @ScaledMetric(relativeTo: .callout) private var minimumChipWidth: CGFloat = 140

    init(garment: WardrobeGarment, model: WardrobeModel) {
        self.garment = garment
        self.model = model
        _selected = State(initialValue: garment.category == .uncategorised ? .tops : garment.category)
    }

    var body: some View {
        NavigationStack {
            AdaptiveScrollScreen(accessibilityIdentifier: "screen.garmentEditor") { _ in
                VStack(alignment: .leading, spacing: GMSpacing.xl) {
                    GMSectionHeader(
                        overline: overline,
                        title: garment.needsLabel ? "What is this?" : garment.displayName,
                        message: headerMessage
                    )

                    preview

                    if !garment.detectedDetails.isEmpty {
                        detectedDetails
                    }

                    VStack(alignment: .leading, spacing: GMSpacing.sm) {
                        Text("Category")
                            .gmTextStyle(.subheadline)
                            .foregroundStyle(GMColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        FlowChoiceChips(
                            options: GarmentCategory.labelChoices,
                            selection: $selected,
                            minimumWidth: minimumChipWidth
                        )
                    }

                    if let error {
                        GMInlineError(error: error)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                GMBottomActionBar {
                    Button {
                        Task { await save() }
                    } label: {
                        GMProgressLabel(title: "Save category", isWorking: isSaving)
                    }
                    .buttonStyle(.gmPrimary)
                    .disabled(isSaving || isDeleting)
                    .accessibilityIdentifier("garmentEditor.save")

                    Button(role: .destructive) {
                        Task { await remove() }
                    } label: {
                        GMProgressLabel(title: "Remove piece", isWorking: isDeleting)
                    }
                    .buttonStyle(.gmDestructive)
                    .disabled(isSaving || isDeleting)
                    .accessibilityIdentifier("garmentEditor.delete")
                }
            }
            .navigationTitle("Piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving || isDeleting)
                }
            }
            .interactiveDismissDisabled(isSaving || isDeleting)
        }
    }

    private var overline: String {
        if garment.needsLabel { return "Needs a label" }
        return garment.userConfirmed ? "Edit piece" : "Check details"
    }

    private var headerMessage: String {
        if garment.needsLabel {
            return "Grymode couldn't identify this piece. Pick a category before you confirm it."
        }
        if !garment.userConfirmed {
            return "Grymode suggested these details from your photo. Fix the category if it's wrong, or remove the piece."
        }
        return "Update the category, or remove the piece from your wardrobe."
    }

    private var detectedDetails: some View {
        VStack(alignment: .leading, spacing: GMSpacing.xs) {
            Text("Detected details")
                .gmTextStyle(.subheadline)
                .foregroundStyle(GMColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(garment.detectedDetails.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: GMSpacing.sm) {
                    Text(row.label)
                        .gmTextStyle(.callout)
                        .foregroundStyle(GMColor.textSecondary)
                        .frame(minWidth: 88, alignment: .leading)
                    Text(row.value.prefix(1).uppercased() + row.value.dropFirst())
                        .gmTextStyle(.callout)
                        .foregroundStyle(GMColor.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gmCard(padding: GMSpacing.md)
        .accessibilityIdentifier("garmentEditor.details")
    }

    private var preview: some View {
        Group {
            if let url = URL(string: garment.imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(GMColor.textSecondary)
                    case .empty:
                        ProgressView().tint(GMColor.accent)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(GMColor.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous)
                .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
        )
        .accessibilityHidden(true)
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do throws(AppError) {
            try await model.updateCategory(garmentId: garment.id, category: selected)
            dismiss()
        } catch {
            self.error = error
        }
    }

    private func remove() async {
        isDeleting = true
        error = nil
        defer { isDeleting = false }
        do throws(AppError) {
            try await model.deleteGarment(id: garment.id)
            dismiss()
        } catch {
            self.error = error
        }
    }
}

private struct FlowChoiceChips: View {
    let options: [GarmentCategory]
    @Binding var selection: GarmentCategory
    let minimumWidth: CGFloat

    var body: some View {
        FlexibleChipWrap(spacing: GMSpacing.sm) {
            ForEach(options) { option in
                GMChoiceChip(title: option.title, isSelected: selection == option) {
                    selection = option
                }
                .frame(minWidth: minimumWidth)
            }
        }
    }
}

/// Simple wrapping layout for category chips without pulling in extra dependencies.
private struct FlexibleChipWrap: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (
        size: CGSize, origins: [CGPoint], sizes: [CGSize]
    ) {
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), origins, sizes)
    }
}
