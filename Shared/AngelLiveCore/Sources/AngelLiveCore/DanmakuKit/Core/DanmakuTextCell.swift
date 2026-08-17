//
//  DanmakuTextCell.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2020/8/29.
//

import Foundation
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public class DanmakuTextCell: DanmakuCell {
    required init(frame: CGRect) {
        super.init(frame: frame)
        danmakuBackgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func willDisplay() {}

    nonisolated public override func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {
        guard let model = model as? DanmakuTextCellModel else { return }

        let text = model.text
        guard !text.isEmpty else { return }
        let nsText = NSString(string: text)
        let drawPoint = CGPoint(x: 25, y: 5)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        if !model.color.danmakuGetRGBA(&red, &green, &blue, &alpha) {
            red = 1
            green = 1
            blue = 1
            alpha = 1
        }

        // DanmakuFlameMaster 默认使用 3px FILL_AND_STROKE 后再覆盖正文。
        // NSAttributedString 的 strokeWidth 单位是字号百分比,因此先把 3 个物理像素
        // 换算成点,再换算成百分比。负值表示同时填充和描边。
        let strokePercentage = DanmakuTextOutlineStyle.strokePercentage(
            fontSize: model.font.pointSize,
            screenScale: danmakuScreenScale()
        )
        let outlineColor = DanmakuTextOutlineStyle.outlineColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )

        let outlineAttributes: [NSAttributedString.Key: Any] = [
            .font: model.font,
            .foregroundColor: outlineColor,
            .strokeColor: outlineColor,
            .strokeWidth: strokePercentage
        ]
        nsText.draw(at: drawPoint, withAttributes: outlineAttributes)

        let fillAttributes: [NSAttributedString.Key: Any] = [
            .font: model.font,
            .foregroundColor: model.color
        ]
        nsText.draw(at: drawPoint, withAttributes: fillAttributes)
    }

    public override func didDisplay(_ finished: Bool) {}
}

enum DanmakuTextOutlineStyle {
    /// Bilibili DanmakuFlameMaster 示例使用 3px 描边。
    static let physicalStrokeWidth: CGFloat = 3

    static func strokePercentage(fontSize: CGFloat, screenScale: CGFloat) -> CGFloat {
        let safeFontSize = max(fontSize, 1)
        let safeScale = max(screenScale, 1)
        let strokeWidthInPoints = physicalStrokeWidth / safeScale
        return -(strokeWidthInPoints / safeFontSize * 100)
    }

    static func outlineColor(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    ) -> DanmakuColor {
        // 官方解析器仅对纯黑文字切白边。这里把接近黑色也纳入,避免深色插件弹幕
        // 与黑边糊成一团,其余文字仍使用官方默认的黑色描边。
        let isNearlyBlack = max(red, green, blue) <= 0.12
        return (isNearlyBlack ? DanmakuColor.white : DanmakuColor.black)
            .withAlphaComponent(alpha)
    }
}
