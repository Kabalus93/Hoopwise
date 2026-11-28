import SwiftUI

// CHOOSING A TEMPLATE (28 Nov 2026, Luther: "make the selector of templates
// less annoying to use, right now scrolling like that is a pain. having them
// all displayed at once would be messy too"). The strip of fourteen chips is
// gone. Now: SWIPE the preview left / right for the next one; a bar under it
// says which one it is ("Torn paper · 14 of 14") between ‹ ›; a tap on the
// name opens a GRID of every template drawn small with the real photo and
// numbers, so the coach picks by looking, not by reading names.

/// Swipe left / right on the preview to change template.
struct PostSwipe: ViewModifier {
    let count: Int
    @Binding var index: Int
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > 60,
                          abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    withAnimation(.snappy) {
                        index = (index + (value.translation.width < 0 ? 1 : -1) + count) % count
                    }
                }
        )
    }
}

/// ‹ name · n of m ▾ › — the name opens the grid.
struct PostTemplateBar<Item: Hashable, Thumb: View>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let symbol: (Item) -> String
    /// One template drawn small (the grid scales it down).
    @ViewBuilder let thumbnail: (Item) -> Thumb
    var thumbnailAspect: CGFloat = 4.0 / 5.0
    @State private var showingGrid = false

    private var index: Int { items.firstIndex(of: selection) ?? 0 }

    var body: some View {
        HStack(spacing: 10) {
            step(-1, icon: "chevron.left").accessibilityIdentifier("post.template.previous")
            Button { showingGrid = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol(selection))
                    Text(title(selection)).fontWeight(.semibold).lineLimit(1)
                    Text("\(index + 1)/\(items.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    Image(systemName: "square.grid.2x2").font(.footnote.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("post.template.all")
            step(1, icon: "chevron.right").accessibilityIdentifier("post.template.next")
        }
        .sheet(isPresented: $showingGrid) {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 16) {
                        ForEach(items, id: \.self) { item in
                            let on = item == selection
                            Button {
                                selection = item
                                showingGrid = false
                            } label: {
                                VStack(spacing: 6) {
                                    Color.clear
                                        .aspectRatio(thumbnailAspect, contentMode: .fit)
                                        .overlay { thumbnail(item) }
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: on ? 3 : 1))
                                    Label(title(item), systemImage: symbol(item))
                                        .font(.footnote.weight(on ? .semibold : .regular))
                                        .foregroundStyle(on ? Color.accentColor : Color.primary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("post.template.grid.\(items.firstIndex(of: item) ?? 0)")
                        }
                    }
                    .padding()
                }
                .navigationTitle(LocalizationManager.shared.currentLanguage == .chinese ? "选择模板" : "Templates")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LocalizationManager.shared.currentLanguage == .chinese ? "完成" : "Done") { showingGrid = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    private func step(_ by: Int, icon: String) -> some View {
        Button {
            withAnimation(.snappy) { selection = items[(index + by + items.count) % items.count] }
        } label: {
            Image(systemName: icon).font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }
}

/// A post canvas (drawn at its full size) scaled to whatever frame it is given.
struct ScaledPost<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)
            content()
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
