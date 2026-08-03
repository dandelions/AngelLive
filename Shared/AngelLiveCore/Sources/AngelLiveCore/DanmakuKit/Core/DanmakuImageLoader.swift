//
//  DanmakuImageLoader.swift
//  AngelLiveCore
//
//  图片弹幕取图:内存缓存 + 并发去重 + 尺寸/条数上限。
//  弹幕是易逝内容,取图超时或失败一律放弃,由调用方降级为文本弹幕。
//
//  统一以 CGImage 为载体:绘制侧本就走 CoreGraphics,且 CGImage 是 Sendable,
//  而 NSImage 不是,用平台图类型会在跨隔离传递时失去并发安全保证。
//

import Foundation
import CoreGraphics
import ImageIO

public actor DanmakuImageLoader {
    public static let shared = DanmakuImageLoader()

    /// 解码后最大边长(像素)。表情类图片远小于此值,超限的按此下采样,防止异常大图打爆内存。
    private static let maxPixelDimension = 512
    /// 内存缓存条数上限。表情图重复率极高,这个量级足以覆盖一个直播间的常用表情。
    private static let maxCacheCount = 120
    /// 取图超时。超时后这条弹幕已无展示价值,放弃并降级为文本。
    private static let requestTimeout: TimeInterval = 3

    private let session: URLSession
    private var cache: [URL: CGImage] = [:]
    /// 缓存淘汰顺序(最早插入在前),达到上限后从头淘汰。
    private var cacheOrder: [URL] = []
    /// 同一 URL 的在途请求,避免同一表情刷屏时重复下载。
    private var inFlight: [URL: Task<CGImage?, Never>] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.requestTimeout
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: configuration)
        }
    }

    /// 取图。命中缓存立即返回;失败、超时或图片异常返回 nil,调用方应降级为文本弹幕。
    public func image(for url: URL) async -> CGImage? {
        if let cached = cache[url] {
            return cached
        }

        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<CGImage?, Never> { [session] in
            guard let (data, response) = try? await session.data(from: url) else { return nil }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            return Self.decode(data)
        }
        inFlight[url] = task

        let image = await task.value
        inFlight[url] = nil
        if let image {
            store(image, for: url)
        }
        return image
    }

    private func store(_ image: CGImage, for url: URL) {
        if cache[url] == nil {
            cacheOrder.append(url)
        }
        cache[url] = image

        while cacheOrder.count > Self.maxCacheCount {
            let evicted = cacheOrder.removeFirst()
            cache[evicted] = nil
        }
    }

    /// 经 ImageIO 解码并下采样。WebP/APNG/GIF 在 iOS 14+ / macOS 11+ 均由系统支持;
    /// 动图只取首帧(本期不做动画播放)。
    private nonisolated static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
