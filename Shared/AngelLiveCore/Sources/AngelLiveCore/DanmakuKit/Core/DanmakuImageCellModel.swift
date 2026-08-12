//
//  DanmakuImageCellModel.swift
//  AngelLiveCore
//
//  整条弹幕是一张图片时使用的 cell model。
//  只负责渲染,图片必须由调用方取好并解码完成(与 DanmakuTextCellModel 只持有文本同理)。
//

import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public final class DanmakuImageCellModel: DanmakuCellModel {
    /// 图片高度相对文本行高的倍数。略高于文本,让图片弹幕在同一轨道里不显局促。
    private static let heightScale: CGFloat = 1.2
    /// 图片宽度上限(相对自身高度)。超宽图会挤占整条轨道,按此裁剪宽高比。
    private static let maxAspectRatio: CGFloat = 4

    public var identifier = ""

    public let image: CGImage
    /// 原始像素尺寸;缺失时按 CGImage 自身尺寸推导宽高比。
    public let pixelSize: CGSize?
    public let font: DanmakuFont

    public var size: CGSize = .zero
    public var track: UInt?
    public var displayTime: Double = 10
    public var type: DanmakuCellType = .floating
    public var isPause = false

    /// 图片实际绘制区域(相对 cell bounds),已按宽高比缩放并居中。
    public private(set) var contentSize: CGSize = .zero

    public var cellClass: DanmakuCell.Type {
        DanmakuImageCell.self
    }

    public init(image: CGImage, pixelSize: CGSize?, font: DanmakuFont) {
        self.image = image
        self.pixelSize = pixelSize
        self.font = font
        self.type = .floating
        calculateSize()
    }

    public func calculateSize() {
        let contentHeight = max(font.danmakuLineHeight * Self.heightScale, 1)

        let source = pixelSize ?? CGSize(width: image.width, height: image.height)
        let ratio: CGFloat
        if source.width > 0, source.height > 0 {
            ratio = min(source.width / source.height, Self.maxAspectRatio)
        } else {
            ratio = 1
        }

        contentSize = CGSize(width: contentHeight * ratio, height: contentHeight)

        // padding 与 DanmakuTextCellModel 保持一致,使图文弹幕间距观感统一
#if canImport(AppKit) && !canImport(UIKit)
        let horizontalPadding: CGFloat = 50
        let verticalPadding: CGFloat = 12
#else
        let horizontalPadding = font.pointSize + 25
        let verticalPadding = font.pointSize * 0.5 + 12
#endif

        size = CGSize(
            width: contentSize.width + horizontalPadding,
            height: contentSize.height + verticalPadding
        )
    }

    /// 图片在 cell 内的绘制矩形:水平方向留与文本相同的左侧起始位置,垂直居中。
    /// 居中对坐标系翻转不敏感,iOS 与 macOS 两套 context 约定下位置一致。
    public func contentRect(in boundsSize: CGSize) -> CGRect {
        let x = (boundsSize.width - contentSize.width) / 2
        let y = (boundsSize.height - contentSize.height) / 2
        return CGRect(x: x, y: y, width: contentSize.width, height: contentSize.height)
    }

    public func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        identifier == cellModel.identifier
    }
}
