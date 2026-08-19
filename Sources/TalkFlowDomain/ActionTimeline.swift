import Foundation

/// One point the pipeline passes on its way from a new message to a sent reply.
///
/// Named after what the user would say happened, not after the function that
/// ran: 「모델 답변 받음」 is a thing somebody waiting can picture, and
/// `generateReply(_:) returned` is not. The whole point of recording these is
/// that a person who thinks TalkFlow is slow can see which of them the time went
/// into, so the names have to be readable by somebody who has not read the code.
public enum ActionStage: String, Codable, Equatable, Sendable {
    /// KakaoTalk's database was seen to move.
    case detected
    /// The archive finished catching up, so the new messages are readable.
    case synchronized
    /// The deterministic rules decided this room was worth asking about.
    case judged
    /// 뒷말 대기 elapsed. Absent when the message did not look unfinished.
    case followUpWaited
    /// Photos extracted and the room's standing note read — everything the
    /// prompt carries besides the conversation itself.
    case contextPrepared
    /// The provider was asked. The gap after this one is the model's own time
    /// plus whatever the CLI spends starting up.
    case modelRequested
    /// The answer came back and parsed.
    case modelAnswered
    /// The draft went into the send queue.
    case queued
    /// The queue accepted the draft and started typing it into KakaoTalk.
    case sendAttempted
    /// KakaoTalk took the message.
    case sent
    /// The draft was dropped before it went out. Carries the reason.
    ///
    /// Its own stage rather than a kind of failure because the two need opposite
    /// readings: a cancelled draft means the rules worked, and by far the most
    /// common reason is that the conversation moved on while the model was still
    /// thinking — which is a statement about how long the thinking took, and the
    /// reason this stage is worth the gap it shows.
    case cancelled
    /// The stage that was running when it went wrong. Carries its own note.
    case failed

    /// Where this stage falls in the pipeline, used to break ties.
    ///
    /// Two stamps can share an instant — the clock has finite resolution and the
    /// steps between a model answering and its draft being queued are a few
    /// microseconds of local work. Sorting on time alone then leaves the order to
    /// whatever the sort algorithm does with equal keys, which is not stable, and
    /// a pane that shows 채팅창 입력 시작 above 모델 답변 받음 is telling the user
    /// the app sent a reply before it had one.
    var order: Int {
        switch self {
        case .detected: 0
        case .synchronized: 1
        case .judged: 2
        case .followUpWaited: 3
        case .contextPrepared: 4
        case .modelRequested: 5
        case .modelAnswered: 6
        case .queued: 7
        case .sendAttempted: 8
        case .sent: 9
        case .cancelled: 10
        case .failed: 11
        }
    }

    public var title: String {
        switch self {
        case .detected: "변경 감지"
        case .synchronized: "동기화 완료"
        case .judged: "규칙 판단 완료"
        case .followUpWaited: "뒷말 대기 완료"
        case .contextPrepared: "문맥 준비 완료"
        case .modelRequested: "모델 호출"
        case .modelAnswered: "모델 답변 받음"
        case .queued: "전송 대기열 등록"
        case .sendAttempted: "채팅창 입력 시작"
        case .sent: "전송 완료"
        case .cancelled: "전송 취소"
        case .failed: "실패"
        }
    }
}

/// When each stage of one reply finished, in the order they happened.
///
/// Written alongside the action rather than into a log, because a duration is
/// only ever asked about next to the thing it describes: the question is always
/// "왜 이 답장이 늦었나", never "지난 화요일의 모델 호출 시간 분포는".
///
/// A reply is recorded across more than one row — the draft when the model
/// answers, the delivery when the queue lets it out — so each row carries the
/// part it witnessed and `merging(_:)` puts them back together for the screen.
/// That keeps the write path append-only: no row is ever revisited to have a
/// later stage added to it.
public struct ActionTimeline: Codable, Equatable, Sendable {
    public struct Step: Codable, Equatable, Sendable {
        public let stage: ActionStage
        public let at: Date
        /// What is worth saying about this stage beyond its name — the reason a
        /// send sat in the queue, the error a failure carried. Nil for the
        /// stages that speak for themselves.
        public let note: String?

        public init(stage: ActionStage, at: Date, note: String? = nil) {
            self.stage = stage
            self.at = at
            self.note = note
        }
    }

    public private(set) var steps: [Step]

    public init(steps: [Step] = []) {
        self.steps = Self.ordered(steps)
    }

    /// By time, then by where the stage falls in the pipeline. The second key is
    /// what keeps a tie from reordering the story — see `ActionStage.order`.
    private static func ordered(_ steps: [Step]) -> [Step] {
        steps.sorted {
            $0.at == $1.at ? $0.stage.order < $1.stage.order : $0.at < $1.at
        }
    }

    public var isEmpty: Bool { steps.isEmpty }

    public var startedAt: Date? { steps.first?.at }
    public var finishedAt: Date? { steps.last?.at }

