import SwiftUI
import UIKit

/// A text editor on ruled paper (14 November 2026, Luther: "have lines like a
/// notebook"). The rules sit under each line of text — the pitch is the body
/// font's line height plus the editor's line spacing, starting at the text
/// view's top inset — with a faint margin line on the left. The editor grows
/// with its text (no inner scrolling), so the rules never drift from the
/// writing; the page around it scrolls.
struct RuledNotebookEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var marginColor: Color = .accentColor
    var minHeight: CGFloat = 280

    /// UITextView's default text container inset.
    private let topInset: CGFloat = 8
    private let lineSpacing: CGFloat = 8
    /// Where the margin rule sits, and where writing starts after it.
    private let margin: CGFloat = 34

    private var lineHeight: CGFloat { UIFont.preferredFont(forTextStyle: .body).lineHeight }
    private var pitch: CGFloat { lineHeight + lineSpacing }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body)
                .lineSpacing(lineSpacing)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .padding(.leading, margin + 4)
                .padding(.trailing, 14)
                .frame(minHeight: minHeight, alignment: .topLeading)

            if text.isEmpty && !placeholder.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, margin + 9)
                    .padding(.top, topInset)
                    .allowsHitTesting(false)
            }
        }
        .background(rules)
    }

    private var rules: some View {
        Canvas { context, size in
            var y = topInset + lineHeight + 3
            var path = Path()
            while y < size.height - 2 {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += pitch
            }
            context.stroke(path, with: .color(.primary.opacity(0.09)), lineWidth: 0.6)
            var marginPath = Path()
            marginPath.move(to: CGPoint(x: margin, y: 0))
            marginPath.addLine(to: CGPoint(x: margin, y: size.height))
            context.stroke(marginPath, with: .color(marginColor.opacity(0.35)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
