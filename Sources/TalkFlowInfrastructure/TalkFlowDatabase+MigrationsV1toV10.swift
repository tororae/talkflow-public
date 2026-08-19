import GRDB
import TalkFlowDomain

/// `TalkFlowDatabase.migrator`에 등록되는 마이그레이션 중 v1부터 v10까지: 정책·설정 테이블의 시작과 방별 첫 열들.
///
/// 등록 순서가 스키마다. GRDB는 등록된 순서대로 적용하므로 이 파일들의 호출
/// 순서와 파일 안의 순서를 바꾸면 업그레이드가 깨진다.
extension TalkFlowDatabase {
    static func registerMigrationsV1toV10(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1-policies-and-settings") { db in
            try db.create(table: "chat_rooms") { table in
                table.column("account_fingerprint", .text).notNull()
                table.column("chat_id", .text).notNull()
                table.column("display_name", .text).notNull()
                table.column("kind", .text).notNull()
                table.primaryKey(["account_fingerprint", "chat_id"])
            }

            try db.create(table: "room_policies") { table in
                table.column("account_fingerprint", .text).notNull()
                table.column("chat_id", .text).notNull()
                table.column("response_mode", .text).notNull()
                table.column("spontaneous_level", .text).notNull()
                table.column("delivery_mode", .text).notNull()
                table.column("minimum_interval", .double).notNull()
                table.column("prefers_recent_human_reply", .boolean).notNull()
                table.primaryKey(["account_fingerprint", "chat_id"])
            }

            // Single-row tables: the CHECK keeps a second row from ever existing,
            // so reads never have to decide which settings are current.
            try db.create(table: "response_style_settings") { table in
                table.column("id", .integer).primaryKey().check { $0 == 1 }
                table.column("tone", .text).notNull()
                table.column("length", .text).notNull()
                table.column("emoji_use", .text).notNull()
                table.column("assertiveness", .text).notNull()
                table.column("mention_tokens", .text).notNull()
            }

            try db.create(table: "app_settings") { table in
                table.column("id", .integer).primaryKey().check { $0 == 1 }
                table.column("responses_enabled", .boolean).notNull()
                table.column("launches_at_login", .boolean).notNull()
                table.column("send_use_policy_accepted", .boolean).notNull().defaults(to: false)
            }

            // Drafts wait here instead of going out as soon as they exist: every
            // condition is re-checked before an action that cannot be undone.
            try db.create(table: "pending_sends") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("account_fingerprint", .text).notNull()
                table.column("chat_id", .text).notNull()
                table.column("trigger_message_id", .text).notNull()
                table.column("text", .text).notNull()
                table.column("eligible_at", .datetime).notNull()
                table.column("state", .text).notNull()
                table.column("detail", .text).notNull()
                table.column("created_at", .datetime).notNull()
            }
            try db.create(
                index: "idx_pending_sends_state",
                on: "pending_sends",
                columns: ["state", "eligible_at"]
            )

            // Holds are recorded alongside replies: the timeline has to answer
            // "why did nothing happen?" as well as "what was sent?".
            try db.create(table: "agent_actions") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("account_fingerprint", .text).notNull()
                table.column("chat_id", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("trigger_message_id", .text)
                table.column("trigger_sender_id", .text)
                table.column("reply_mode", .text)
                table.column("confidence", .text)
                table.column("reply_text", .text)
                table.column("detail", .text).notNull()
                table.column("context_message_count", .integer).notNull().defaults(to: 0)
                table.column("created_at", .datetime).notNull()
            }
            try db.create(
                index: "idx_agent_actions_created_at",
                on: "agent_actions",
                columns: ["created_at"]
            )
            try db.create(
                index: "idx_agent_actions_room",
                on: "agent_actions",
                columns: ["chat_id", "created_at"]
            )
        }

        migrator.registerMigration("v2-wake-display-to-send") { db in
            try db.alter(table: "app_settings") { table in
                table.add(column: "wakes_display_to_send", .boolean).notNull().defaults(to: true)
            }
        }

        // A draft cannot be judged without seeing what it answers. The trigger
        // is copied rather than looked up so the record still reads correctly
        // after the archive is pruned or the account changes.
        migrator.registerMigration("v3-trigger-message-text") { db in
            try db.alter(table: "agent_actions") { table in
                table.add(column: "trigger_text", .text)
                table.add(column: "trigger_sender_name", .text)
            }
        }

        // Tagging and answering hours are the room's business, not the app's.
        // Both arrive with the value that changes nothing for the rooms already
        // configured: no tag, since typing `@이름` never was a real mention, and
        // no window, since those rooms have been answering around the clock.
        migrator.registerMigration("v4-room-tagging-and-active-hours") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "tags_recipient_by_name", .boolean).notNull().defaults(to: false)
                table.add(column: "active_hours_limited", .boolean).notNull().defaults(to: false)
                table.add(column: "active_hours_start_minute", .integer)
                    .notNull()
                    .defaults(to: ReplyActiveHours.always.startMinute)
                table.add(column: "active_hours_end_minute", .integer)
                    .notNull()
                    .defaults(to: ReplyActiveHours.always.endMinute)
            }
        }

        // Reading photos widens what leaves the Mac, so it arrives off for every
        // room that already exists. A user who configured a room before this
        // setting existed agreed to text going to the provider and nothing else,
        // and a default of on would send pictures they never offered.
        migrator.registerMigration("v5-room-photo-context") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "reads_photos", .boolean).notNull().defaults(to: false)
            }
        }

        // A room's own call words. Empty for every room that already exists, and
        // that changes nothing for them: the words they answered to before are
        // the global ones, which still apply, plus the account's own name, which
        // they now get without anybody registering it.
        migrator.registerMigration("v6-room-response-keywords") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "response_keywords", .text).notNull().defaults(to: "[]")
            }
        }

        // Judging in batches arrives off, as zero, for every room that already
        // exists. It changes when a room answers, and a room the user set up to
        // answer each message should not start holding them back because an
        // upgrade decided that for them.
        migrator.registerMigration("v7-room-judgement-interval") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "judgement_interval", .double).notNull().defaults(to: 0)
            }
        }

        // A queued reply now remembers whose message it answers. Only that
        // person saying more can make it stale, and without the sender the gate
        // had to treat anybody speaking as the same thing.
        migrator.registerMigration("v8-pending-send-trigger-sender") { db in
            try db.alter(table: "pending_sends") { table in
                table.add(column: "trigger_sender_id", .text)
            }
        }

        // The interval became a range, so a cycle can wait somewhere between two
        // numbers instead of at exactly the same instant every time. Existing
        // rooms take zero for the new end, which the reader raises to whatever
        // they already had: a fixed interval, unchanged. Nobody's room starts
        // varying because an upgrade decided it should.
        migrator.registerMigration("v9-room-judgement-interval-range") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "judgement_interval_longest", .double).notNull().defaults(to: 0)
            }
        }

        // A reply routinely answers several messages — 뒷말 대기 folds them in,
        // 판단 주기 accumulates them — and the record named only the last one.
        // Nullable with no default because the rows already written have no run
        // to reconstruct: their trigger line is all that was ever kept, and the
        // timeline still reads them that way rather than showing a blank.
        migrator.registerMigration("v10-action-answered-run") { db in
            try db.alter(table: "agent_actions") { table in
                table.add(column: "answered_run", .text)
            }
        }
    }
}
