import Testing
@testable import AngelLiveCore

@Suite("Remote plugin catalog action state")
struct RemotePluginCatalogActionStateTests {

    @Test("installed plugins expose updates directly in an open catalog")
    func installedPluginCanUpdate() {
        #expect(resolve(.installed, installed: true, hasUpdate: true) == .update)
        #expect(resolve(.notInstalled, installed: true, hasUpdate: true) == .update)
    }

    @Test("an installed plugin without a newer version stays installed")
    func installedPluginWithoutUpdate() {
        #expect(resolve(.installed, installed: true) == .installed)
        #expect(resolve(.notInstalled, installed: true) == .installed)
    }

    @Test("active operations take precedence over stale row state")
    func activeOperationWins() {
        #expect(resolve(.installed, installed: true, hasUpdate: true, updating: true) == .updating)
        #expect(resolve(.installing, installed: false) == .installing)
    }

    @Test("new and failed plugins keep their install states")
    func installAndFailureStates() {
        #expect(resolve(.notInstalled, installed: false) == .install)
        #expect(resolve(.failed("network"), installed: false) == .failed("network"))
    }

    private func resolve(
        _ installState: PluginInstallState,
        installed: Bool,
        hasUpdate: Bool = false,
        updating: Bool = false
    ) -> RemotePluginCatalogActionState {
        .resolve(
            installState: installState,
            isInstalled: installed,
            hasUpdate: hasUpdate,
            isUpdating: updating
        )
    }
}
