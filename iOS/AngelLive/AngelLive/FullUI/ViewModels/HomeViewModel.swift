//
//  HomeViewModel.swift
//  AngelLive
//
//  插件驱动首页的展示状态。各插件独立加载，失败时保留其他来源的内容。
//

import AngelLiveCore
import Foundation
import Observation

struct HomeBannerEntry: Identifiable, Sendable {
    let banner: PluginHomeBanner
    let pluginId: String
    let pluginDisplayName: String
    let liveType: LiveType

    var id: String { banner.id }
}

struct HomeSectionEntry: Identifiable, Sendable {
    let section: PluginHomeSection
    let pluginId: String
    let pluginDisplayName: String
    let liveType: LiveType

    var id: String { section.id }
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var bannerEntries: [HomeBannerEntry] = []
    private(set) var sectionEntries: [HomeSectionEntry] = []
    private(set) var failedPluginNames: [String] = []
    private(set) var isRefreshing = false
    private(set) var hasLoaded = false

    @ObservationIgnored
    private let service: PluginHomeFeedService
    @ObservationIgnored
    private var feedsByPluginId: [String: PluginHomeFeed] = [:]
    @ObservationIgnored
    private var platformOrder: [String] = []
    @ObservationIgnored
    private var sectionOrder: [String] = []

    init(service: PluginHomeFeedService = PluginHomeFeedService()) {
        self.service = service
    }

    func refresh(installedPluginIds: [String]) async {
        guard !isRefreshing else { return }

        let platforms = SandboxPluginCatalog
            .availablePlatforms(installedPluginIds: installedPluginIds)
            .filter { PlatformCapability.supports(.homeFeed, for: $0.liveType) }

        let activePluginIds = Set(platforms.map(\.pluginId))
        feedsByPluginId = feedsByPluginId.filter { activePluginIds.contains($0.key) }
        platformOrder = stableOrder(
            previous: platformOrder,
            current: platforms.map(\.pluginId)
        )
        failedPluginNames.removeAll()
        rebuildEntries()

        guard !platforms.isEmpty else {
            hasLoaded = true
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoaded = true
        }

        await withTaskGroup(of: HomeFeedFetchResult.self) { group in
            for platform in platforms {
                group.addTask { [service] in
                    do {
                        let feed = try await service.fetch(platform: platform)
                        return .success(feed)
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        return .failure(
                            pluginId: platform.pluginId,
                            pluginDisplayName: platform.displayName,
                            message: error.localizedDescription
                        )
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let feed):
                    feedsByPluginId[feed.pluginId] = feed
                case .failure(let pluginId, let pluginDisplayName, let message):
                    failedPluginNames.append(pluginDisplayName)
                    Logger.warning(
                        "首页内容加载失败: pluginId=\(pluginId), error=\(message)",
                        category: .plugin
                    )
                case .cancelled:
                    break
                }
                rebuildEntries()
            }
        }
    }
}

private extension HomeViewModel {
    func stableOrder(previous: [String], current: [String]) -> [String] {
        let currentSet = Set(current)
        let retained = previous.filter(currentSet.contains)
        let retainedSet = Set(retained)
        return retained + current.filter { !retainedSet.contains($0) }
    }

    func rebuildEntries() {
        let feeds = platformOrder.compactMap { feedsByPluginId[$0] }
        bannerEntries = fairBannerEntries(from: feeds)

        let availableSections: [HomeSectionEntry] = feeds.flatMap { feed -> [HomeSectionEntry] in
            let liveType = LiveParseJSPlatformManager.platform(forPluginId: feed.pluginId)?.liveType
                ?? LiveType(rawValue: feed.pluginId)
                ?? .placeholder
            return feed.sections.compactMap { section -> HomeSectionEntry? in
                guard !section.items.isEmpty else { return nil }
                return HomeSectionEntry(
                    section: section,
                    pluginId: feed.pluginId,
                    pluginDisplayName: feed.pluginDisplayName,
                    liveType: section.items.first?.room.liveType ?? liveType
                )
            }
        }

        let availableSectionIds = Set(availableSections.map(\.id))
        sectionOrder = stableOrder(
            previous: sectionOrder.filter(availableSectionIds.contains),
            current: availableSections.map(\.id)
        )
        let entryById = Dictionary(
            availableSections.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        sectionEntries = sectionOrder.compactMap { entryById[$0] }
    }

    func fairBannerEntries(from feeds: [PluginHomeFeed]) -> [HomeBannerEntry] {
        let maximumBannerCount = 5
        let maximumSourceCount = feeds.map(\.banners.count).max() ?? 0
        var result: [HomeBannerEntry] = []

        for sourceIndex in 0..<maximumSourceCount {
            for feed in feeds where feed.banners.indices.contains(sourceIndex) {
                let banner = feed.banners[sourceIndex]
                let liveType: LiveType
                switch banner.target {
                case .room(let room):
                    liveType = room.liveType
                case .category:
                    liveType = LiveParseJSPlatformManager.platform(forPluginId: feed.pluginId)?.liveType
                        ?? LiveType(rawValue: feed.pluginId)
                        ?? .placeholder
                }
                result.append(
                    HomeBannerEntry(
                        banner: banner,
                        pluginId: feed.pluginId,
                        pluginDisplayName: feed.pluginDisplayName,
                        liveType: liveType
                    )
                )
                if result.count == maximumBannerCount {
                    return result
                }
            }
        }
        return result
    }
}

private enum HomeFeedFetchResult: Sendable {
    case success(PluginHomeFeed)
    case failure(pluginId: String, pluginDisplayName: String, message: String)
    case cancelled
}
