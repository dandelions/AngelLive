import Foundation

enum DanmakuTextDrawing {
    nonisolated static func draw(
        _ text: String,
        font: DanmakuFont,
        color: DanmakuColor,
        at point: CGPoint
    ) {
        guard !text.isEmpty else { return }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        if !color.danmakuGetRGBA(&red, &green, &blue, &alpha) {
            red = 1
            green = 1
            blue = 1
            alpha = 1
        }

        let strokePercentage = DanmakuTextOutlineStyle.strokePercentage(
            fontSize: font.pointSize,
            screenScale: danmakuScreenScale()
        )
        let outlineColor = DanmakuTextOutlineStyle.outlineColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
        let value = NSString(string: text)
        value.draw(
            at: point,
            withAttributes: [
                .font: font,
                .foregroundColor: outlineColor,
                .strokeColor: outlineColor,
                .strokeWidth: strokePercentage
            ]
        )
        value.draw(
            at: point,
            withAttributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }
}
