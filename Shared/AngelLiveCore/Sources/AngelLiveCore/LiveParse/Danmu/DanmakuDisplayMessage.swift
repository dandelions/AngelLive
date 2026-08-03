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

    public init(url: URL, pixelSize: CGSize?) {
        self.url = url
        self.pixelSize = pixelSize
    }
}

/// 一条弹幕的展示模型。
///
/// `image` 存在即代表这是一条图片弹幕；不存在则是普通文本弹幕。
/// `text` 始终有值，图片加载失败或不支持图片渲染时作为降级文案。
public struct DanmakuDisplayMessage: Sendable, Equatable {
    public let text: String
    public let nickname: String
    public let color: UInt32
    public let image: DanmakuDisplayImage?

    public init(text: String, nickname: String, color: UInt32, image: DanmakuDisplayImage? = nil) {
        self.text = text
        self.nickname = nickname
        self.color = color
        self.image = image
    }
}

extension DanmakuDisplayMessage {
    /// 默认弹幕颜色，插件未提供 color 时使用。
    static let defaultColor: UInt32 = 0xFFFFFF

    init(_ message: LiveParseDanmakuMessage) {
        self.init(
            text: message.text,
            nickname: message.nickname,
            color: message.color ?? Self.defaultColor,
            image: DanmakuDisplayImage(message.image)
        )
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

        self.init(url: url, pixelSize: size)
    }
}
