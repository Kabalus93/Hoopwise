import Foundation

// Plays strings written in Hoopwise, after the port. JournalPlayStrings is
// generated from the Journal's catalog and must not be hand-edited, so text
// the Journal never had lives here; `jp` reads the generated table first.
nonisolated enum JournalPlayStringsAdded {
    typealias Entry = JournalPlayStrings.Entry

    static let table: [String: Entry] = [
        "Click to select a player, a defender or a line; drag to move it, or the end or a bend of a line.":
            .init(en: "Click to select a player, a defender or a line; drag to move it, or the end or a bend of a line.",
                  enOne: nil, zh: "点击选中球员、防守人或线条；拖动可移动它，或拖动线的终点和弯折点。"),
        "Shot": .init(en: "Shot", enOne: nil, zh: "投篮"),
        "Drag from the shooter toward the basket; the line ends in the rim.":
            .init(en: "Drag from the shooter toward the basket; the line ends in the rim.", enOne: nil,
                  zh: "从投篮的球员向篮筐拖动；线会停在篮筐上。"),
        "Shot by %lld": .init(en: "Shot by %lld", enOne: nil, zh: "%lld 号投篮"),
        "Shot (a drive to the basket is red too)": .init(en: "Shot (a drive to the basket is red too)", enOne: nil,
                                                          zh: "投篮（运球突破到篮下也是红色）"),
        "Steps": .init(en: "Steps", enOne: nil, zh: "步骤"),
        "Its drawing and notes go with it. Cancel brings it back until you press Done.":
            .init(en: "Its drawing and notes go with it. Cancel brings it back until you press Done.", enOne: nil,
                  zh: "这一步的图和说明会一起删除。按“完成”之前，点“取消”可以恢复。"),
        "Discard your changes to these steps?": .init(en: "Discard your changes to these steps?", enOne: nil,
                                                       zh: "放弃对这些步骤的修改？"),
        "This step": .init(en: "This step", enOne: nil, zh: "这一步"),
        "Keyboard shortcuts": .init(en: "Keyboard shortcuts", enOne: nil, zh: "键盘快捷键"),
        "Tools": .init(en: "Tools", enOne: nil, zh: "工具"),
        "Delete the selection": .init(en: "Delete the selection", enOne: nil, zh: "删除所选"),
        "Nudge (⇧ for more)": .init(en: "Nudge (⇧ for more)", enOne: nil, zh: "微移（按住 ⇧ 移得更多）"),
        "Deselect": .init(en: "Deselect", enOne: nil, zh: "取消选择"),
        "Undo and redo": .init(en: "Undo and redo", enOne: nil, zh: "撤销和重做"),
        "Player %lld": .init(en: "Player %lld", enOne: nil, zh: "%lld 号球员"),
        "Has a ball": .init(en: "Has a ball", enOne: nil, zh: "持球"),
        "Erase their lines": .init(en: "Erase their lines", enOne: nil, zh: "擦掉他的线"),
        "The one to read": .init(en: "The one to read", enOne: nil, zh: "要读的防守人"),
        "Pass from %lld to %lld": .init(en: "Pass from %lld to %lld", enOne: nil, zh: "%1$lld 传给 %2$lld"),
        "Line by %lld": .init(en: "Line by %lld", enOne: nil, zh: "%lld 号的线"),
        "Kind": .init(en: "Kind", enOne: nil, zh: "类型"),
        "Drag the dots on the line to shape it.": .init(en: "Drag the dots on the line to shape it.", enOne: nil, zh: "拖动线上的圆点来调整形状。"),
        "Straight": .init(en: "Straight", enOne: nil, zh: "直线"),
        "Curved": .init(en: "Curved", enOne: nil, zh: "曲线"),
        "Line": .init(en: "Line", enOne: nil, zh: "线条"),
        "Drag a player, a defender, the end of a line or a bend. Tap a line to make it straight or curved.":
            .init(en: "Drag a player, a defender, the end of a line or a bend. Tap a line to make it straight or curved.",
                  enOne: nil, zh: "拖动球员、防守人、线的终点或弯折点。点一下线条可在直线和曲线之间切换。"),
        "Edit steps": .init(en: "Edit steps", enOne: nil, zh: "编辑步骤"),
        "Tap a player to give or take a ball. Several players can each have one.":
            .init(en: "Tap a player to give or take a ball. Several players can each have one.", enOne: nil,
                  zh: "点一下球员给球或收回球。可以让几名球员各拿一个球。"),
        // Drill drawings (November 2026): players and cones.
        "Player": .init(en: "Player", enOne: nil, zh: "球员"),
        "Cone": .init(en: "Cone", enOne: nil, zh: "标志桶"),
        "Tap the court to add a player.": .init(en: "Tap the court to add a player.", enOne: nil,
                                                zh: "点一下球场，添加一名球员。"),
        "Tap the court to add a cone.": .init(en: "Tap the court to add a cone.", enOne: nil,
                                              zh: "点一下球场，放一个标志桶。"),
        "Tap a player, a line, a defender, a cone or a note to erase it.":
            .init(en: "Tap a player, a line, a defender, a cone or a note to erase it.", enOne: nil,
                  zh: "点一下球员、线条、防守人、标志桶或文字即可擦掉。"),
        "Click to select a player, a defender, a cone or a line; drag to move it, or the end or a bend of a line.":
            .init(en: "Click to select a player, a defender, a cone or a line; drag to move it, or the end or a bend of a line.",
                  enOne: nil, zh: "点击选中球员、防守人、标志桶或线条；拖动可移动它，或拖动线的终点和弯折点。"),
    ]
}
