//
//  DanmakuDisplayMessage.swift
//  AngelLiveCore
//
//  弹幕消息的展示模型：跨模块边界交给 App 层渲染。
//  字段均为展示就绪值，App 层不做任何来源判断。
//

import Foundation
import CoreGraphics

/// 图片弹幕的图片信息。
public struct DanmakuDisplayImage: Sendable, Equatable {
    public let url: URL
    /// 原始像素尺寸。缺失时按图片自身解码尺寸处理。
    public let pixelSize: CGSize?
    /// 此图片加载失败时使用的局部降级文案。
    public let altText: String?

    public init(url: URL, pixelSize: CGSize?, altText: String? = nil) {
        self.url = url
        self.pixelSize = pixelSize
        self.altText = altText
    }
}

/// 一条弹幕内部的有序内容片段。
public enum DanmakuDisplaySegment: Sendable, Equatable {
    case text(String)
    case image(DanmakuDisplayImage)
}

/// 一条弹幕的展示模型。
///
/// `segments` 是首选展示内容；旧插件的 `image` 会自动转换成单图片片段。
/// `text` 始终有值，所有片段无效或图片全部加载失败时作为整条降级文案。
public struct DanmakuDisplayMessage: Sendable, Equatable {
    public let text: String
    public let nickname: String
    public let color: UInt32
    public let segments: [DanmakuDisplaySegment]

    /// 兼容旧调用方：仅当整条内容是单张图片时返回该图片。
    public var image: DanmakuDisplayImage? {
        guard segments.count == 1, case .image(let image) = segments[0] else { return nil }
        return image
    }

    public init(text: String, nickname: String, color: UInt32, image: DanmakuDisplayImage? = nil) {
        self.init(
            text: text,
            nickname: nickname,
            color: color,
            segments: image.map { [.image($0)] } ?? [.text(text)]
        )
    }

    public init(
        text: String,
        nickname: String,
        color: UInt32,
        segments: [DanmakuDisplaySegment]
    ) {
        self.text = text
        self.nickname = nickname
        self.color = color
        self.segments = segments.isEmpty ? [.text(text)] : segments
    }
}

extension DanmakuDisplayMessage {
    /// 默认弹幕颜色，插件未提供 color 时使用。
    static let defaultColor: UInt32 = 0xFFFFFF

    init(_ message: LiveParseDanmakuMessage) {
        let decodedSegments = Self.displaySegments(from: message.segments)
        self.init(
            text: message.text,
            nickname: message.nickname,
            color: message.color ?? Self.defaultColor,
            segments: decodedSegments.isEmpty
                ? Self.legacySegments(text: message.text, image: message.image)
                : decodedSegments
        )
    }

    /// 限制单条内容复杂度，避免不可信插件一次触发无界下载和离屏位图尺寸。
    private static let maximumSegmentCount = 32
    private static let maximumImageCount = 8

    private static func displaySegments(
        from segments: [LiveParseDanmakuSegment]?
    ) -> [DanmakuDisplaySegment] {
        guard let segments else { return [] }

        var result: [DanmakuDisplaySegment] = []
        var imageCount = 0
        for segment in segments.prefix(maximumSegmentCount) {
            switch segment {
            case .text(let text) where !text.isEmpty:
                if case .text(let previous)? = result.last {
                    result[result.count - 1] = .text(previous + text)
                } else {
                    result.append(.text(text))
                }
            case .image(let image) where imageCount < maximumImageCount:
                guard let displayImage = DanmakuDisplayImage(image) else { continue }
                result.append(.image(displayImage))
                imageCount += 1
            default:
                continue
            }
        }
        return result
    }

    private static func legacySegments(
        text: String,
        image: LiveParseDanmakuImage?
    ) -> [DanmakuDisplaySegment] {
        if let image = DanmakuDisplayImage(image) {
            return [.image(image)]
        }
        return [.text(text)]
    }
}

extension DanmakuDisplayImage {
    /// URL 非法时返回 nil，消息自动退化为纯文本弹幕。
    init?(_ image: LiveParseDanmakuImage?) {
        guard let image,
              let url = URL(string: image.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let size: CGSize?
        if let width = image.width, let height = image.height, width > 0, height > 0 {
            size = CGSize(width: width, height: height)
        } else {
            size = nil
        }

        self.init(url: url, pixelSize: size, altText: image.alt)
    }
}
