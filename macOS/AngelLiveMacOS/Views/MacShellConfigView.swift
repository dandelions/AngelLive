import SwiftUI
import AngelLiveCore

struct MacShellConfigView: View {
    @Environment(StreamBookmarkService.self) private var bookmarkService
    @Environment(PluginSourceManager.self) private var pluginSourceManager
    @Environment(PluginAvailabilityService.self) private var pluginAvailability

    @State private var inputURL = ""
    @State private var inputTitle = ""
    @State private var showContentSheet = false
    @State private var isProcessing = false

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

    var body: some View {
        Form {
            addSection
        }
        .formStyle(.grouped)
        .navigationTitle("配置")
        .sheet(isPresented: $showContentSheet) {
            MacSubscriptionContentSheet(
                pluginSourceManager: pluginSourceManager,
                pluginAvailability: pluginAvailability
            )
            .frame(minWidth: 620, minHeight: 480)
        }
    }

    private var addSection: some View {
        Section {
            PanelHintCard(
                title: "添加视频或订阅",
                message: "输入直播链接可直接加入收藏；输入订阅源地址时，会自动检查远程内容并展示可安装扩展。",
                systemImage: "square.and.arrow.down.on.square",
                tint: .accentColor
            )

            TextField("标题（可选）", text: $inputTitle)
            TextField("输入地址", text: $inputURL)

            Button {
                handleAdd()
            } label: {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: isSubscriptionURL ? "tray.and.arrow.down.fill" : "plus.circle.fill")
                    }
                    Text(isSubscriptionURL ? "添加并检查订阅" : "添加内容")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(trimmedURL.isEmpty || isProcessing)

            if let error = pluginSourceManager.errorMessage {
                PluginSourceErrorCard(title: "插件源异常", message: error)
            }
        } header: {
            Text("添加视频或订阅")
        } footer: {
            Text("输入视频地址可在收藏页直接播放；输入订阅地址后会在弹窗里继续处理安装。")
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
                    showContentSheet = true
                }
            } else {
                let addedURLs = await pluginSourceManager.addSourceWithKeyResolution(url)
                if !addedURLs.isEmpty {
                    inputURL = ""
                    inputTitle = ""
                    showContentSheet = true
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

private struct MacSubscriptionContentSheet: View {
    let pluginSourceManager: PluginSourceManager
    let pluginAvailability: PluginAvailabilityService
    @Environment(\.dismiss) private var dismiss
    @Environment(PluginInstallConsentService.self) private var consentService
    private let rowInsets = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)

    var body: some View {
        @Bindable var consent = consentService

        NavigationStack {
            List {
                if let error = pluginSourceManager.errorMessage {
                    PluginSourceErrorCard(title: "插件源异常", message: error)
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)
                }

                if pluginSourceManager.isFetchingIndex {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载订阅...")
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets)
                } else if pluginSourceManager.remotePlugins.isEmpty {
                    ErrorView.empty(
                        title: "暂无可用内容",
                        message: "当前订阅里还没有可安装内容，可以稍后刷新或更换订阅源。",
                        symbolName: "tray",
                        tint: .secondary,
                        layout: .compact(minHeight: 180)
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets)
                } else {
                    ForEach(pluginSourceManager.remotePlugins) { item in
                        contentRow(item)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .navigationTitle("订阅内容")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if pluginSourceManager.installTotalCount > 0 {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
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
            await pluginSourceManager.refreshAvailableUpdates()
        }
        .alert(consent.alertTitle, isPresented: $consent.isPresenting) {
            Button(consent.continueButtonTitle) { consent.resolve(true) }
            Button("取消", role: .cancel) { consent.resolve(false) }
        } message: {
            Text(consent.alertMessage)
        }
    }

    private func contentRow(_ item: RemotePluginDisplayItem) -> some View {
        PanelNavigationRow(
            title: item.displayName,
            subtitle: "版本 \(item.item.version)",
            showsChevron: false
        ) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.orange.gradient)
        } titleAccessory: {
            if item.item.auth?.required == true
                || pluginAvailability.requiresLogin(for: item.id) {
                RequiresLoginTag()
            }
        } trailing: {
            itemStateView(item)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .listRowInsets(rowInsets)
    }

    @ViewBuilder
    private func itemStateView(_ item: RemotePluginDisplayItem) -> some View {
        switch pluginSourceManager.catalogActionState(for: item) {
        case .failed(let error):
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppConstants.Colors.warning)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(AppConstants.Colors.error)
                    .lineLimit(2)
            }

        case .install:
            installActionButton(title: "安装") {
                let success = await pluginSourceManager.installPlugin(item)
                if success {
                    await pluginAvailability.refresh()
                    await pluginSourceManager.refreshAvailableUpdates()
                }
            }
        case .update:
            installActionButton(title: "更新") {
                let success = await pluginSourceManager.updatePlugin(pluginId: item.id)
                if success {
                    await pluginAvailability.refresh()
                    await pluginSourceManager.refreshAvailableUpdates()
                }
            }
        case .installing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("安装中")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        case .updating:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("更新中")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppConstants.Colors.success)
        }
    }

    private func installActionButton(title: String, action: @escaping () async -> Void) -> some View {
        Button(title) {
            Task { await action() }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
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
            await pluginSourceManager.refreshAvailableUpdates()
        }
    }
}
