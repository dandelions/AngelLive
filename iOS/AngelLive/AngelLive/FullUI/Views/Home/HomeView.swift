//
//  HomeView.swift
//  AngelLive
//
//  插件驱动的 iOS 首页：焦点内容、本地收藏、插件分区、历史和平台入口。
//

import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

struct HomeView: View {
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.presentToast) private var presentToast

    @State private var viewModel = HomeViewModel()
    @State private var navigationState = LiveRoomNavigationState()
    @State private var contentWidth: CGFloat = 390
    @Namespace private var roomTransitionNamespace

    var body: some View {
        playerPresentation
            .task(id: pluginAvailability.installedPluginIds) {
                async let feedRefresh: Void = viewModel.refresh(
                    installedPluginIds: pluginAvailability.installedPluginIds
                )
                async let favoriteRefresh: Void = refreshFavoritesIfNeeded()
                _ = await (feedRefresh, favoriteRefresh)
            }
    }
}

private extension HomeView {
    @ViewBuilder
    var playerPresentation: some View {
        if #available(iOS 18.0, *) {
            homeNavigation
                .fullScreenCover(isPresented: playerPresentedBinding) {
                    playerDestination
                }
        } else {
            homeNavigation
                .navigationDestination(isPresented: playerPresentedBinding) {
                    playerDestination
                }
        }
    }

    var homeNavigation: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 36) {
                    if !viewModel.bannerEntries.isEmpty {
                        HomeHeroCarousel(
                            entries: viewModel.bannerEntries,
                            containerWidth: contentWidth,
                            onOpenRoom: { room in
                                openRoom(room, rooms: [room], mode: .direct)
                            }
                        )
                    } else if viewModel.isRefreshing {
                        HomeHeroLoadingCard(containerWidth: contentWidth)
                    } else {
                        HomeCompactHeader()
                    }

                    HomeFavoriteSection(
                        rooms: Array(favoriteModel.roomList.prefix(10)),
                        isRefreshing: favoriteModel.isCloudSyncing,
                        cardWidth: roomCardWidth,
                        namespace: roomTransitionNamespace,
                        onSelect: { room, rooms in
                            openRoom(room, rooms: rooms, mode: .local)
                        }
                    )

                    if let firstPluginSection = viewModel.sectionEntries.first,
                       !firstPluginSection.section.items.isEmpty {
                        HomePluginRoomSection(
                            entry: firstPluginSection,
                            cardWidth: roomCardWidth,
                            namespace: roomTransitionNamespace,
                            onSelect: { room, rooms in
                                openRoom(room, rooms: rooms, mode: .direct)
                            }
                        )
                    }

                    ForEach(viewModel.sectionEntries.dropFirst()) { entry in
                        HomePluginRoomSection(
                            entry: entry,
                            cardWidth: roomCardWidth,
                            namespace: roomTransitionNamespace,
                            onSelect: { room, rooms in
                                openRoom(room, rooms: rooms, mode: .direct)
                            }
                        )
                    }

                    if viewModel.hasLoaded,
                       !pluginAvailability.isChecking,
                       pluginAvailability.installedPluginIds.isEmpty {
                        HomeConfigurationGuide()
                    }

                    if !viewModel.failedPluginNames.isEmpty {
                        HomeFeedFailureCard(
                            pluginNames: viewModel.failedPluginNames,
                            isRefreshing: viewModel.isRefreshing,
                            retry: refreshHome
                        )
                    }
                }
                .padding(.bottom, 44)
            }
            .background(AppConstants.Colors.primaryBackground)
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea(edges: .top)
            .refreshable {
                await refreshAll()
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                contentWidth = max(1, newWidth)
            }
            .navigationDestination(for: HomeCategoryRoute.self) { route in
                HomeCategoryView(
                    route: route,
                    navigationState: navigationState,
                    namespace: roomTransitionNamespace
                )
            }
        }
    }

    var roomCardWidth: CGFloat {
        min(max((contentWidth - 48) / 2.22, 154), 280)
    }

    var playerPresentedBinding: Binding<Bool> {
        Binding(
            get: { navigationState.showPlayer },
            set: { isPresented in
                if !isPresented { navigationState.dismiss() }
            }
        )
    }

    @ViewBuilder
    var playerDestination: some View {
        if let room = navigationState.currentRoom {
            DetailPlayerView(
                viewModel: RoomInfoViewModel(room: room),
                categoryRooms: navigationState.categoryRooms
            )
            .modifier(
                ZoomTransitionModifier(
                    sourceID: room.roomId,
                    namespace: roomTransitionNamespace
                )
            )
            .toolbar(.hidden, for: .tabBar)
        }
    }

    func openRoom(_ room: LiveModel, rooms: [LiveModel], mode: HomeRoomOpenMode) {
        switch mode {
        case .direct:
            navigationState.navigate(to: room, categoryRooms: rooms)
        case .local:
            if room.liveState == LiveState.close.rawValue {
                presentToast(ToastValue(icon: Image(systemName: "tv.slash"), message: "主播已下播"))
            } else {
                navigationState.navigate(to: room, categoryRooms: rooms)
            }
        }
    }

    @MainActor
    func refreshFavoritesIfNeeded() async {
        if favoriteModel.shouldSync() {
            await favoriteModel.syncWithActor()
        }
    }

    func refreshHome() {
        Task {
            await viewModel.refresh(installedPluginIds: pluginAvailability.installedPluginIds)
        }
    }

    @MainActor
    func refreshAll() async {
        await viewModel.refresh(
            installedPluginIds: pluginAvailability.installedPluginIds
        )
        await favoriteModel.syncWithActor()
    }
}

