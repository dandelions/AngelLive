import Foundation
import CoreGraphics
import CoreText

/// 已完成网络加载、可直接参与布局和离屏绘制的图文片段。
public enum DanmakuMixedCellSegment {
    case text(String)
    case image(CGImage, pixelSize: CGSize?)
}

public final class DanmakuMixedCellModel: DanmakuCellModel {
    struct LayoutItem {
        let segment: DanmakuMixedCellSegment
        let rect: CGRect
    }

    private static let horizontalPadding: CGFloat = 25
    private static let verticalPadding: CGFloat = 6
    private static let imageHeightScale: CGFloat = 1.2
    private static let maximumImageAspectRatio: CGFloat = 4

    public var identifier = ""
    public let segments: [DanmakuMixedCellSegment]
    public let font: DanmakuFont
    public var color: DanmakuColor = .white
    public var backgroundColor: DanmakuColor = .clear
    public private(set) var size: CGSize = .zero
    public var track: UInt?
    public var displayTime: Double = 10
    public var type: DanmakuCellType = .floating
    public var isPause = false

    var layoutItems: [LayoutItem] = []

    public var cellClass: DanmakuCell.Type {
        DanmakuMixedCell.self
    }

    public init(segments: [DanmakuMixedCellSegment], font: DanmakuFont) {
        self.segments = segments
        self.font = font
        calculateSize()
    }

    public func calculateSize() {
        let measured = segments.compactMap { segment -> (DanmakuMixedCellSegment, CGSize)? in
            switch segment {
            case .text(let text):
                guard !text.isEmpty else { return nil }
                return (segment, Self.measure(text: text, font: font))
            case .image(let image, let pixelSize):
                let source = pixelSize ?? CGSize(width: image.width, height: image.height)
                let ratio: CGFloat
                if source.width > 0, source.height > 0 {
                    ratio = min(source.width / source.height, Self.maximumImageAspectRatio)
                } else {
                    ratio = 1
                }
                let height = max(font.danmakuLineHeight * Self.imageHeightScale, 1)
                return (segment, CGSize(width: height * ratio, height: height))
            }
        }

        guard !measured.isEmpty else {
            layoutItems = []
            size = CGSize(width: 100, height: 60)
            return
        }

        let spacing = max(font.pointSize * 0.12, 2)
        let contentHeight = measured.map(\.1.height).max() ?? font.danmakuLineHeight
        var x = Self.horizontalPadding
        layoutItems = measured.enumerated().map { index, item in
            let rect = CGRect(
                x: x,
                y: Self.verticalPadding + (contentHeight - item.1.height) / 2,
                width: item.1.width,
                height: item.1.height
            )
            x += item.1.width
            if index < measured.count - 1 {
                x += spacing
            }
            return LayoutItem(segment: item.0, rect: rect)
        }

        size = CGSize(
            width: ceil(x + Self.horizontalPadding),
            height: ceil(contentHeight + Self.verticalPadding * 2)
        )
    }

    public func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        identifier == cellModel.identifier
    }

    private static func measure(text: String, font: DanmakuFont) -> CGSize {
#if canImport(AppKit) && !canImport(UIKit)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font as CTFont
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, [])
        return CGSize(width: ceil(bounds.width), height: ceil(max(bounds.height, font.danmakuLineHeight)))
#else
        let measured = NSString(string: text).size(withAttributes: [.font: font])
        return CGSize(width: ceil(measured.width), height: ceil(max(measured.height, font.danmakuLineHeight)))
#endif
    }
}
