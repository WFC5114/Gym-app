import SwiftUI

@main
struct GymApp: App {
    @State private var model: MachineModel
    @State private var health = HealthStore()
    private let mode: LaunchMode

    init() {
        let mode = LaunchMode.from(ProcessInfo.processInfo.arguments)
        self.mode = mode
        _model = State(initialValue: Fixtures.makeModel(for: mode))
    }

    var body: some Scene {
        WindowGroup {
            MachineView(model: model)
                .dynamicTypeSize(mode == .fixture("a11y-xxl") ? DynamicTypeSize.accessibility3 ... .accessibility3 : DynamicTypeSize.xSmall ... .accessibility5)
                .task {
                    // Only the real app asks for Health; demo and fixtures never show a prompt.
                    guard mode == .live else { return }
                    await health.requestAccessAndLoad()
                    model.readiness = await health.readiness()
                    model.refreshAdvice()
                    model.setBodyHistory(await health.bodyHistory())
                    model.store.settleElapsedRests(now: .now)
                    model.syncGlassImmediately()
                }
        }
    }
}
