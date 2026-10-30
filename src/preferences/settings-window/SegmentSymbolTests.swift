import XCTest

final class SegmentSymbolTests: XCTestCase {
    func testSymbolSpacingWithRoomToSpare() {
        let spacing = SegmentSymbol.spacing(glyphWidth: 15, labelWidth: 40, availableWidth: 105)
        XCTAssertEqual(spacing.before, SegmentSymbol.margin)
        XCTAssertEqual(spacing.after, SegmentSymbol.margin + SegmentSymbol.extraGap)
    }

    /// Arabic "Hold" (86.8pt beside a 15pt glyph in a 105pt segment) fit before the spacing existed;
    /// it must not start truncating because of it.
    func testSymbolSpacingNeverExceedsSlack() {
        let spacing = SegmentSymbol.spacing(glyphWidth: 15, labelWidth: 86.8, availableWidth: 104.5)
        XCTAssertLessThanOrEqual(15 + spacing.before + spacing.after + SegmentSymbol.appKitGap + 86.8, 104.5 + 0.001)
        XCTAssertLessThanOrEqual(spacing.before, spacing.after)
    }

    func testSymbolSpacingIsZeroForLabelsThatAlreadyTruncate() {
        let spacing = SegmentSymbol.spacing(glyphWidth: 15, labelWidth: 120, availableWidth: 105)
        XCTAssertEqual(spacing.before, 0)
        XCTAssertEqual(spacing.after, 0)
    }
}