private enum HomeRoomOpenMode {
    case direct
    case local
}

private struct HomeRoomPresentation: Identifiable {
    let id: String
    let room: LiveModel
    let detail: String

    init(id: String? = nil, room: LiveModel, detail: String) {
        self.id = id ?? room.id
        self.room = room
        self.detail = detail
    }
}

private struct HomeFavoriteSection: View {
    let rooms: [LiveModel]
    let isRefreshing: Bool
    let cardWidth: CGFloat
    let namespace: Namespace.ID
    let onSelect: (LiveModel, [LiveModel]) -> Void

    var body: some View {
        HomeHorizontalRoomSection(
            title: "我的收藏",
            subtitle: isRefreshing ? "状态更新中" : nil,
            items: rooms.map { HomeRoomPresentation(room: $0, detail: $0.userName) },
            cardWidth: cardWidth,
            emptyMessage: "收藏常看的直播间，之后可以从这里快速进入",
            emptySystemImage: "heart",
            trailing: {
                NavigationLink {
                    FavoriteView(embeddedInNavigationStack: true)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    HomeSeeAllLabel()
                }
            },
            onSelect: { room in onSelect(room, rooms) },
            namespace: namespace
        )
    }
}

private struct HomePluginRoomSection: View {
    let entry: HomeSectionEntry
    let cardWidth: CGFloat
    let namespace: Namespace.ID
    let onSelect: (LiveModel, [LiveModel]) -> Void

    private var rooms: [LiveModel] {
        entry.section.items.map(\.room)
    }

    private var subtitle: String {
        let source = entry.section.personalized
            ? "为你推荐 · 来自 \(entry.pluginDisplayName)"
            : "来自 \(entry.pluginDisplayName)"
        guard let subtitle = entry.section.subtitle, !subtitle.isEmpty else {
            return source
        }
        return "\(subtitle) · \(source)"
    }

    private var route: HomeCategoryRoute? {
        entry.section.seeAllTarget.map {
            HomeCategoryRoute(
                pluginId: entry.pluginId,
                liveType: entry.liveType,
                category: $0,
                fallbackTitle: entry.section.title
            )
        }
    }

