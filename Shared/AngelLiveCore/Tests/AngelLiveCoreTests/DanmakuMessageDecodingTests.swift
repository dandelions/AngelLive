import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Danmaku driver message decoding")
struct DanmakuMessageDecodingTests {
    private func decode(_ json: String) throws -> LiveParseDanmakuDriverResult {
        try JSONDecoder().decode(LiveParseDanmakuDriverResult.self, from: Data(json.utf8))
    }

    @Test("plain message decodes without an image block")
    func decodesPlainMessage() throws {
        let result = try decode("""
        {"messages":[{"text":"233333","nickname":"alice","color":16777215}]}
        """)

        #expect(result.messages?.count == 1)
        #expect(result.messages?.first?.text == "233333")
        #expect(result.messages?.first?.image == nil)
    }

    @Test("image block decodes with url and pixel size")
    func decodesImageBlock() throws {
        let result = try decode("""
        {"messages":[{"text":"[dog]","nickname":"bob","color":16777215,
        "image":{"url":"https://example.com/dog.png","width":162,"height":81}}]}
        """)

        let message = try #require(result.messages?.first)
        let display = DanmakuDisplayMessage(message)
        #expect(display.image?.url.absoluteString == "https://example.com/dog.png")
        #expect(display.image?.pixelSize == CGSize(width: 162, height: 81))
        #expect(display.text == "[dog]")
    }

    @Test("image block without size keeps url and leaves pixel size nil")
    func decodesImageWithoutSize() throws {
        let result = try decode("""
        {"messages":[{"text":"[cat]","nickname":"carol",
        "image":{"url":"https://example.com/cat.png"}}]}
        """)

        let display = DanmakuDisplayMessage(try #require(result.messages?.first))
        #expect(display.image?.url.absoluteString == "https://example.com/cat.png")
        #expect(display.image?.pixelSize == nil)
        // color 缺失时落默认值
        #expect(display.color == DanmakuDisplayMessage.defaultColor)
    }

    @Test("ordered segments decode as text-image-text content")
    func decodesMixedSegments() throws {
        let result = try decode("""
        {"messages":[{"text":"hello [dog] world","nickname":"alice","color":65280,
        "segments":[
          {"type":"text","text":"hello "},
          {"type":"image","url":"https://example.com/dog.png","width":80,"height":40,"alt":"[dog]"},
          {"type":"text","text":" world"}
        ]}]}
        """)

        let message = try #require(result.messages?.first)
        let display = DanmakuDisplayMessage(message)
        #expect(display.segments.count == 3)
        #expect(display.image == nil)

        guard case .text(let prefix) = display.segments[0],
              case .image(let image) = display.segments[1],
              case .text(let suffix) = display.segments[2] else {
            Issue.record("segments did not preserve text-image-text order")
            return
        }
        #expect(prefix == "hello ")
        #expect(image.url.absoluteString == "https://example.com/dog.png")
        #expect(image.pixelSize == CGSize(width: 80, height: 40))
        #expect(image.altText == "[dog]")
        #expect(suffix == " world")
    }

    @Test("one malformed or future segment is dropped without discarding valid siblings")
    func malformedSegmentDoesNotDiscardMessage() throws {
        let result = try decode("""
        {"messages":[{"text":"fallback","nickname":"alice",
        "segments":[
          {"type":"text","text":"before"},
          {"type":"sticker","url":"https://example.com/future.webp"},
          {"type":"image","url":42},
          {"type":"text","text":" after"}
        ]}]}
        """)

        let display = DanmakuDisplayMessage(try #require(result.messages?.first))
        // 两个相邻的有效文本片段在过滤坏片段后会合并，减少绘制 run 数量。
        #expect(display.segments == [.text("before after")])
    }

    @Test("valid segments take precedence over the legacy whole-image block")
    func segmentsTakePrecedenceOverLegacyImage() throws {
        let result = try decode("""
        {"messages":[{"text":"fallback","nickname":"alice",
        "image":{"url":"https://example.com/legacy.png"},
        "segments":[{"type":"text","text":"new format"}]}]}
        """)

        let display = DanmakuDisplayMessage(try #require(result.messages?.first))
        #expect(display.segments == [.text("new format")])
        #expect(display.image == nil)
    }

    @Test("non http url degrades to a plain text message")
    func rejectsNonHTTPImageURL() throws {
        let result = try decode("""
        {"messages":[{"text":"fallback","nickname":"dave",
        "image":{"url":"file:///etc/passwd","width":10,"height":10}}]}
        """)

        let display = DanmakuDisplayMessage(try #require(result.messages?.first))
        #expect(display.image == nil)
        #expect(display.text == "fallback")
    }

    @Test("one malformed element is dropped while the rest of the batch survives")
    func malformedElementDoesNotDiscardBatch() throws {
        // 第二条缺少必填的 nickname,整批解码若不做逐条容错会全军覆没
        let result = try decode("""
        {"messages":[
          {"text":"first","nickname":"alice","color":16777215},
          {"text":"broken"},
          {"text":"third","nickname":"carol","color":16777215}
        ]}
        """)

        #expect(result.messages?.count == 2)
        #expect(result.messages?.map(\.text) == ["first", "third"])
    }

    @Test("a malformed image block does not discard the message itself")
    func malformedImageBlockDropsWholeMessageNotBatch() throws {
        // image.url 是必填 String,类型错误时该条消息解码失败被丢弃,其余照常送达
        let result = try decode("""
        {"messages":[
          {"text":"kept","nickname":"alice"},
          {"text":"bad-image","nickname":"bob","image":{"url":123}}
        ]}
        """)

        #expect(result.messages?.count == 1)
        #expect(result.messages?.first?.text == "kept")
    }

    @Test("unknown keys are ignored for forward compatibility")
    func ignoresUnknownKeys() throws {
        let result = try decode("""
        {"messages":[{"text":"hi","nickname":"alice","futureBlock":{"a":1}}],"futureTopLevel":true}
        """)

        #expect(result.messages?.count == 1)
        #expect(result.messages?.first?.text == "hi")
    }
}
