import XCTest

@testable import Grymode

/// Guards WCAG 2.x contrast for every text/background pairing the design system uses.
final class ColorContrastTests: XCTestCase {
    private static let normalTextMinimum = 4.5

    func testContrastFormulaMatchesReferenceValues() {
        XCTAssertEqual(Palette.white.contrastRatio(against: RGBColor(hex: 0x000000)), 21, accuracy: 0.01)
        XCTAssertEqual(Palette.white.contrastRatio(against: Palette.white), 1, accuracy: 0.001)
        XCTAssertEqual(
            Palette.softBlack.contrastRatio(against: Palette.warmOffWhite),
            Palette.warmOffWhite.contrastRatio(against: Palette.softBlack),
            accuracy: 0.0001
        )
    }

    func testTextPairingsMeetAAForNormalText() {
        let pairings: [(name: String, foreground: RGBColor, background: RGBColor)] = [
            ("primary on background", Palette.softBlack, Palette.warmOffWhite),
            ("primary on surface", Palette.softBlack, Palette.paper),
            ("primary on sunken", Palette.softBlack, Palette.stone),
            ("primary on accent container", Palette.softBlack, Palette.oliveMist),
            ("secondary on background", Palette.graphite, Palette.warmOffWhite),
            ("secondary on surface", Palette.graphite, Palette.paper),
            ("secondary on sunken", Palette.graphite, Palette.stone),
            ("accent on background", Palette.deepOlive, Palette.warmOffWhite),
            ("accent on surface", Palette.deepOlive, Palette.paper),
            ("on-primary on primary action", Palette.warmOffWhite, Palette.softBlack),
            ("error on background", Palette.oxblood, Palette.warmOffWhite),
            ("error on surface", Palette.oxblood, Palette.paper),
        ]
        for pairing in pairings {
            let ratio = pairing.foreground.contrastRatio(against: pairing.background)
            XCTAssertGreaterThanOrEqual(
                ratio,
                Self.normalTextMinimum,
                "\(pairing.name) is \(String(format: "%.2f", ratio)):1"
            )
        }
    }

    func testMutedGreyIsNotSafeForBodyText() {
        // Documents why `textMuted` is reserved for decorative elements, never for information.
        XCTAssertLessThan(Palette.mutedGrey.contrastRatio(against: Palette.warmOffWhite), Self.normalTextMinimum)
    }
}
