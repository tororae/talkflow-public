import Foundation
import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// What this room is doing with the values it currently holds.
///
/// Titled and separate from the form because it answers a different question. The
/// `?` behind each setting says what that setting means in general; these lines
/// say what this room does now, with the combination it is set to — and several of
/// them exist because a combination cost or silenced something the screen used to
/// leave unexplained.
struct RoomBehaviourSummary: View {
    private let entry: ChatRoomPolicy
    private let cycle: JudgementCycle?

    init(entry: ChatRoomPolicy, cycle: JudgementCycle?) {
        self.entry = entry
        self.cycle = cycle
    }

    var body: some View {
        Section("지금 이 방의 동작") {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode)
                Text(interjection)
                Text(condition)
                Text(cadence)
                if let nextJudgement {
                    Text(nextJudgement)
                }
                Text(activeHours)
                Text(photos)
                Text(webSearch)
                Text(links)
                Text(memory)
                Text(opener)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var mode: String {
        switch entry.policy.responseMode {
        case .off:
            "이 방에서는 아무것도 하지 않습니다."
        case .detectOnly:
            // It used to promise that this mode records what 끔 does not. Nothing
            // in the pipeline reads the difference — collection is per account,
            // not per room — so the promise was the 낮음/보통 mistake again.
            "AI를 호출하거나 답을 만들지 않습니다. 대화 수집은 계정 단위라, 지금은 \"끔\"과 하는 일이 같습니다."
        case .mentionOnly:
            "\"이 방이 답하는 말\"에 있는 말로 부른 메시지에만 응답합니다."
        case .automatic:
            entry.room.kind == .direct
                ? "상대의 새 메시지마다 응답을 검토합니다."
                : "나를 부른 메시지에 응답하고, 그 외 메시지는 끼어들기 확률이 정합니다."
        }
    }

    /// What the dial in front of the user actually means for this room, and — in
    /// one line, not a lecture — what that combination costs.
    private var interjection: String {
        guard entry.room.kind == .group, entry.policy.responseMode == .automatic else {
            return "끼어들기 확률은 단체방 자동응답에서만 씁니다."
        }
        let chance = entry.policy.interjectionChance
        if chance.neverAsks {
            return "나를 부르지 않은 메시지는 AI에게 넘기지 않습니다. 부른 메시지만 답합니다."
        }
        if chance.asksEveryTime {
            return "나를 부르지 않은 메시지도 전부 AI에게 넘기고, 답할지는 AI가 정합니다. \(callCost)"
        }
        return """
        나를 부르지 않은 메시지 중 \(chance.summary)만 AI에게 넘기고, 나머지는 그냥 지나갑니다. \
        넘긴 것도 답할지는 AI가 정합니다. \(callCost)
        """
    }

    /// Says which of the two conditions is in force. A room following 설정 and a
    /// room with its own are otherwise indistinguishable here, and this list is
    /// what the user reads to answer "무엇에 답하나".
    private var condition: String {
        guard let own = entry.policy.answeringConditionOverride else {
            return "무엇에 답할지는 설정의 답변 조건을 따릅니다."
        }
        return own.isEmpty
            ? "이 방은 답변 조건 없이 판단합니다. 설정의 조건도 쓰지 않습니다."
            : "이 방만의 답변 조건으로 판단합니다: \(own.text)"
    }

    /// The line the user has to see before the bill does. The chance is the
    /// other lever, so the two are named together rather than each pointing
    /// somewhere else.
    private var callCost: String {
        entry.policy.judgesInBatches
            ? "호출은 \(counted)\(entry.policy.judgementInterval.summary) 한 번입니다."
            : "판단 주기가 \"즉시\"라 넘긴 메시지마다 호출 1회입니다."
    }

    /// Two settings bound how often this room answers, so the one in force says
    /// so and names the one it is standing in for.
    private var cadence: String {
        guard entry.policy.judgesInBatches else {
            return "새 메시지마다 판단합니다. 최소 응답 간격 안에 온 메시지는 건너뜁니다."
        }
        return """
        \(counted)\(entry.policy.judgementInterval.summary) 한 번만 판단하고, \
        그동안 쌓인 메시지를 한 번에 봅니다.\(spread) \
        이 방에서는 최소 응답 간격 대신 이 주기가 적용됩니다. \
        너무 길어지면 오래된 메시지부터 빼고 몇 개를 뺐는지 AI에게 알립니다.
        """
    }

    /// Whose messages the number counts. "10개마다" alone leaves the user to
    /// guess, and the guess that matters — whether their own typing brings the
    /// next answer closer — is the one they would get wrong.
    private var counted: String {
        entry.policy.judgementInterval.countsMessages ? "다른 사람의 메시지 " : ""
    }

    /// A varying cadence looks like a malfunction to anyone watching the clock,
    /// so the room says it is on purpose.
    private var spread: String {
        guard !entry.policy.judgementInterval.isFixed else { return "" }
        return entry.policy.judgementInterval.countsMessages
            ? " 주기마다 이 범위 안에서 세는 개수가 달라집니다."
            : " 주기마다 이 범위 안에서 기다리는 시간이 달라집니다."
    }

    /// A room in the middle of a cycle says nothing and records nothing, which
    /// from outside is what a broken room looks like. What ends the cycle is a
    /// fixed thing once it starts, so it can simply be shown.
    ///
    /// A time rather than a countdown: keeping a countdown honest would mean a
    /// timer redrawing this form every second, and one that quietly goes stale is
    /// worse than none. The second sentence is not padding — a room is only
    /// re-examined when it changes, so the batch waits for the next message
    /// rather than firing on the deadline by itself.
    ///
    /// A cycle counted in messages has no hour to name, so it names the number it
    /// drew instead. That is the part a range hides: 5개~15개 is a different
    /// number every cycle, and the room looks stuck to anybody who assumed the
    /// low end.
    private var nextJudgement: String? {
        guard entry.policy.judgesInBatches, let cycle else { return nil }
        switch cycle.ends {
        case let .at(due):
            guard due > Date() else {
                return "이번 주기는 이미 끝났습니다. 새 메시지가 오면 모아 둔 것을 한 번에 판단합니다."
            }
            return """
            이번 주기는 \(Self.clock.string(from: due))쯤 끝납니다. \
            그 뒤 새 메시지가 오면 모아 둔 것을 한 번에 판단합니다.
            """
        case let .afterMessages(count):
            return """
            이번 주기는 다른 사람의 메시지 \(count)개가 쌓이면 끝납니다. \
            방이 조용하면 그만큼 늦어집니다.
            """
        }
    }

    private var activeHours: String {
        let hours = entry.policy.activeHours
        guard hours.isLimited else {
            return "시간대 제한 없이 언제든 답합니다."
        }
        guard hours.startMinute != hours.endMinute else {
            return "시작과 종료가 같습니다. 하루 종일 답합니다."
        }
        return "매일 \(hours.summary) 동안만 답하고, 그 밖의 시간에는 AI를 호출하지 않습니다."
    }

    /// The one switch on this screen that widens what leaves the Mac, so it says
    /// so where the choice is made instead of in a document nobody opens. Read as
    /// "the app looks at photos", it sounds like local work; what it actually does
    /// is upload the pictures from this room.
    private var photos: String {
        guard entry.policy.readsPhotos else {
            return "사진은 보내지 않습니다. 사진 메시지는 \"(사진)\"으로만 전달되어, 무엇이 찍혔는지 모른 채 답합니다."
        }
        return """
        이 방의 최근 사진을 최대 \(MessagePhotoSelection.limit)장까지 답장 요청에 첨부합니다. \
        대화 글에 더해 사진 파일이 AI 제공자로 나갑니다. \
        이 Mac에 이미 받아 둔 사진만 쓰고, 호출이 끝나면 지웁니다.
        """
    }

    /// The second switch that widens what leaves the Mac, said here for the same
    /// reason as 사진: read as "the app can look things up" it sounds free of
    /// consequence, when what it does is turn this room's words into web queries.
    private var webSearch: String {
        guard entry.policy.webSearch else {
            return "웹 검색을 쓰지 않습니다. 대화와 이미 아는 것만으로 답합니다."
        }
        return """
        답에 최신 사실 확인이 필요할 때 AI가 웹을 검색합니다. \
        이 방의 대화에서 뽑은 검색어가 AI 제공자의 웹 검색을 거쳐 나갑니다. \
        이 Mac에서 명령을 돌리지는 않고(read-only 그대로), 검색만 제공자 쪽에서 이뤄집니다.
        """
    }

    /// The third switch that widens what leaves the Mac, said the same way: read
    /// as "the app reads links" it sounds harmless, when it opens the page and
    /// sends a request to that address on the account's behalf.
    private var links: String {
        guard entry.policy.readsLinks else {
            return "링크를 열지 않습니다. 링크는 주소 글자로만 전달되어, 그 안에 무엇이 있는지 모른 채 답합니다."
        }
        return """
        대화에 올라온 최근 링크를 최대 \(MessageLinkSelection.limit)개까지 앱이 열어 페이지 글을 답장 요청에 넣습니다. \
        페이지를 열려고 그 주소로 요청이 나가고, 사설·로컬 주소는 열지 않습니다. \
        모델은 브라우징하지 않고(read-only 그대로), 앱이 뽑은 텍스트만 받습니다.
        """
    }

    /// What the model knows about this room before it reads a single message.
    ///
    /// In this list rather than only in its own section, because the difference is
    /// invisible from outside: two rooms answering with the same style and the
    /// same condition will answer differently, and the reason is a paragraph
    /// stored on disk that this line is the only mention of on the whole form.
    private var memory: String {
        guard entry.policy.remembersConversation else {
            return "이 방의 요약을 만들지 않습니다. 답장은 최근 대화만 보고 만듭니다."
        }
        return """
        이 방이 어떤 방인지 정리해 두고 답장 요청마다 함께 보냅니다. \
        요약은 위 "대화 기억"에서 읽고 고칠 수 있습니다.
        """
    }

    /// Said here as well as in its own section, because this list is what the
    /// user reads to answer "what will this room do". A room that may speak first
    /// and a room that never will are otherwise indistinguishable from a summary
    /// that only talks about answering.
    private var opener: String {
        guard entry.policy.responseMode != .off, entry.policy.responseMode != .detectOnly else {
            return "먼저 말을 걸지 않습니다."
        }
        switch entry.policy.conversationOpener {
        case .off:
            return "먼저 말을 걸지 않습니다. 아무도 부르지 않으면 조용합니다."
        case .draftOnly:
            return """
            조용해지면 \(entry.policy.conversationOpenerInterval.summary) 먼저 걸 말이 있는지 살피고, \
            만들어도 사람이 눌러야 나갑니다.
            """
        case .delivers:
            return entry.policy.openerDeliversAutomatically
                ? """
                조용해지면 \(entry.policy.conversationOpenerInterval.summary) 먼저 말을 걸고, \
                만든 말은 사람 확인 없이 나갑니다.
                """
                : """
                먼저 걸 말을 만들지만 전송 방식이 "\(entry.policy.deliveryMode.title)"이라 \
                사람이 눌러야 나갑니다.
                """
        }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
