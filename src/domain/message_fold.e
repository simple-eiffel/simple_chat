note
	description: "[
		WHAT A MESSAGE LOOKS LIKE NOW, given the log.

		The room is append-only: nothing is ever rewritten, and an edit, a
		delete or a reaction is a NEW event naming the message it acts on.
		This is the one pass that folds them, in log order, into the state
		a reader should see - the same shape the poll and the roster
		already use, and never a per-feature table.

		THE RULES, in one place because they are easy to get subtly wrong:

		  * ORDER IS THE ARBITER. Events fold oldest first, so the LAST
		    edit wins, and a delete that follows an edit still buries it.
		  * A DELETE IS FINAL. Once a message is tombstoned nothing brings
		    it back - a later edit of a deleted message changes nothing a
		    reader sees. That is deliberate: an author who deletes has
		    withdrawn the words, and an edit must not resurrect them.
		  * REACTIONS ARE PER PERSON PER EMOJI, last word wins. The same
		    person clicking the same emoji twice ends with it off; two
		    people are two reactions. Deduping is by (sender, emoji), so
		    nothing double-counts however the events arrive.
		  * A FOLD EVENT NEVER DRAWS. `is_fold_kind' says so, and
		    `standalone' is what a client turns into bubbles.
		  * AN EVENT THAT NAMES NOTHING IS IGNORED. A malformed payload, a
		    target outside this page, a target that is not a message: all
		    are dropped in silence rather than raised. A room must render
		    whatever the log holds.
	]"
	author: "Larry Rix"

class
	MESSAGE_FOLD

create
	make

feature {NONE} -- Initialization

	make (a_events: LIST [CHAT_EVENT])
			-- Fold `a_events' - oldest first - into the current view.
		do
			create texts.make (a_events.count)
			create deleted.make (a_events.count)
			create edited.make (a_events.count)
			create reactions.make (a_events.count)
			create standalone.make (a_events.count)
			create replies.make (a_events.count)
			across a_events as e loop
				absorb (e)
			end
		ensure
			only_real_messages_draw: across standalone as e all not kinds.is_fold_kind (e.kind) end
		end

feature -- Access

	standalone: ARRAYED_LIST [CHAT_EVENT]
			-- The events that draw a bubble of their own, in log order.

	current_text (a_id: INTEGER_64): detachable STRING_32
			-- The text `a_id' should show now: its latest edit, or Void
			-- when it was never edited (the original body stands).
		do
			Result := texts.item (a_id)
		end

	is_deleted (a_id: INTEGER_64): BOOLEAN
			-- Was `a_id' tombstoned?
		do
			Result := deleted.has (a_id)
		end

	is_edited (a_id: INTEGER_64): BOOLEAN
			-- Does the room know `a_id' was changed after it was said?
		do
			Result := edited.has (a_id)
		ensure
			text_when_edited: Result implies current_text (a_id) /= Void
		end

	reply_parent (a_id: INTEGER_64): INTEGER_64
			-- The message `a_id' answers; 0 when it answers none.
		do
			if attached replies.item (a_id) as p then
				Result := p
			end
		ensure
			non_negative: Result >= 0
		end

	reactions_on (a_id: INTEGER_64): HASH_TABLE [INTEGER, STRING_32]
			-- Emoji -> how many people have it on `a_id'; empty when none.
		do
			create Result.make (4)
			across live_reactions (a_id) as on loop
				if on then
					count_one (Result, emoji_of_key (@on.key))
				end
			end
		ensure
			all_positive: across Result as c all c > 0 end
		end

	reacted (a_id, a_sender_id: INTEGER_64; a_emoji: READABLE_STRING_32): BOOLEAN
			-- Has `a_sender_id' got `a_emoji' on `a_id' right now?
		do
			Result := attached live_reactions (a_id).item (reaction_key (a_sender_id, a_emoji)) as v and then v
		end