    var body: some View {
        HomeHorizontalRoomSection(
            title: entry.section.title,
            subtitle: subtitle,
            items: entry.section.items.map {
                HomeRoomPresentation(
                    id: $0.id,
                    room: $0.room,
                    detail: $0.reason ?? $0.room.userName
                )
            },
            cardWidth: cardWidth,
            trailing: {
                if let route {
                    NavigationLink(value: route) {
                        HomeSeeAllLabel()
                    }
                }
            },
            onSelect: { room in onSelect(room, rooms) },
            namespace: namespace
        )
    }
}

private struct HomeHorizontalRoomSection<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let items: [HomeRoomPresentation]
    let cardWidth: CGFloat
    let emptyMessage: String?
    let emptySystemImage: String
    let trailing: Trailing
    let onSelect: (LiveModel) -> Void
    let namespace: Namespace.ID

    init(
        title: String,
        subtitle: String?,
        items: [HomeRoomPresentation],
        cardWidth: CGFloat,
        emptyMessage: String? = nil,
        emptySystemImage: String = "rectangle.stack",
        @ViewBuilder trailing: () -> Trailing,
        onSelect: @escaping (LiveModel) -> Void,
        namespace: Namespace.ID
    ) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.cardWidth = cardWidth
        self.emptyMessage = emptyMessage
        self.emptySystemImage = emptySystemImage
        self.trailing = trailing()
        self.onSelect = onSelect
        self.namespace = namespace
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            HomeSectionHeader(title: title, subtitle: subtitle) {
                trailing
            }

            if items.isEmpty, let emptyMessage {
                HomeEmptyRail(message: emptyMessage, systemImage: emptySystemImage)
            } else {
                roomScroll
            }
        }
    }

    private var roomScroll: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: AppConstants.Spacing.lg) {
                ForEach(items) { item in
                    Button {
                        onSelect(item.room)
                    } label: {
                        LiveRoomCard(
                            room: item.room,
                            width: cardWidth,
                            liveCheckMode: .none,
                            subtitle: item.detail,
                            disableTapGesture: true
                        )
                        .environment(\.roomTransitionNamespace, namespace)
                    }
                    .buttonStyle(HomeCardButtonStyle())
                    .accessibilityLabel("\(item.room.roomTitle)，\(item.room.userName)")
                    .accessibilityHint("打开播放页")
                }
            }
            .padding(.horizontal, AppConstants.Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }
}

private struct HomeSectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(
        title: String,
        subtitle: String?,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppConstants.Spacing.md) {
            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppConstants.Colors.primaryText)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: AppConstants.Spacing.sm)
            trailing
        }
        .padding(.horizontal, AppConstants.Spacing.xl)
    }
}

