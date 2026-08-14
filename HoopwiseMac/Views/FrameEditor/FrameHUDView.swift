import SwiftUI

/// The context HUD — Motion's pattern in Apple dress.
///
/// A selection summons a small translucent panel AT the selection: what this
/// thing is, what you can do to it, and what gestures it answers to. Two jobs
/// in one surface, and the second is the one that mattered in the hand test —
/// ⌥-drag and the screen tool existed only in a palette you had to go looking
/// in, so they never announced themselves.
///
/// It replaces an inspector column rather than joining one. Nothing here needs
/// multi-field precision, so nothing here is a form.
struct FrameHUDView: View {
    @ObservedObject var model: FrameEditorModel
    let subject: FrameEditorModel.HUDSubject

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if case .action(let id) = subject, let action = model.selectedAction,
               action.id == id {
                actionControls(action)
            }
            hints
        }
        .padding(10)
        .frame(width: 208, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if case .action = subject {
                Button {
                    model.deleteSelectedAction()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete this action (⌫)")
            }
        }
    }

    private var icon: String {
        switch subject {
        case .entity: return "person.fill"
        case .action:
            switch model.selectedAction?.kind {
            case .pass:    return "arrow.forward"
            case .shot:    return "basketball.fill"
            case .screen:  return "rectangle.compress.vertical"
            case .dribble: return "figure.basketball"
            default:       return "arrow.up.right"
            }
        }
    }

    private var title: String {
        switch subject {
        case .entity(let id):
            return model.label(of: id)
        case .action:
            guard let action = model.selectedAction else { return "Action" }
            return action.kind.displayName
        }
    }

    // MARK: - Action controls

    @ViewBuilder
    private func actionControls(_ action: PlayAction) -> some View {
        // DERIVED TIME, shown because nothing lets you type it — this is the
        // number a coach would otherwise wonder about.
        HStack(spacing: 4) {
            Text(String(format: "%.2fs", model.duration(of: action)))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text("derived from distance ÷ pace")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }

        if action.movesActor {
            Picker("", selection: Binding(
                get: { action.pace ?? action.effectiveTier },
                set: { model.setPace($0, for: action.id) })) {
                Text("Walk").tag(PaceTier.walk)
                Text("Cut").tag(PaceTier.cut)
                Text("Sprint").tag(PaceTier.sprint)
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()
        }

        if action.kind == .pass || action.kind == .shot {
            Button {
                model.convertSelectedFlight()
            } label: {
                Label(action.kind == .shot ? "Convert to Pass" : "Convert to Shot",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Hints

    private var hints: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.gestureHints(for: subject), id: \.self) { hint in
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// First-use coach marks: the three gestures the whole editor is built on,
/// stated once on the canvas rather than waiting in a palette.
///
/// Dismissed for good with the ×, and brought back by the ? in the palette —
/// so it is a reminder, not a wall.
struct FrameCoachMarks: View {
    @AppStorage("frameEditor.hintsDismissed") private var dismissed = false
    var forceShow: Bool
    var onDismiss: () -> Void

    var body: some View {
        if !dismissed || forceShow {
            HStack(spacing: 14) {
                hint("hand.draw", "Drag a player", "cut")
                hint("option", "⌥-drag a player", "screen")
                hint("basketball.fill", "Drag the ball", "pass or shot")
                Button {
                    dismissed = true
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Hide these hints")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.07)) }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }

    private func hint(_ symbol: String, _ gesture: String, _ result: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
            Text(gesture).font(.system(size: 10, weight: .medium))
            Image(systemName: "arrow.right")
                .font(.system(size: 7))
                .foregroundStyle(.tertiary)
            Text(result).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
