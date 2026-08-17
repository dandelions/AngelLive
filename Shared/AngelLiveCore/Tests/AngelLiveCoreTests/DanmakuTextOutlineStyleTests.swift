import CoreGraphics
import Testing
@testable import AngelLiveCore

@Suite("Danmaku text outline style")
struct DanmakuTextOutlineStyleTests {

    @Test("keeps the outline at three physical pixels across Retina scales")
    func physicalStrokeWidthIsStable() {
        let fontSize: CGFloat = 16
        let at2x = DanmakuTextOutlineStyle.strokePercentage(fontSize: fontSize, screenScale: 2)
        let at3x = DanmakuTextOutlineStyle.strokePercentage(fontSize: fontSize, screenScale: 3)

        #expect(abs(at2x - (-9.375)) < 0.001)
        #expect(abs(at3x - (-6.25)) < 0.001)
    }

    @Test("uses a white outline only for nearly black text")
    func contrastingOutlineColor() {
        let dark = DanmakuTextOutlineStyle.outlineColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 0.7)
        let bright = DanmakuTextOutlineStyle.outlineColor(red: 1, green: 1, blue: 1, alpha: 0.7)

        #expect(components(of: dark) == RGBA(red: 1, green: 1, blue: 1, alpha: 0.7))
        #expect(components(of: bright) == RGBA(red: 0, green: 0, blue: 0, alpha: 0.7))
    }

    private func components(of color: DanmakuColor) -> RGBA {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let converted = color.danmakuGetRGBA(&red, &green, &blue, &alpha)
        #expect(converted)
        return RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    private struct RGBA: Equatable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }
}
