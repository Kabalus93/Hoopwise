//
//  MacSettingsForm.swift
//  Hoopwise
//
//  HAND-DRAWN MAC ROWS FOR SETTINGS (26 Nov 2026, Luther: the Settings
//  window still had the iPad's rounded cards and big switch inside).
//  The Mac app runs with iPad-style system controls, so a `Form` there is
//  always the iPad's. This container takes the SAME `Section`s the phone's
//  Form takes and draws them the way System Settings does: a small caption
//  over a quiet box, 34 pt rows split by hairlines, a small switch, pop-up
//  menus, the footnote under the box. iPhone and iPad keep their Form.
//

import SwiftUI

struct MacSettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(sections: content) { section in
                    VStack(alignment: .leading, spacing: 7) {
                        if !section.header.isEmpty {
                            section.header
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                                .textCase(nil)
                                .padding(.leading, 4)
                        }
                        VStack(spacing: 0) {
                            ForEach(subviews: section.content) { row in
                                row
                                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                                    .padding(.horizontal, 14).padding(.vertical, 3)
                                    .overlay(alignment: .top) {
                                        if row.id != section.content.first?.id {
                                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                                .padding(.leading, 14)
                                        }
                                    }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.055)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                        if !section.footer.isEmpty {
                            section.footer
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        }
                    }
                }
            }
            .font(.system(size: 16))
            .toggleStyle(MacSwitchToggleStyle())
            .labelStyle(MacSettingsLabelStyle())
            .controlSize(.small)
            .tint(.accentColor)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

/// A row's label: a small quiet symbol, then the words.
struct MacSettingsLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 9) {
            configuration.icon
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            configuration.title
        }
    }
}

/// The Mac's small switch, drawn here: the words on the left, a 38 × 22
/// switch on the right; the whole row is not the target, only the switch.
struct MacSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            Button {
                withAnimation(.snappy(duration: 0.16)) { configuration.isOn.toggle() }
            } label: {
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.white.opacity(0.18))
                    .frame(width: 38, height: 22)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                            .padding(2)
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
        }
    }
}

extension View {
    /// A settings row that leads somewhere: on the Mac the words, a spacer and
    /// a small chevron (a NavigationLink outside a List draws none).
    func macSettingsLinkLabel() -> some View {
        HStack(spacing: 8) {
            // On the Mac a row that leads somewhere reads like the others, not as a blue link.
            if FilmRoom.isOn { self.foregroundStyle(.white.opacity(0.92)) } else { self }
            if FilmRoom.isOn {
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .contentShape(Rectangle())
    }
}

/// A settings row with a choice: on the Mac the words on the left and a
/// pop-up menu on the right (a Picker outside a List shows only its value);
/// in a Form the system's own picker row.
struct SettingsPickerRow<Selection: Hashable, Options: View>: View {
    let title: String
    let systemImage: String
    @Binding var selection: Selection
    @ViewBuilder var options: Options

    var body: some View {
        if FilmRoom.isOn {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 12)
                Picker(title, selection: $selection) { options }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(.white.opacity(0.9))
            }
        } else {
            Picker(selection: $selection) { options } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }
}
