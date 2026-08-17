//
//  ShellConfigView.swift
//  AngelLive
//
//  壳 UI - 配置页：统一输入框，自动识别视频链接或订阅地址。
//

import SwiftUI
import AngelLiveCore

struct ShellConfigView: View {
    @Environment(StreamBookmarkService.self) private var bookmarkService
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(PluginAvailabilityService.self) private var pluginAvailability

    @State private var inputURL = ""
    @State private var inputTitle = ""
    @State private var showContentList = false
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            List {
                addSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("配置")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showContentList) {
                SubscriptionContentSheet(
                    pluginSourceManager: pluginSourceManager,
                    pluginAvailability: pluginAvailability
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - 添加

    private var trimmedURL: String {
        inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSubscriptionURL: Bool {
        guard !trimmedURL.isEmpty else { return false }
        if let url = URL(string: trimmedURL) {
            return url.pathExtension.lowercased() == "json"
        }
        return trimmedURL.lowercased().hasSuffix(".json")
    }

    private var addSection: some View {
        Section {
            TextField("标题（可选）", text: $inputTitle)

            TextField("输入地址", text: $inputURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocapitalization(.none)

            Button {
                handleAdd()
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppConstants.Colors.success.gradient)
                    }
                    Text("添加")
                }
            }
            .disabled(trimmedURL.isEmpty || isProcessing)

            if let error = pluginSourceManager.errorMessage {
                PluginSourceErrorCard(title: "插件源异常", message: error)
            }
        } header: {
            Text("添加视频或订阅")
        } footer: {
            Text("输入视频地址添加到收藏，可在收藏页直接播放")
        }
    }

    private func handleAdd() {
        let url = trimmedURL
        let title = inputTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldTreatAsSubscription = isSubscriptionURL
        guard !url.isEmpty else { return }

        isProcessing = true
        Task {
            if shouldTreatAsSubscription {
                let addedURLs = await pluginSourceManager.addSourceFromInput(url)
                if !addedURLs.isEmpty {
                    inputURL = ""
                    inputTitle = ""
                    showContentList = true
                }
            } else {
                let addedURLs = await pluginSourceManager.addSourceWithKeyResolution(url)
                if !addedURLs.isEmpty {
                    inputURL = ""
                    inputTitle = ""
                    showContentList = true
                } else if pluginSourceManager.errorMessage == nil {
                    await bookmarkService.add(title: title.isEmpty ? url : title, url: url)
                    inputURL = ""
                    inputTitle = ""
                }
            }
            isProcessing = false
        }
    }

}

// MARK: - 订阅内容列表

struct SubscriptionContentSheet: View {
    let pluginSourceManager: PluginSourceManager
    let pluginAvailability: PluginAvailabilityService
    @Environment(\.dismiss) private var dismiss

    private var shouldShowEmptyState: Bool {
        !pluginSourceManager.isFetchingIndex
            && pluginSourceManager.errorMessage == nil
            && pluginSourceManager.remotePlugins.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if shouldShowEmptyState {
                    ErrorView.empty(
                        title: "暂无可用内容",
                        message: "暂时没有可安装的订阅内容，稍后刷新再试。",
                        symbolName: "tray.circle",
                        tint: .cyan
                    )
                } else {
                    List {
                        if let error = pluginSourceManager.errorMessage {
                            Section {
                                PluginSourceErrorCard(title: "插件源异常", message: error)
                            }
                        }

                        if pluginSourceManager.isFetchingIndex {
                            Section {
                                HStack(spacing: AppConstants.Spacing.sm) {
                                    ProgressView()
                                    Text("正在加载订阅...")
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                }
                                .padding(.vertical, AppConstants.Spacing.xs)
                            }
                        } else {
                            ForEach(pluginSourceManager.remotePlugins) { item in
                                contentRow(item)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("订阅内容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if pluginSourceManager.installTotalCount > 0 {
                        HStack(spacing: AppConstants.Spacing.xs) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("\(pluginSourceManager.installCompletedCount)/\(pluginSourceManager.installTotalCount)")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                    } else {
                        Button("全部安装") {
                            installAllPlugins()
                        }
                        .disabled(!canInstallAll)
                    }
                }
            }
        }
        .task {
            // 在 sheet 生命周期内刷新版本映射，已安装插件可直接出现“更新”。
            await pluginSourceManager.refreshAvailableUpdates()
        }
    }

    private func contentRow(_ item: RemotePluginDisplayItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.body)
                        .foregroundStyle(AppConstants.Colors.primaryText)
                    if item.item.auth?.required == true
                        || pluginAvailability.requiresLogin(for: item.id) {
                        RequiresLoginTag()
                    }
                }

                Text("v\(item.item.version)")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }

            Spacer()

            itemStateView(item)
        }
        .padding(.vertical, AppConstants.Spacing.xs)
    }

    @ViewBuilder
    private func itemStateView(_ item: RemotePluginDisplayItem) -> some View {
        switch pluginSourceManager.catalogActionState(for: item) {
        case .failed(let error):
            VStack(alignment: .trailing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppConstants.Colors.warning)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(AppConstants.Colors.error)
                    .lineLimit(2)
            }
        case .install:
            catalogActionButton(title: "安装") {
                let success = await pluginSourceManager.installPlugin(item)
                if success {
                    await pluginAvailability.refresh()
                    await pluginSourceManager.refreshAvailableUpdates()
                }
            }
        case .update:
            catalogActionButton(title: "更新") {
                let success = await pluginSourceManager.updatePlugin(pluginId: item.id)
                if success {
                    await pluginAvailability.refresh()
                    await pluginSourceManager.refreshAvailableUpdates()
                }
            }
            .accessibilityLabel("更新插件")
        case .installing:
            HStack(spacing: AppConstants.Spacing.xs) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("安装中")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        case .updating:
            HStack(spacing: AppConstants.Spacing.xs) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("更新中")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppConstants.Colors.success)
        }
    }

    private func catalogActionButton(title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, AppConstants.Spacing.sm)
                .padding(.vertical, AppConstants.Spacing.xs)
                .background(AppConstants.Colors.link)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
    }

    private var canInstallAll: Bool {
        !pluginSourceManager.isInstalling &&
        pluginSourceManager.remotePlugins.contains {
            pluginSourceManager.catalogActionState(for: $0) == .install
        }
    }

    private func installAllPlugins() {
        guard canInstallAll else { return }
        Task {
            let count = await pluginSourceManager.installAll()
            if count > 0 {
                await pluginAvailability.refresh()
            }
        }
    }
}