feature {NONE} -- The fold

	absorb (a_event: CHAT_EVENT)
			-- Fold one event. Anything malformed is dropped in silence: a
			-- room renders whatever the log holds.
		local
			l_target: INTEGER_64
		do
			if kinds.is_fold_kind (a_event.kind) then
				l_target := target_of (a_event)
				if l_target > 0 then
					if a_event.kind.same_string ({CHAT_EVENT_KINDS}.Kind_delete) then
						deleted.force (True, l_target)
					elseif a_event.kind.same_string ({CHAT_EVENT_KINDS}.Kind_edit) then
							-- A delete is final: an edit after it changes nothing.
						if not deleted.has (l_target) and then not a_event.body.is_empty then
							texts.force (a_event.body.twin, l_target)
							edited.force (True, l_target)
						end
					else
						absorb_reaction (a_event, l_target)
					end
				end
			else
				standalone.extend (a_event)
				l_target := payload_id (a_event, {CHAT_EVENT_KINDS}.Key_reply_to)
				if l_target > 0 then
					replies.force (l_target, a_event.id)
				end
			end
		end

	absorb_reaction (a_event: CHAT_EVENT; a_target: INTEGER_64)
			-- One person's emoji, on or off. Last word per (person, emoji) wins.
		require
			positive_target: a_target > 0
		local
			l_emoji: STRING_32
			l_map: HASH_TABLE [BOOLEAN, STRING_32]
		do
			if attached a_event.payload.string_item ({CHAT_EVENT_KINDS}.Key_emoji) as em and then not em.is_empty then
				create l_emoji.make_from_string_general (em)
				l_map := live_reactions (a_target)
				l_map.force (payload_flag (a_event, {CHAT_EVENT_KINDS}.Key_on), reaction_key (a_event.sender_id, l_emoji))
				reactions.force (l_map, a_target)
			end
		end

	target_of (a_event: CHAT_EVENT): INTEGER_64
			-- The message a fold event names; 0 when it names none.
		do
			Result := payload_id (a_event, {CHAT_EVENT_KINDS}.Key_target)
		ensure
			non_negative: Result >= 0
		end

	payload_id (a_event: CHAT_EVENT; a_key: STRING_32): INTEGER_64
			-- A positive id under `a_key', or 0 for anything missing,
			-- mistyped or not positive.
		do
			if attached a_event.payload.integer_item (a_key) as n and then n.item > 0 then
				Result := n.item
			end
		ensure
			non_negative: Result >= 0
		end

	payload_flag (a_event: CHAT_EVENT; a_key: STRING_32): BOOLEAN
			-- The boolean under `a_key'; True when it is missing, because a
			-- reaction event that does not say otherwise is an ADD.
		do
			if attached a_event.payload.boolean_item (a_key) as b then
				Result := b.item
			else
				Result := True
			end
		end

	live_reactions (a_id: INTEGER_64): HASH_TABLE [BOOLEAN, STRING_32]
		do
			if attached reactions.item (a_id) as m then
				Result := m
			else
				create Result.make (4)
			end
		end

	count_one (a_counts: HASH_TABLE [INTEGER, STRING_32]; a_emoji: STRING_32)
		do
			if attached a_counts.item (a_emoji) as n then
				a_counts.force (n + 1, a_emoji)
			else
				a_counts.force (1, a_emoji)
			end
		end

	reaction_key (a_sender_id: INTEGER_64; a_emoji: READABLE_STRING_32): STRING_32
			-- One person, one emoji. The separator is a unit separator, a
			-- character no emoji carries, so the halves always part again.
		do
			create Result.make_from_string_general (a_sender_id.out)
			Result.append_character (Separator)
			Result.append_string_general (a_emoji)
		end

	emoji_of_key (a_key: STRING_32): STRING_32
		local
			i: INTEGER
		do
			i := a_key.index_of (Separator, 1)
			if i > 0 and i < a_key.count then
				Result := a_key.substring (i + 1, a_key.count)
			else
				create Result.make_empty
			end
		end

	Separator: CHARACTER_32 = '%/31/'

	kinds: CHAT_EVENT_KINDS
		once
			create Result
		end

	texts: HASH_TABLE [STRING_32, INTEGER_64]
	deleted: HASH_TABLE [BOOLEAN, INTEGER_64]
	edited: HASH_TABLE [BOOLEAN, INTEGER_64]
	replies: HASH_TABLE [INTEGER_64, INTEGER_64]
	reactions: HASH_TABLE [HASH_TABLE [BOOLEAN, STRING_32], INTEGER_64]

invariant
	standalone_attached: standalone /= Void
	edited_implies_text: across edited as e all texts.has (@e.key) end

end