private struct HomeEmptyRail: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(AppConstants.Colors.tertiaryText)
                .frame(width: 34, height: 34)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppConstants.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppConstants.Spacing.xl)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeSeeAllLabel: View {
    var body: some View {
        HStack(spacing: AppConstants.Spacing.xs) {
            Text("查看全部")
            Image(systemName: "chevron.right")
                .font(.caption.bold())
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppConstants.Colors.secondaryText)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeHeroCarousel: View {
    let entries: [HomeBannerEntry]
    let containerWidth: CGFloat
    let onOpenRoom: (LiveModel) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedBannerID: String?

    private let pageInset: CGFloat = 0
    private let cardSpacing: CGFloat = 0

    private var viewportWidth: CGFloat {
        max(containerWidth, 280)
    }

    private var cardWidth: CGFloat {
        viewportWidth
    }

    private var cardHeight: CGFloat {
        min(viewportWidth / AppConstants.AspectRatio.pic, 320)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal) {
                HStack(spacing: cardSpacing) {
                    ForEach(entries) { entry in
                        heroPage(for: entry)
                            .frame(width: cardWidth, height: cardHeight)
                            .id(entry.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $selectedBannerID)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .frame(width: viewportWidth, height: cardHeight)
            .background(.black)

            if entries.count > 1 {
                HomeHeroPageIndicator(entries: entries, selectedID: selectedBannerID)
                    .padding(.top, 52)
                    .padding(.trailing, AppConstants.Spacing.lg)
            }
        }
        .frame(height: cardHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .onAppear(perform: normalizeSelection)
        .onChange(of: entries.map(\.id)) { _, _ in normalizeSelection() }
        .task(id: autoplayTaskID) {
            await runAutoplayIfNeeded()
        }
    }

    private var autoplayTaskID: String {
        "\(entries.map(\.id).joined(separator: "|"))::\(selectedBannerID ?? "")::\(scenePhase)::\(reduceMotion)"
    }

    private func normalizeSelection() {
        guard !entries.isEmpty else {
            selectedBannerID = nil
            return
        }
        if !entries.contains(where: { $0.id == selectedBannerID }) {
            selectedBannerID = entries[0].id
        }
    }

    @MainActor
    private func runAutoplayIfNeeded() async {
        guard entries.count > 1, scenePhase == .active, !reduceMotion else { return }

        do {
            try await Task.sleep(for: .seconds(6))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        let currentIndex = entries.firstIndex { $0.id == selectedBannerID } ?? 0
        let nextIndex = entries.index(after: currentIndex) == entries.endIndex
            ? entries.startIndex
            : entries.index(after: currentIndex)
        withAnimation(.smooth(duration: 0.45)) {
            selectedBannerID = entries[nextIndex].id
        }
    }

    @ViewBuilder
    private func heroPage(for entry: HomeBannerEntry) -> some View {
        heroDestination(for: entry)
            .frame(width: cardWidth, height: cardHeight)
            .clipped()
    }

    @ViewBuilder
    private func heroDestination(for entry: HomeBannerEntry) -> some View {
        switch entry.banner.target {
        case .room(let room):
            Button { onOpenRoom(room) } label: {
                HomeHeroCard(
                    entry: entry,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    pageInset: pageInset,
                    cardSpacing: cardSpacing
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开播放页")
        case .category(let category):
            NavigationLink(
                value: HomeCategoryRoute(
                    pluginId: entry.pluginId,
                    liveType: entry.liveType,
                    category: category,
                    fallbackTitle: entry.banner.title
                )
            ) {
                HomeHeroCard(
                    entry: entry,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    pageInset: pageInset,
                    cardSpacing: cardSpacing
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开分类")
        }
    }
}

private struct HomeHeroCard: View {
    let entry: HomeBannerEntry
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let pageInset: CGFloat
    let cardSpacing: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The page remains fixed at the viewport width. Only its bitmap moves,
        // driven by the page's position in the horizontal scroll view. A small
        // uniform zoom supplies safe overscan for a full-width 16:9 banner.
        let imageScale: CGFloat = reduceMotion ? 1 : 1.16
        let parallaxTravel = cardWidth * (imageScale - 1) / 2

        ZStack {
            HomeHeroRemoteImage(url: entry.banner.imageURL)
                .frame(width: cardWidth, height: cardHeight)
                .visualEffect { content, proxy in
                    content
                        .scaleEffect(imageScale)
                        .offset(
                            x: parallaxOffset(
                                for: proxy,
                                pageInset: pageInset,
                                pageStride: cardWidth + cardSpacing,
                                travel: parallaxTravel
                            )
                        )
                }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.34),
                    .init(color: .black.opacity(0.12), location: 0.56),
                    .init(color: .black.opacity(0.86), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                Spacer(minLength: 0)

                if let badge = entry.banner.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.82))
                }

                Text(entry.banner.title)
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                if let subtitle = entry.banner.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }

                Text(entry.pluginDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppConstants.Spacing.lg)
        }
        .clipped()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.banner.title)，来自 \(entry.pluginDisplayName)")
    }

    nonisolated private func parallaxOffset(
        for proxy: GeometryProxy,
        pageInset: CGFloat,
        pageStride: CGFloat,
        travel: CGFloat
    ) -> CGFloat {
        let pageMinX = proxy.frame(
            in: .scrollView(axis: .horizontal)
        ).minX - pageInset
        let pageProgress = min(
            max(pageMinX / max(pageStride, 1), -1),
            1
        )
        return -pageProgress * travel
    }
}

private struct HomeHeroRemoteImage: View {
    let url: URL?

    var body: some View {
        if let url {
            KFImage(url)
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 1200, height: 675)))
                .placeholder { placeholder }
                .fade(duration: 0.2)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(AppConstants.Colors.placeholderGradient())
            .overlay {
                Image(systemName: "sparkles.tv.fill")
                    .font(.title2)
                    .foregroundStyle(AppConstants.Colors.placeholderText)
            }
    }
}

private struct HomeHeroPageIndicator: View {
    let entries: [HomeBannerEntry]
    let selectedID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            ForEach(entries) { entry in
                Capsule()
                    .fill(entry.id == selectedID ? .white : .white.opacity(0.42))
                    .frame(width: entry.id == selectedID ? 24 : 7, height: 7)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: selectedID)
        .accessibilityHidden(true)
    }
}

