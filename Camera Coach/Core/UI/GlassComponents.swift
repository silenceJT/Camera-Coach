//
//  GlassComponents.swift
//  Camera Coach
//
//  Liquid Glass UI components for iOS 26+ with graceful fallbacks.
//  Provides modern, translucent chrome components while keeping HUD content crisp.
//

import SwiftUI

// MARK: - Glass Container (Core Primitive)

/// Reusable glass wrapper using iOS 26 native .glassEffect() modifier
@available(iOS 26.0, *)
struct GlassContainer<S: Shape, Content: View>: View {
    let shape: S
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTrans
    @Environment(\.colorScheme) private var colorScheme

    init(in shape: S,
         @ViewBuilder content: @escaping () -> Content) {
        self.shape = shape
        self.content = content
    }

    var body: some View {
        // CRITICAL: Content must be SEPARATE from glass effect layer
        // Glass effect only applies to background, not foreground text
        ZStack {
            // Background layer with glass effect
            Group {
                if reduceTrans {
                    // Accessibility: Opaque background with higher contrast border
                    shape.fill(Color(uiColor: .systemBackground).opacity(0.95))
                        .overlay(
                            shape.stroke(
                                Color(uiColor: colorScheme == .dark ? .white : .black).opacity(0.3),
                                lineWidth: 1.0
                            )
                        )
                } else {
                    // ✅ iOS 26 REAL Liquid Glass using .glassEffect() modifier
                    shape.fill(.ultraThinMaterial)  // Use material as base for glass effect
                        .glassEffect(.regular.interactive())  // Apply glass effect ONLY to background
                }
            }

            // Foreground content layer (NOT affected by glass effect)
            content()
                .padding(12)
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
            Image(systemName: template.iconName)
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
            .clipShape(RoundedRectangle(cornerRadius: 18))  // Clip to wrapper shape
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
        // Use ZStack to separate glass background from text foreground
        ZStack {
            // Background layer with glass effect
            Capsule()
                .fill(.ultraThinMaterial)
                .glassEffect(.regular.interactive())

            // Foreground text layer (NOT affected by glass effect)
            Text(text)
                .font(.callout.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .fixedSize(horizontal: true, vertical: false)  // Let text determine width
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
    // NOTE: iconName removed - now loaded from templates.json per template

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
                        iconName: "person.fill",
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
                        iconName: "person.crop.rectangle.fill",
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