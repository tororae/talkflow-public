import GRDB
import TalkFlowDomain

/// `TalkFlowDatabase.migrator`에 등록되는 마이그레이션 중 v23부터 v31까지: 사람 링크와 방별 메모, 모델·검색·링크 읽기, 관리자 방.
///
/// 등록 순서가 스키마다. GRDB는 등록된 순서대로 적용하므로 이 파일들의 호출
/// 순서와 파일 안의 순서를 바꾸면 업그레이드가 깨진다.
extension TalkFlowDatabase {
    static func registerMigrationsV23toV31(in migrator: inout DatabaseMigrator) {
        // Whether a link is this person's own work or something they passed on,
        // and when it last came up.
        //
        // The distinction a reply gets wrong in the most embarrassing direction:
        // 「형이 만든 그 앱」 about a forwarded link credits somebody with a
        // stranger's work, and the reverse dismisses their own. `unknown` is the
        // default and the honest answer for most links — a model asked to choose
        // between made and shared will choose, and a guess recorded as a fact is
        // what this column exists to prevent.
        //
        // `last_mentioned_at` is how the list orders itself, so nobody has to
        // rank links by hand. A link nobody has brought up in months falls off
        // the end of a prompt on its own.
        migrator.registerMigration("v23-person-link-relation") { db in
            try db.alter(table: "person_links") { table in
                table.add(column: "relation", .text).notNull().defaults(to: "unknown")
                table.add(column: "last_mentioned_at", .datetime)
            }
        }

        // A person in one room is not the same file as the same person in
        // another. The key is the room and the sender together.
        //
        // v22 keyed on `sender_id` alone, and justified it with two readings that
        // were both taken off the wrong account (1.4). 「a correspondent in
        // several of this account's rooms」 — one room, on the account TalkFlow
        // actually reads; the several were the logged-out one. 「Two
        // correspondents sharing one display name」 — one person, in two rooms.
        // KakaoTalk stamps a *different* sender id on the same human in every
        // group room, so that pair was never a name collision, and the cross-room
        // knowledge the single key existed to preserve was never being preserved:
        // only two ids in this account span rooms at all, and they are this
        // account itself and the user's own.
        //
        // What the single key did do is make removal unsafe, because a note might
        // have been earned somewhere the current room cannot see. Nothing was.
        // Room-scoped, a note can finally drop what has finished.
        //
        // The room comes from the action log rather than from a guess: a note only
        // exists because this account replied to somebody, and every one of the
        // notes on this machine resolves to exactly one `chat_id` there. Anything
        // that does not resolve is a note for a reply that no longer exists, and
        // goes.
        migrator.registerMigration("v24-person-notes-per-room") { db in
            try db.create(table: "person_notes_new") { table in
                table.column("chat_id", .text).notNull()
                table.column("sender_id", .text).notNull()
                table.column("display_name", .text).notNull()
                table.column("note", .text).notNull()
                table.column("is_user_edited", .boolean).notNull().defaults(to: false)
                table.column("covered_through_message_id", .text)
                table.column("updated_at", .datetime).notNull()
                table.primaryKey(["chat_id", "sender_id"])
            }
            try db.execute(sql: """
                INSERT INTO person_notes_new
                    (chat_id, sender_id, display_name, note, is_user_edited,
                     covered_through_message_id, updated_at)
                SELECT a.chat_id, n.sender_id, n.display_name, n.note,
                       n.is_user_edited, n.covered_through_message_id, n.updated_at
                FROM person_notes n
                JOIN (
                    SELECT trigger_sender_id, MIN(chat_id) AS chat_id
                    FROM agent_actions
                    WHERE trigger_sender_id IS NOT NULL
                    GROUP BY trigger_sender_id
                ) a ON a.trigger_sender_id = n.sender_id
                """)
            try db.drop(table: "person_notes")
            try db.rename(table: "person_notes_new", to: "person_notes")

            try db.create(table: "person_links_new") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("chat_id", .text).notNull()
                table.column("sender_id", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("label", .text).notNull()
                table.column("url", .text).notNull()
                table.column("relation", .text).notNull().defaults(to: "unknown")
                table.column("last_mentioned_at", .datetime)
            }
            try db.execute(sql: """
                INSERT INTO person_links_new
                    (chat_id, sender_id, position, label, url, relation, last_mentioned_at)
                SELECT a.chat_id, l.sender_id, l.position, l.label, l.url,
                       l.relation, l.last_mentioned_at
                FROM person_links l
                JOIN (
                    SELECT trigger_sender_id, MIN(chat_id) AS chat_id
                    FROM agent_actions
                    WHERE trigger_sender_id IS NOT NULL
                    GROUP BY trigger_sender_id
                ) a ON a.trigger_sender_id = l.sender_id
                """)
            try db.drop(table: "person_links")
            try db.rename(table: "person_links_new", to: "person_links")
            try db.create(
                index: "idx_person_links_person",
                on: "person_links",
                columns: ["chat_id", "sender_id"]
            )
        }

        // Which model answers, which until now nothing in TalkFlow said.
        //
        // Nullable and null by default, because null is a decision and not a
        // missing value: it means pass no `-m` and let `~/.codex/config.toml`
        // decide, which is exactly what every install has been doing. An upgrade
        // changes nobody's replies.
        migrator.registerMigration("v25-ai-model") { db in
            try db.alter(table: "app_settings") { table in
                table.add(column: "ai_model", .text)
            }
        }

        // 고정. What used to be `is_user_edited` and used to mean two things at
        // once: a person typed this, and therefore the refresh may never touch it
        // again. The second half was never asked for and there was no way to take
        // it back — for a person note nothing cleared the flag, so correcting a
        // name froze that person's note permanently.
        //
        // Renamed rather than added beside, because keeping both would leave two
        // columns that disagree about whether a note may change and no rule for
        // which wins. Existing values carry straight over: a note frozen under the
        // old rule stays frozen, now visibly and with a way out.
        migrator.registerMigration("v26-pin-instead-of-hand-edited") { db in
            for table in ["room_summaries", "person_notes"] {
                try db.alter(table: table) { alteration in
                    alteration.rename(column: "is_user_edited", to: "is_pinned")
                }
            }
        }

        // Web search widens what leaves the Mac again, a step past 사진 함께 읽기:
        // with it on, the model turns this room's words into search queries that
        // reach the open web, not only the provider. So it arrives off for every
        // room that already exists — a room configured before this agreed to its
        // text going to the model, not to that text becoming searches.
        migrator.registerMigration("v27-room-web-search") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "web_search", .boolean).notNull().defaults(to: false)
            }
        }

        // Reading a link widens what leaves the Mac the same way 사진 함께 읽기 and
        // 웹 검색 do: the app opens a URL a message carried and puts the page's text
        // in the prompt. Off for every room that already exists — a page someone
        // pasted is not something the account agreed to fetch until it says so.
        migrator.registerMigration("v28-room-link-reading") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "reads_links", .boolean).notNull().defaults(to: false)
            }
        }

        // 먼저 말 걸기의 새 손잡이들 — 전용 시간, 연속 횟수, 재시도 주제, 비활성 시간
        // 주기 처리, 참고 지시. 모두 기존 방이 지금 하는 대로의 값으로 도착한다:
        // 전용 시간은 제한 없음(.always), 연속 횟수 0(내가 마지막이면 먼저 말 안 검),
        // 이어가기, 주기는 밤에도 계속 돌림, 참고 지시 없음. 어느 것도 업그레이드로
        // 방 동작을 바꾸지 않는다.
        migrator.registerMigration("v29-opener-hours-and-repeat") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "opener_hours_limited", .boolean).notNull().defaults(to: false)
                table.add(column: "opener_hours_start_minute", .integer)
                    .notNull().defaults(to: ReplyActiveHours.always.startMinute)
                table.add(column: "opener_hours_end_minute", .integer)
                    .notNull().defaults(to: ReplyActiveHours.always.endMinute)
                table.add(column: "opener_repeat_limit", .integer).notNull().defaults(to: 0)
                table.add(column: "opener_repeat_topic", .text)
                    .notNull().defaults(to: OpenerRepeatTopic.carryOn.rawValue)
                table.add(column: "opener_cadence_pauses_outside_hours", .boolean)
                    .notNull().defaults(to: false)
                table.add(column: "opener_prompt_hint", .text)
            }
        }

        // 「다른 사람이 먼저 답하면 보류」가 사라졌다. 이 값을 읽던 판단은 없어졌고,
        // room_policies의 INSERT는 모든 컬럼을 이름으로 적으므로, 남은 컬럼은 다음
        // 저장마다 뜻 없는 값을 채워 넣어야 하는 짐이 된다. v12에서 spontaneous_level을
        // 그랬듯 남기지 않고 지운다.
        migrator.registerMigration("v30-drop-prefers-recent-human-reply") { db in
            try db.alter(table: "room_policies") { table in
                table.drop(column: "prefers_recent_human_reply")
            }
        }

        // 관리자 모드 방 — 설정에서 지정한, 조작 명령을 받는 방.
        //
        // 방이 어떻게 답하는지가 아니라 앱을 조종하는 메타 설정이라 room_policies가
        // 아니라 자기 테이블에 둔다. 비어서 도착한다: 아무 방도 명령을 받지 않는 것이
        // 기본이고, 업그레이드가 어떤 방을 콘솔로 만들지 않는다.
        migrator.registerMigration("v31-admin-rooms") { db in
            try db.create(table: "admin_rooms") { table in
                table.column("account_fingerprint", .text).notNull()
                table.column("chat_id", .text).notNull()
                table.primaryKey(["account_fingerprint", "chat_id"])
            }
        }
    }
}
