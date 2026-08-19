import TalkFlowDomain

public struct ObserveKakaoSync: Sendable {
    private let source: any KakaoSyncSource

    public init(source: any KakaoSyncSource) {
        self.source = source
    }

    public func callAsFunction() async -> AsyncStream<KakaoSyncEvent> {
        await source.events()
    }
}
