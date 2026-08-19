import GRDB
import TalkFlowDomain

/// `TalkFlowDatabase.migrator`에 등록되는 마이그레이션 중 v18부터 v22까지: 불태우기 모드와 그 상태, 시간대 국면, 사람 메모.
///
/// 등록 순서가 스키마다. GRDB는 등록된 순서대로 적용하므로 이 파일들의 호출
/// 순서와 파일 안의 순서를 바꾸면 업그레이드가 깨진다.
extension TalkFlowDatabase {
    static func registerMigrationsV18toV22(in migrator: inout DatabaseMigrator) {
        // 집중 시간 — see `BurningMode`.
        //
        // The three `burning_*` values that shadow a room's own pace are stored
        // beside the ones they shadow rather than in a table of their own. They
        // are settings, they belong to exactly one room, and a user who edits a
        // room edits both at once; splitting them would buy a join and a way for
        // the two halves to disagree.
        //
        // Every default here is the room behaving as it does today. `enabled` is
        // false, so the columns are inert until somebody switches a room on, and
        // an upgrade cannot change what any existing room does.
        migrator.registerMigration("v18-room-burning-mode") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "burning_enabled", .boolean).notNull().defaults(to: false)
                table.add(column: "burning_chance", .integer).notNull().defaults(to: 10)
                table.add(column: "burning_duration_shortest", .double).notNull().defaults(to: 600)
                table.add(column: "burning_duration_longest", .double).notNull().defaults(to: 1_500)
                table.add(column: "burning_cooldown_shortest", .double).notNull().defaults(to: 7_200)
                table.add(column: "burning_cooldown_longest", .double).notNull().defaults(to: 21_600)
                table.add(column: "burning_interjection_chance", .integer).notNull().defaults(to: 90)
                table.add(column: "burning_minimum_interval", .double).notNull().defaults(to: 0)
                table.add(column: "burning_judgement_interval", .double).notNull().defaults(to: 0)
                table.add(column: "burning_judgement_interval_longest", .double).notNull().defaults(to: 0)
            }
        }

        // Where a room is in the cycle right now, which is not a setting.
        //
        // Its own table for the reason the columns above are not: this is drawn,
        // it expires by itself, and it is meaningless the moment the user edits
        // the room. Keeping it beside the settings would mean a 저장 either wiping
        // a live burn or carefully copying it across, and both are worse than a
        // row somewhere else.
        //
        // On disk rather than in memory because a burn outlives the app. A Mac
        // that restarts mid-burn should come back still burning — and, more
        // importantly, a cooldown must survive a restart or relaunching the app
        // would be how a room burns twice in a row.
        //
        // `announced_at` is the instant the end of the burn was last spoken about
        // in this room. Nothing here runs on a timer, so a burn that expired while
        // the Mac was asleep is announced when the room is next examined; without
        // this column it would be announced on every examination after that.
        migrator.registerMigration("v19-room-burning-state") { db in
            try db.create(table: "room_burning_state") { table in
                table.column("account_fingerprint", .text).notNull()
                table.column("chat_id", .text).notNull()
                table.column("started_at", .datetime).notNull()
                table.column("ends_at", .datetime).notNull()
                table.column("cooldown_until", .datetime).notNull()
                table.column("announced_at", .datetime)
                table.primaryKey(["account_fingerprint", "chat_id"])
            }
        }

        // 상태 알림 — see `StateAnnouncements`.
        //
        // The transitions are one text column rather than four booleans, and the
        // column holds raw values joined the way `response_keywords` already
        // joins its list. Four columns would have been four migrations the next
        // time a transition was added, and a set is what the domain holds.
        //
        // Empty is off, which is what every room gets. Nothing here can start
        // speaking because of an upgrade.
        migrator.registerMigration("v20-room-state-announcements") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "announcement_transitions", .text).notNull().defaults(to: "")
                table.add(column: "announcement_recent_window", .double).notNull().defaults(to: 600)
                table.add(column: "announcement_delivery", .text).notNull().defaults(to: "draftOnly")
            }
        }

        // Whether this room's 답변 활성화 시간 was open the last time the room was
        // looked at.
        //
        // One boolean, and it is the whole of what an hours announcement needs.
        // The schedule is not guessed at — the user typed it — so nothing has to
        // anticipate a closing; the app compares the phase now against the phase
        // then and knows a boundary was crossed. An earlier design had a notice
        // window to get the goodbye out before the hours shut, which was solving
        // a problem that does not exist: the goodbye is the one message allowed
        // out after they shut, because it is the message about them shutting.
        //
        // Its own table rather than a column on `room_burning_state`, which only
        // has a row for rooms that have burned. A room with 집중 시간 off still
        // has hours, and hanging this off a burn would mean inventing one.
        migrator.registerMigration("v21-room-hours-phase") { db in
            try db.create(table: "room_hours_phase") { table in
                table.column("account_fingerprint", .text).notNull()
                table.column("chat_id", .text).notNull()
                table.column("was_open", .boolean).notNull()
                table.primaryKey(["account_fingerprint", "chat_id"])
            }
        }

        // 사람 기억 — see `PersonNote`.
        //
        // Keyed on the sender id alone, with no account column and no room
        // column. One person is one note: a frequent correspondent appeared in
        // several of this account's rooms, and a note that reset at the room
        // boundary would learn them once per room, which is the opposite of the
        // point.
        //
        // The name is stored to draw a list and for nothing else. It is not the
        // key and cannot be: two of this account's most frequent correspondents
        // were found sharing one display name, told apart only by their sender
        // ids.
        //
        // Both readings above are wrong. v24 says why, and they are left as they
        // were argued so that the correction has something to correct.
        //
        // Links live in their own table rather than inside the prose. A URL is
        // the one thing in a note a model will confidently rewrite, and a note
        // that quietly corrupts somebody's link is worse than one that never
        // carried it.
        migrator.registerMigration("v22-person-notes") { db in
            try db.create(table: "person_notes") { table in
                table.column("sender_id", .text).primaryKey()
                table.column("display_name", .text).notNull()
                table.column("note", .text).notNull()
                table.column("is_user_edited", .boolean).notNull().defaults(to: false)
                table.column("covered_through_message_id", .text)
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "person_links") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("sender_id", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("label", .text).notNull()
                table.column("url", .text).notNull()
            }
            try db.create(index: "idx_person_links_sender", on: "person_links", columns: ["sender_id"])

            // Off in every room. This widens what leaves the Mac, and in this app
            // that means nobody gets it by upgrading.
            try db.alter(table: "room_policies") { table in
                table.add(column: "remembers_people", .boolean).notNull().defaults(to: false)
            }
        }
    }
}
