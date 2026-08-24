import Foundation

/// 插件房间数据的兼容解码模型。
///
/// 插件历史上会把部分标识和计数字段编码成数字或布尔值，因此这里统一按字符串接收；
/// 是否具备可导航的稳定身份，由具体宿主服务在解码后校验。
public struct PluginRoomDTO: Decodable, Equatable, Sendable {
    public let userName: String
    public let roomTitle: String
    public let roomCover: String
    public let userHeadImg: String
    public let liveState: String?
    public let userId: String
    public let roomId: String
    public let liveWatchedCount: String?

    public init(
        userName: String,
        roomTitle: String,
        roomCover: String,
        userHeadImg: String,
        liveState: String?,
        userId: String,
        roomId: String,
        liveWatchedCount: String?
    ) {
        self.userName = userName
        self.roomTitle = roomTitle
        self.roomCover = roomCover
        self.userHeadImg = userHeadImg
        self.liveState = liveState
        self.userId = userId
        self.roomId = roomId
        self.liveWatchedCount = liveWatchedCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        userName = container.decodeLossyStringIfPresent(forKey: .userName) ?? ""
        roomTitle = container.decodeLossyStringIfPresent(forKey: .roomTitle) ?? ""
        roomCover = container.decodeLossyStringIfPresent(forKey: .roomCover) ?? ""
        userHeadImg = container.decodeLossyStringIfPresent(forKey: .userHeadImg) ?? ""
        liveState = container.decodeLossyStringIfPresent(forKey: .liveState)
        userId = container.decodeLossyStringIfPresent(forKey: .userId) ?? ""
        roomId = container.decodeLossyStringIfPresent(forKey: .roomId) ?? ""
        liveWatchedCount = container.decodeLossyStringIfPresent(forKey: .liveWatchedCount)
    }

    private enum CodingKeys: String, CodingKey {
        case userName
        case roomTitle
        case roomCover
        case userHeadImg
        case liveState
        case userId
        case roomId
        case liveWatchedCount
    }

    public func toLiveModel(liveType: LiveType) -> LiveModel {
        LiveModel(
            userName: userName,
            roomTitle: roomTitle,
            roomCover: roomCover,
            userHeadImg: userHeadImg,
            liveType: liveType,
            liveState: liveState,
            userId: userId,
            roomId: roomId,
            liveWatchedCount: liveWatchedCount
        )
    }
}

extension KeyedDecodingContainer {
    func decodeLossyStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func decodeLossyIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key), let intValue = Int(value) {
            return intValue
        }
        return nil
    }
}