private struct HomeHeroLoadingCard: View {
    let containerWidth: CGFloat

    private var viewportWidth: CGFloat {
        max(containerWidth, 280)
    }

    var body: some View {
        Rectangle()
            .fill(AppConstants.Colors.placeholderGradient())
            .frame(width: viewportWidth, height: min(viewportWidth / AppConstants.AspectRatio.pic, 320))
            .overlay {
                VStack(spacing: AppConstants.Spacing.md) {
                    ProgressView()
                    Text("正在加载首页内容")
                        .font(.subheadline)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("正在加载首页内容")
    }
}

private struct HomeCompactHeader: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.42), Color.accentColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [.clear, AppConstants.Colors.primaryBackground],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text("首页")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppConstants.Colors.primaryText)
                Text("你的直播与播放入口")
                    .font(.subheadline)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
            .padding(.horizontal, AppConstants.Spacing.xl)
            .padding(.bottom, AppConstants.Spacing.xl)
        }
        .frame(height: 138)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeRemoteImage: View {
    let url: URL?
    let symbolName: String

    var body: some View {
        Group {
            if let url {
                KFImage(url)
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 960, height: 540)))
                    .placeholder { placeholder }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        Rectangle()
            .fill(AppConstants.Colors.placeholderGradient())
            .overlay {
                Image(systemName: symbolName)
                    .font(.title2)
                    .foregroundStyle(AppConstants.Colors.placeholderText)
            }
    }
}

private struct HomeFeedFailureCard: View {
    let pluginNames: [String]
    let isRefreshing: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(AppConstants.Colors.warning)

            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text("部分首页内容暂不可用")
                    .font(.subheadline.weight(.semibold))
                Text(pluginNames.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Button("重试", action: retry)
                .disabled(isRefreshing)
                .frame(minHeight: 44)
        }
        .padding(AppConstants.Spacing.lg)
        .background(
            AppConstants.Colors.secondaryBackground,
            in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
        )
        .padding(.horizontal, AppConstants.Spacing.xl)
    }
}

private struct HomeConfigurationGuide: View {
    var body: some View {
        VStack(spacing: AppConstants.Spacing.lg) {
            Image(systemName: "square.stack.3d.up.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.tint)

            VStack(spacing: AppConstants.Spacing.xs) {
                Text("配置你的首页")
                    .font(.headline)
                Text("添加内容源后，首页会展示它们提供的焦点内容和直播分区。")
                    .font(.subheadline)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            NavigationLink {
                AdaptivePlatformView()
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                Text("前往配置")
                    .font(.headline)
                    .frame(minWidth: 120, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(AppConstants.Spacing.xxl)
        .background(
            AppConstants.Colors.secondaryBackground,
            in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl)
        )
        .padding(.horizontal, AppConstants.Spacing.xl)
    }
}

private struct HomeCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.18),
                value: configuration.isPressed
            )
    }
}

struct HomeCategoryRoute: Hashable {
    let pluginId: String
    let liveType: LiveType
    let categoryID: String
    let parentID: String
    let title: String
    let icon: String
    let biz: String?

