//
//  DanmuView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/5.
//

import SwiftUI
import UIKit
import AngelLiveCore

struct DanmuView: UIViewRepresentable {
    var coordinator: Coordinator
    var height: CGFloat
    @Environment(AppState.self) var appViewModel

    func makeUIView(context: Context) -> DanmakuView {
        let view = DanmakuView(frame: .init(x: 0, y: 0, width: 1920, height: height))
        // 各端统一采用 B 站风格的顶部首个安全轨道;此处显式设置以固定 tvOS 行为。
        view.floatingTrackPolicy = .topPriority
        view.playingSpeed = Float(appViewModel.danmuSettingsViewModel.danmuSpeed)
        view.play()
        coordinator.uiView = view
        return view
    }

    func updateUIView(_ uiView: DanmakuView, context: Context) {
        // §6.1 切字号:仅当 frame 真变化时才重算轨道;paddingTop/trackHeight/displayArea 各自 didSet 已在真变化时重算
        let newFrame = CGRect(x: 0, y: 0, width: 1920, height: height)
        if uiView.frame != newFrame {
            uiView.frame = newFrame
            uiView.recalculateTracks()
        }
        uiView.paddingTop = 5
        uiView.trackHeight = CGFloat(Double(appViewModel.danmuSettingsViewModel.danmuFontSize) * 1.35)
        uiView.playingSpeed = Float(appViewModel.danmuSettingsViewModel.danmuSpeed)
        uiView.displayArea = 1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var uiView: DanmakuView?

        func setup(view: DanmakuView) {
            self.uiView = view
        }

        /// 发射弹幕。带图片的消息先取图再发射,取图失败或超时降级为文本弹幕。
        @MainActor
        func shoot(_ message: DanmakuDisplayMessage, showColorDanmu: Bool, alpha: CGFloat, font: CGFloat) {
            guard let image = message.image else {
                shoot(text: message.text, showColorDanmu: showColorDanmu, color: message.color, alpha: alpha, font: font)
                return
            }

            Task { @MainActor [weak self] in
                guard let cgImage = await DanmakuImageLoader.shared.image(for: image.url) else {
                    self?.shoot(text: message.text, showColorDanmu: showColorDanmu, color: message.color, alpha: alpha, font: font)
                    return
                }
                self?.shootImage(cgImage, pixelSize: image.pixelSize, font: font)
            }
        }

        @MainActor
        private func shootImage(_ image: CGImage, pixelSize: CGSize?, font: CGFloat) {
            let model = DanmakuImageCellModel(
                image: image,
                pixelSize: pixelSize,
                font: .systemFont(ofSize: font)
            )
            // §6.2 错落感:与文本弹幕一致的 displayTime 微抖动
            model.displayTime = model.displayTime * Double.random(in: 0.85...1.15)
            uiView?.shoot(danmaku: model)
        }

        func shoot(text: String, showColorDanmu: Bool, color: UInt32, alpha: CGFloat, font: CGFloat) {
            let model = DanmakuTextCellModel(str: text, strFont: .systemFont(ofSize: font))
            // §6.2 错落感:displayTime ±15% 微抖动,同 tick 发出的弹幕速度自然拉开
            model.displayTime = model.displayTime * Double.random(in: 0.85...1.15)
            if text.contains("醒目留言") || text.contains("SC") {
                model.backgroundColor = .orange
                model.color = .white
            } else {
                if showColorDanmu && color != 0xFFFFFF {
                    model.color = UIColor(rgb: Int(color), alpha: alpha)
                } else {
                    model.color = UIColor.white.withAlphaComponent(alpha)
                }
            }
            DispatchQueue.main.async {
                self.uiView?.shoot(danmaku: model)
            }
        }

        func pause() {
            DispatchQueue.main.async {
                self.uiView?.pause()
            }
        }

        func play() {
            DispatchQueue.main.async {
                self.uiView?.play()
            }
        }

        func clear() {
            DispatchQueue.main.async {
                self.uiView?.stop()
            }
        }
    }
}
