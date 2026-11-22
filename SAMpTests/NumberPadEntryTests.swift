import Testing
@testable import Hoopwise

/// The floating number pad's typing rules (23 Nov 2026).
struct NumberPadEntryTests {
    @Test func theFirstKeyReplacesThenKeysAppend() {
        var e = NumberPadEntry(text: "", maximum: 20)
        e.reset(to: 7)
        e.press("1"); #expect(e.text == "1")
        e.press("2"); #expect(e.text == "12")
        e.delete(); #expect(e.text == "1")
        e.reset(to: 5)
        e.press("3"); #expect(e.text == "3", "a value set from outside is replaced by the next key")
    }

    @Test func pastTheTopStartsAgainAndNoLeadingZeros() {
        var e = NumberPadEntry(text: "", maximum: 20)
        e.press("1"); e.press("5"); #expect(e.text == "15")
        e.press("3"); #expect(e.text == "3", "153 is past 20: start again from 3")
        var small = NumberPadEntry(text: "", maximum: 5)
        small.press("8"); #expect(small.text == "", "a key past the top alone is ignored")
        var z = NumberPadEntry(text: "")
        z.press("0"); z.press("4"); #expect(z.text == "4")
    }

    @Test func decimalsOnlyWhenAsked() {
        var money = NumberPadEntry(text: "", decimals: 2)
        money.press("1"); money.press("."); money.press("5"); money.press("0"); money.press("9")
        #expect(money.text == "1.50" && money.value == 1.5, "two decimals at most")
        var whole = NumberPadEntry(text: "")
        whole.press("3"); whole.press("."); #expect(whole.text == "3")
        #expect(NumberPadEntry.format(250, decimals: 2) == "250")
        #expect(NumberPadEntry.format(12.5, decimals: 2) == "12.5")
    }
}