    init(
        pluginId: String,
        liveType: LiveType,
        category: LiveCategoryModel,
        fallbackTitle: String
    ) {
        self.pluginId = pluginId
        self.liveType = liveType
        categoryID = category.id
        parentID = category.parentId
        title = category.title.isEmpty ? fallbackTitle : category.title
        icon = category.icon
        biz = category.biz
    }
}

private struct HomeCategoryView: View {
    let route: HomeCategoryRoute
    let navigationState: LiveRoomNavigationState
    let namespace: Namespace.ID
    @State private var model: HomeCategoryViewModel

    init(
        route: HomeCategoryRoute,
        navigationState: LiveRoomNavigationState,
        namespace: Namespace.ID
    ) {
        self.route = route
        self.navigationState = navigationState
        self.namespace = namespace
        _model = State(initialValue: HomeCategoryViewModel(route: route))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 154, maximum: 280), spacing: AppConstants.Spacing.lg)],
                spacing: AppConstants.Spacing.xl
            ) {
                ForEach(model.rooms) { room in
                    Button {
                        navigationState.navigate(to: room, categoryRooms: model.rooms)
                    } label: {
                        LiveRoomCard(
                            room: room,
                            width: model.cardWidth,
                            liveCheckMode: .none,
                            disableTapGesture: true
                        )
                        .environment(\.roomTransitionNamespace, namespace)
                    }
                    .buttonStyle(HomeCardButtonStyle())
                    .onAppear {
                        loadMoreIfNeeded(after: room)
                    }
                }
            }
            .padding(AppConstants.Spacing.xl)

            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(AppConstants.Spacing.xl)
            } else if model.rooms.isEmpty {
                ContentUnavailableView(
                    "暂无直播间",
                    systemImage: "rectangle.stack.badge.questionmark",
                    description: Text(model.errorMessage ?? "当前分类暂时没有可显示的内容。")
                )
                .padding(.vertical, 80)
            }
        }
        .background(AppConstants.Colors.groupedBackground)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await model.load(refresh: true) }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            model.updateCardWidth(containerWidth: width)
        }
        .task { await model.load(refresh: true) }
    }

    private func loadMoreIfNeeded(after room: LiveModel) {
        guard room.id == model.rooms.last?.id else { return }
        Task { await model.loadMore() }
    }
}

@MainActor
@Observable
private final class HomeCategoryViewModel {
    private(set) var rooms: [LiveModel] = []
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var errorMessage: String?
    private(set) var cardWidth: CGFloat = 170

    @ObservationIgnored private let route: HomeCategoryRoute
    @ObservationIgnored private var page = 1

    init(route: HomeCategoryRoute) {
        self.route = route
    }

    func updateCardWidth(containerWidth: CGFloat) {
        let usableWidth = max(154, containerWidth - AppConstants.Spacing.xl * 2)
        let columnCount = max(1, Int((usableWidth + AppConstants.Spacing.lg) / 190))
        let spacing = AppConstants.Spacing.lg * CGFloat(max(0, columnCount - 1))
        cardWidth = min(280, (usableWidth - spacing) / CGFloat(columnCount))
    }

    func load(refresh: Bool) async {
        guard !isLoading else { return }
        if refresh {
            page = 1
            hasMore = true
            errorMessage = nil
        } else if !hasMore {
            return
        }

        guard let platform = LiveParseJSPlatformManager.platform(forPluginId: route.pluginId) else {
            errorMessage = "对应内容源已不可用。"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let context: [String: Any] = [
                "category": [
                    "id": route.categoryID,
                    "parentId": route.parentID,
                    "title": route.title,
                    "icon": route.icon,
                    "biz": route.biz ?? ""
                ]
            ]
            let fetched = try await LiveParseJSPlatformManager.getRoomList(
                platform: platform,
                id: route.categoryID,
                parentId: route.parentID,
                page: page,
                context: context
            )
            hasMore = !fetched.isEmpty
            if refresh {
                rooms = fetched.removingDuplicates()
            } else {
                rooms = rooms.appendingUnique(contentsOf: fetched)
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        page += 1
        await load(refresh: false)
        if errorMessage != nil {
            page = max(1, page - 1)
        }
    }
}