    /// Nil rather than zero for a timeline with one step: a single stamp records
    /// that something happened, not that it took no time.
    public var duration: TimeInterval? {
        guard let startedAt, let finishedAt, steps.count > 1 else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    /// Adds a stage, keeping the list in time order.
    ///
    /// A repeated stage replaces the earlier stamp instead of appending a second
    /// one. The queue re-reads a waiting draft every ten seconds, and without
    /// this a draft that waited two minutes would carry a dozen identical
    /// 「전송 대기열 등록」 rows and bury the one line that explains the wait.
    public mutating func stamp(_ stage: ActionStage, at date: Date = Date(), note: String? = nil) {
        steps.removeAll { $0.stage == stage }
        steps.append(Step(stage: stage, at: date, note: note))
        steps = Self.ordered(steps)
    }

    public func stamping(_ stage: ActionStage, at date: Date = Date(), note: String? = nil) -> ActionTimeline {
        var copy = self
        copy.stamp(stage, at: date, note: note)
        return copy
    }

    /// Folds another row's stages into this one.
    ///
    /// The later record wins on a stage both carry, because the row written
    /// later saw that stage more recently — the queue stamps 전송 대기열 등록 from
    /// the entry's own creation time, which is the same instant the draft row
    /// recorded, so either answer is right and taking one keeps the list from
    /// growing a duplicate.
    public func merging(_ other: ActionTimeline) -> ActionTimeline {
        guard !other.isEmpty else { return self }
        var merged = self
        for step in other.steps {
            merged.stamp(step.stage, at: step.at, note: step.note)
        }
        return merged
    }

    /// Each stage with how long the pipeline spent getting to it.
    ///
    /// The first stage has no elapsed time — nothing preceded it — which is why
    /// this is nil rather than zero there. Zero would read as "instant" and the
    /// truth is "unknown, this is where the clock started".
    public var spans: [Span] {
        var previous: Date?
        return steps.map { step in
            let elapsed = previous.map { step.at.timeIntervalSince($0) }
            previous = step.at
            return Span(stage: step.stage, at: step.at, elapsed: elapsed, note: step.note)
        }
    }

    public struct Span: Equatable, Sendable {
        public let stage: ActionStage
        public let at: Date
        /// Time since the previous stage. Nil on the first.
        public let elapsed: TimeInterval?
        public let note: String?
    }

    /// The stage that took longest, so the screen can point at it rather than
    /// leaving the user to compare ten numbers themselves.
    ///
    /// Nil when nothing stands out — a timeline of one step, or one where every
    /// gap is under a second and naming a winner would be noise.
    public var slowestStage: ActionStage? {
        let candidates = spans.filter { ($0.elapsed ?? 0) >= 1 }
        return candidates.max { ($0.elapsed ?? 0) < ($1.elapsed ?? 0) }?.stage
    }

    /// How far this got, in the four steps somebody scanning the 활동 목록 cares
    /// about.
    ///
    /// Coarser than `ActionStage` on purpose. Twelve stages is the right grain for
    /// "왜 이 답장이 늦었나" next to one reply, and the wrong grain for a row of
    /// checkboxes: 동기화 완료 and 문맥 준비 완료 are steps nobody filters by, and a
    /// bar offering them buries the division that matters. That division is
    /// whether the model was asked, because it separates the holds that cost
    /// nothing from the holds that cost a call — 3,249 against 1,221 on this
    /// account, indistinguishable on screen until now.
    public var reach: ActionReach {
        let stages = Set(steps.map(\.stage))
        if stages.contains(.sent) { return .sent }
        if stages.contains(.modelAnswered) { return .answered }
        if stages.contains(.modelRequested) { return .requested }
        if stages.contains(.judged) || stages.contains(.detected) { return .judged }
        // A row from before these stamps existed, or one written by a path that
        // does not stamp at all. Named rather than folded into 판단, because
        // guessing would put 5,877 stamped rows and a thousand unstamped ones in
        // one bucket and call it a measurement.
        return .unrecorded
    }
}

/// The furthest point one recorded action got to.
public enum ActionReach: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    /// The rules looked and stopped. No call, no cost — 최소 응답 간격 and the
    /// hours gates land here, and they are most of the record.
    case judged
    /// The model was asked and the answer never arrived. A hung call, a crash, a
    /// provider error: the case that leaves nothing behind today.
    case requested
    /// The model answered. Whether that answer became a draft or a 보류 is the
    /// other axis — this one says the call was paid for.
    case answered
    /// It reached KakaoTalk.
    case sent
    /// No stages recorded.
    case unrecorded

    public var id: Self { self }

    public var title: String {
        switch self {
        case .judged: "판단까지"
        case .requested: "요청까지"
        case .answered: "답변까지"
        case .sent: "전송까지"
        case .unrecorded: "기록 없음"
        }
    }

    /// One line for the filter bar's help, said as what it excludes rather than
    /// what it is — a checkbox is read by what disappears when it is unticked.
    public var explanation: String {
        switch self {
        case .judged: "모델을 부르지 않고 규칙만 보고 멈춘 것입니다. 비용이 들지 않습니다."
        case .requested: "모델을 불렀는데 답이 돌아오지 않은 것입니다."
        case .answered: "모델이 답한 것입니다. 초안이 됐거나 보류됐습니다."
        case .sent: "카카오톡까지 나간 것입니다."
        case .unrecorded: "단계가 기록되기 전에 남은 오래된 기록입니다."
        }
    }
}
