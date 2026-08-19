import GRDB
import TalkFlowDomain

/// `TalkFlowDatabase.migrator`에 등록되는 마이그레이션 중 v11부터 v17까지: 먼저 말 걸기, 방별 재정의, 요약, 활동 기록.
///
/// 등록 순서가 스키마다. GRDB는 등록된 순서대로 적용하므로 이 파일들의 호출
/// 순서와 파일 안의 순서를 바꾸면 업그레이드가 깨진다.
extension TalkFlowDatabase {
    static func registerMigrationsV11toV17(in migrator: inout DatabaseMigrator) {
        // Starting a conversation is the first thing this app does that nobody
        // asked for, so every room that already exists takes it off — including
        // the rooms whose owner has already agreed to 상시 전송 for replies. That
        // agreement was about answering, and an upgrade may not read it as
        // permission to speak. The interval column carries the suggested range so
        // a room switched on later has a cadence without anyone typing one.
        //
        // The queue column names the message a queued opener was written after,
        // and stays null for every reply: only an opener is cancelled by somebody
        // else in the room merely speaking.
        migrator.registerMigration("v11-room-conversation-opener") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "conversation_opener", .text)
                    .notNull()
                    .defaults(to: ConversationOpener.off.rawValue)
                table.add(column: "conversation_opener_shortest", .double)
                    .notNull()
                    .defaults(to: JudgementIntervalInput.conversationOpener.time.suggested.shortest)
                table.add(column: "conversation_opener_longest", .double)
                    .notNull()
                    .defaults(to: JudgementIntervalInput.conversationOpener.time.suggested.longest)
            }
            try db.alter(table: "pending_sends") { table in
                table.add(column: "opens_conversation_after_message_id", .text)
            }
        }

        // 자발 개입 becomes 끼어들기 확률, and two settings gain a per-room override.
        //
        // The enum went because it never held the gradient its three words
        // promised: 낮음 and 보통 were the same value in code for months, and the
        // local rule that briefly told them apart dropped a plain Korean question
        // because it ended `건가..` with no `?`. A percentage cannot make that
        // promise falsely. `꺼짐` is the one step that meant something the model
        // could not do for itself — never being asked at all — so it maps to 0
        // and the other two, which both asked every time, map to 100.
        //
        // The overrides arrive as "follow 설정" for every room: null for the
        // condition, off for the style. A room the user configured before this
        // existed has been answering in the global style all along, and freezing
        // a copy of today's global into it would turn later edits to 설정 into a
        // setting that stopped working.
        migrator.registerMigration("v12-interjection-chance-and-room-overrides") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "interjection_chance", .integer)
                    .notNull()
                    .defaults(to: InterjectionChance.always.percent)
                table.add(column: "answering_condition", .text)
                table.add(column: "uses_own_style", .boolean).notNull().defaults(to: false)
                table.add(column: "style_tone", .text).notNull().defaults(to: ResponseStyle().tone)
                table.add(column: "style_length", .text)
                    .notNull()
                    .defaults(to: ResponseStyle().length.rawValue)
                table.add(column: "style_emoji_use", .text)
                    .notNull()
                    .defaults(to: ResponseStyle().emojiUse.rawValue)
                table.add(column: "style_assertiveness", .text)
                    .notNull()
                    .defaults(to: ResponseStyle().assertiveness.rawValue)
            }
            try db.execute(
                sql: """
                UPDATE room_policies
                SET interjection_chance = CASE spontaneous_level WHEN 'off' THEN 0 ELSE 100 END
                """
            )
            // Dropped rather than left behind. A column nobody reads is a column
            // the next writer has to keep filling with a value that means
            // nothing, and this table's inserts name every column they write.
            try db.alter(table: "room_policies") { table in
                table.drop(column: "spontaneous_level")
            }

            // The global condition shares the single row the global style
            // already lives in. Empty for everybody: nobody has written one, and
            // a condition the app invented would be the guess this setting exists
            // to replace.
            try db.alter(table: "response_style_settings") { table in
                table.add(column: "answering_condition", .text).notNull().defaults(to: "")
            }
        }

        // 판단 주기 can now be counted in messages instead of on a clock, so the
        // two numbers beside it need a column saying which they are.
        //
        // Every room that already exists takes `seconds`, which is what its
        // numbers have always meant. Nothing else would be honest: a room set to
        // 5분 is not a room somebody asked to answer every five messages, and the
        // rooms on 즉시 keep no numbers at all, so the unit changes nothing for
        // them either way.
        //
        // The opener's cycle gets no such column. It counts a silence, which has
        // no messages in it to count, and a column nobody reads is a column the
        // next writer has to keep filling with a value that means nothing.
        migrator.registerMigration("v13-room-judgement-interval-unit") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "judgement_interval_unit", .text)
                    .notNull()
                    .defaults(to: JudgementInterval.Measure.seconds.rawValue)
            }
        }

        // 채팅방 요약 gets a table of its own rather than columns on the policy.
        //
        // Its lifecycle is not the policy's. A policy row is rewritten by the room
        // screen on every keystroke of 답변 조건, as a full-row upsert naming every
        // column; a summary is rewritten by a background sweep that can be in
        // flight while those keystrokes are landing. In one row the two writers
        // would each read the other's stale copy and put it back. Deleting is also
        // a real operation here — "지우기" has to leave nothing behind, not four
        // columns holding a value every future reader must agree means absence.
        //
        // On for every room that already exists, unlike the migrations for photos
        // and for openers. Those arrived off because one widened what leaves the
        // Mac and the other made the app speak unasked. This one does neither: the
        // conversation it condenses is already going to the provider on every
        // reply in these rooms, and what it adds is a few calls a day against a
        // model that was otherwise answering months of friendship from thirty
        // lines. The switch beside it is for the part that is new — a written
        // description of real people sitting on disk — and it deletes the note
        // when it goes off.
        migrator.registerMigration("v14-room-conversation-summary") { db in
            try db.create(table: "room_summaries") { table in
                table.column("account_fingerprint", .text).notNull()
                table.column("chat_id", .text).notNull()
                table.column("summary_text", .text).notNull()
                table.column("updated_at", .datetime).notNull()
                // Whether a person wrote what this says. The sweep refuses to
                // overwrite a row where this is true.
                table.column("is_user_edited", .boolean).notNull().defaults(to: false)
                // The newest message folded in: where the next refresh starts
                // reading, so the cost of remembering a room does not grow with
                // the room.
                table.column("covered_through_message_id", .text)
                table.column("covered_message_count", .integer).notNull().defaults(to: 0)
                table.primaryKey(["account_fingerprint", "chat_id"])
            }

            try db.alter(table: "room_policies") { table in
                table.add(column: "remembers_conversation", .boolean).notNull().defaults(to: true)
            }
        }

        // Where the time went, per action.
        //
        // The record already said what was decided and when the row was written,
        // which is enough to see that a reply took two minutes and no help at all
        // in seeing which two minutes. Answering that from the outside took a
        // night of sampling stacks and still left three candidates standing,
        // because the durations were never anywhere.
        //
        // Nullable with no default: the rows already written were not timed and
        // must not claim to have been. The screen leaves the section out for them
        // rather than drawing an empty one.
        migrator.registerMigration("v15-action-timeline") { db in
            try db.alter(table: "agent_actions") { table in
                table.add(column: "timeline", .text)
            }
        }

        // A KakaoTalk 답장 aimed at one of this account's messages counts as
        // being called.
        //
        // Defaulted on for every existing room, unlike 먼저 말 걸기 in v11 which
        // every room had to opt into. That one was the app doing something nobody
        // asked for. This one is the app noticing it was addressed — the person
        // who picked a message out and replied to it is waiting for an answer
        // whether or not anybody has registered a keyword.
        migrator.registerMigration("v16-room-answers-replies") { db in
            try db.alter(table: "room_policies") { table in
                table.add(column: "answers_replies", .boolean).notNull().defaults(to: true)
            }
        }

        // A room the user asked to stop seeing.
        //
        // Hidden rather than deleted, because there is nothing to delete: the
        // room list is derived from the archive, and a room is in it because a
        // message once arrived. Removing the row would bring the room back on the
        // next load with its settings gone — a delete that loses the
        // configuration and not the room is the worst of both.
        //
        // The instant is kept rather than a flag, because 「언제부터 안 보이기로
        // 했는지」 is the question somebody asks when a room they expected is
        // missing.
        migrator.registerMigration("v17-hidden-rooms") { db in
            try db.alter(table: "chat_rooms") { table in
                table.add(column: "hidden_at", .datetime)
            }
        }
    }
}
