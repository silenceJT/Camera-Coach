//
//  GlassComponents.swift
//  Camera Coach
//
//  Liquid Glass UI components for iOS 26+ with graceful fallbacks.
//  Provides modern, translucent chrome components while keeping HUD content crisp.
//

import SwiftUI

// MARK: - Glass Container (Core Primitive)

/// Reusable glass wrapper using iOS native materials (iOS 26+ optimized)
@available(iOS 26.0, *)
struct GlassContainer<S: Shape, Content: View>: View {
    let shape: S
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTrans

    init(in shape: S,
         displayMode: String = "automatic",  // Placeholder for future API
         @ViewBuilder content: @escaping () -> Content) {
        self.shape = shape
        self.content = content
    }

    var body: some View {
        content()
            .padding(12)
            .background {
                if reduceTrans {
                    shape.fill(Color(uiColor: .systemBackground))
                } else {
                    // iOS 26 native camera-style glass using .ultraThinMaterial
                    shape.fill(.ultraThinMaterial)
                }
            }
            .clipShape(shape)
    }
}

// MARK: - Glass Card (Individual Template Button)

/// Individual template card with glass effect
@available(iOS 26.0, *)
struct GlassCard: View {
    let template: Template
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: template.category.iconName)
                .font(.body)
                .foregroundStyle(.primary)

            Text(template.category.shortDisplayName)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .frame(width: Config.glassCardWidth, height: Config.glassCardHeight)
        .background {
            RoundedRectangle(cornerRadius: Config.glassCardCornerRadius)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Config.glassCardCornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
    }
}

// MARK: - Category Pill Bar

/// Horizontal scroll view of category filter pills
@available(iOS 26.0, *)
struct CategoryPillBar: View {
    let categories: [TemplateCategory?]
    @Binding var selectedCategory: TemplateCategory?

    init(selectedCategory: Binding<TemplateCategory?>) {
        self.categories = [nil] + TemplateCategory.allCases.map { $0 as TemplateCategory? }
        self._selectedCategory = selectedCategory
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories.indices, id: \.self) { index in
                    CategoryPill(
                        category: categories[index],
                        isSelected: categories[index] == selectedCategory
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: Config.glassSpringResponse, dampingFraction: Config.glassSpringDamping)) {
                            selectedCategory = categories[index]
                        }

                        // Haptic feedback
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

/// Individual category filter pill
@available(iOS 26.0, *)
struct CategoryPill: View {
    let category: TemplateCategory?
    let isSelected: Bool

    var body: some View {
        Text(category?.shortDisplayName ?? "All")
            .font(.caption.weight(.medium))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }
            .contentShape(Capsule())
    }
}

// MARK: - Glass Shelf (Template Carousel)

/// Horizontal template carousel with glass background
@available(iOS 26.0, *)
struct GlassShelf: View {
    let templates: [Template]
    @Binding var selectedID: String?
    @Binding var selectedCategory: TemplateCategory?

    var body: some View {
        VStack(spacing: 8) {
            // Category Filter Pills
            CategoryPillBar(selectedCategory: $selectedCategory)

            // Template Cards Carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Config.glassCardSpacing) {
                    ForEach(filteredTemplates) { template in
                        GlassCard(
                            template: template,
                            isSelected: template.id == selectedID
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedID == template.id {
                                    selectedID = nil
                                } else {
                                    selectedID = template.id
                                }
                            }

                            let impact = UIImpactFeedbackGenerator(style: .soft)
                            impact.impactOccurred()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var filteredTemplates: [Template] {
        guard let category = selectedCategory else { return templates }
        return templates.filter { $0.category == category }
    }
}

// MARK: - Glass Pill (Transient Guidance Hint)

/// Transient guidance hint with glass capsule background
@available(iOS 26.0, *)
struct GlassPill: View {
    let text: String

    var body: some View {
        GlassContainer(
            in: Capsule(),
            displayMode: "always"
        ) {
            Text(text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
        .shadow(
            color: .black.opacity(0.1),
            radius: Config.glassShadowRadius,
            y: Config.glassShadowOffsetY
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// MARK: - Glass Shelf Wrapper (UIKit Bridge)

/// Wrapper for GlassShelf to bridge UIKit → SwiftUI with proper state management
@available(iOS 26.0, *)
struct GlassShelfWrapper: View {
    let templates: [Template]
    let onTemplateSelected: (Template?) -> Void
    let onCategorySelected: (TemplateCategory?) -> Void

    @State private var selectedID: String?
    @State private var selectedCategory: TemplateCategory?

    var body: some View {
        GlassShelf(
            templates: templates,
            selectedID: $selectedID,
            selectedCategory: $selectedCategory
        )
        .onChange(of: selectedID) { oldValue, newValue in
            let template = templates.first { $0.id == newValue }
            onTemplateSelected(template)
        }
        .onChange(of: selectedCategory) { oldValue, newValue in
            onCategorySelected(newValue)
        }
    }
}

// MARK: - Template Category Extensions

extension TemplateCategory {
    var iconName: String {
        switch self {
        case .full_body: return "person.fill"
        case .half_body: return "person.crop.rectangle.fill"
        case .close_up: return "person.crop.circle.fill"
        case .couple: return "person.2.fill"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .full_body: return "Full"
        case .half_body: return "Half"
        case .close_up: return "Close"
        case .couple: return "Couple"
        }
    }
}

// MARK: - Preview Support

#if DEBUG
@available(iOS 26.0, *)
struct GlassComponents_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Glass Pill Preview
            GlassPill(text: "Align to silhouette")

            // Category Pill Bar Preview
            CategoryPillBar(selectedCategory: .constant(.half_body))

            // Glass Card Preview
            HStack(spacing: 10) {
                GlassCard(
                    template: Template(
                        id: "preview_full",
                        category: .full_body,
                        description: "Full body preview",
                        orientation: .portrait,
                        headAnchorRect: CGRect(x: 0.3, y: 0.1, width: 0.4, height: 0.3),
                        headroomRangePct: HeadroomRange(min: 7, max: 12),
                        horizonToleranceDeg: 3,
                        flipAllowed: true,
                        aspectVariants: ["4:3"]
                    ),
                    isSelected: false
                )

                GlassCard(
                    template: Template(
                        id: "preview_half",
                        category: .half_body,
                        description: "Half body preview",
                        orientation: .portrait,
                        headAnchorRect: CGRect(x: 0.3, y: 0.15, width: 0.4, height: 0.35),
                        headroomRangePct: HeadroomRange(min: 7, max: 12),
                        horizonToleranceDeg: 3,
                        flipAllowed: true,
                        aspectVariants: ["4:3"]
                    ),
                    isSelected: true
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.3))
        .previewLayout(.sizeThatFits)
    }
}
#endif