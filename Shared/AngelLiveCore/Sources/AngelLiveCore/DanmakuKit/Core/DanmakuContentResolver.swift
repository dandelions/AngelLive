import CoreGraphics
import Foundation

/// 已完成图片加载、可直接交给 UI 或弹幕渲染器展示的内容片段。
public enum DanmakuResolvedSegment: Sendable {
    case text(String)
    case image(CGImage, pixelSize: CGSize?)
}

/// 图文弹幕统一解析器。飞屏弹幕和聊天列表共用同一份缓存、并发去重与失败降级逻辑。
public enum DanmakuContentResolver {
    public static func resolve(
        _ segments: [DanmakuDisplaySegment]
    ) async -> [DanmakuResolvedSegment] {
        var images: [Int: CGImage] = [:]
        await withTaskGroup(of: (Int, CGImage?).self) { group in
            for (index, segment) in segments.enumerated() {
                guard case .image(let image) = segment else { continue }
                group.addTask {
                    (index, await DanmakuImageLoader.shared.image(for: image.url))
                }
            }

            for await (index, image) in group {
                images[index] = image
            }
        }

        var result: [DanmakuResolvedSegment] = []
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .text(let text):
                append(text: text, to: &result)
            case .image(let descriptor):
                if let image = images[index] {
                    result.append(.image(image, pixelSize: descriptor.pixelSize))
                } else if let alt = descriptor.altText {
                    append(text: alt, to: &result)
                }
            }
        }
        return result
    }

    private static func append(text: String, to result: inout [DanmakuResolvedSegment]) {
        guard !text.isEmpty else { return }
        if case .text(let previous)? = result.last {
            result[result.count - 1] = .text(previous + text)
        } else {
            result.append(.text(text))
        }
    }
}
