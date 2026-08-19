import CoreGraphics
import Testing
@testable import AngelLiveCore

@Suite("Danmaku mixed content layout")
struct DanmakuMixedCellModelTests {
    @Test("text and images keep source order and share one measured cell")
    func laysOutOrderedSegments() throws {
        let image = try #require(makeImage(width: 80, height: 40))
        let model = DanmakuMixedCellModel(
            segments: [
                .text("before"),
                .image(image, pixelSize: CGSize(width: 80, height: 40)),
                .text("after")
            ],
            font: .systemFont(ofSize: 20)
        )

        #expect(model.layoutItems.count == 3)
        #expect(model.layoutItems[0].rect.maxX < model.layoutItems[1].rect.minX)
        #expect(model.layoutItems[1].rect.maxX < model.layoutItems[2].rect.minX)
        #expect(model.size.width > model.layoutItems[2].rect.maxX)
        #expect(model.size.height >= model.layoutItems[1].rect.height)
        #expect(model.cellClass == DanmakuMixedCell.self)
    }

    @Test("extremely wide images are capped to four times their inline height")
    func capsImageAspectRatio() throws {
        let image = try #require(makeImage(width: 1_000, height: 10))
        let model = DanmakuMixedCellModel(
            segments: [.image(image, pixelSize: CGSize(width: 1_000, height: 10)), .text("ok")],
            font: .systemFont(ofSize: 20)
        )

        let imageRect = try #require(model.layoutItems.first?.rect)
        #expect(imageRect.width / imageRect.height <= 4.001)
    }

    @Test("shared resolver preserves content order and merges adjacent text")
    func resolvesTextSegmentsForAllPresentationSurfaces() async throws {
        let resolved = await DanmakuContentResolver.resolve([
            .text("hello"),
            .text(" world")
        ])

        #expect(resolved.count == 1)
        guard case .text(let text) = try #require(resolved.first) else {
            Issue.record("Expected a resolved text segment")
            return
        }
        #expect(text == "hello world")
    }

    private func makeImage(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }
}
