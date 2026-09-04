note
	description: "[
		What a participant is asked: who asked (the stored member's id and
		display name), what, in which room, how long an answer may be, and
		any `via' choice - shaped exactly like ADDRESSED_REQUEST's `via'
		(M2), so a request can never carry a choice the parser would not
		have produced.

		`context_lines' is the room's recent conversation, oldest first, one
		line per message and each already prefixed by its sender's display
		name - what lets a participant answer "and its cube root?". It is
		empty unless the dispatcher fills it (`set_context'), and it is
		never part of `text': the question stays exactly what was asked.

		`is_private' marks an ask that is ONE MEMBER'S OWN and never the
		room's - a summary, drawn in the asker's window and posted nowhere.
		It is False for every request the room can see. A participant that
		keeps an engine conversation per room reads it and keeps none: a
		private ask must neither continue the room's session nor become it,
		or the engine answers out of a transcript nobody asked it to
		summarise. That is what Larry saw - "@claude sum" came back with a
		summary of the CLI's own session rather than the room's.

		`make' builds a request from someone the store does not know
		(`asker_id' = 0: previews and tests); the dispatcher always uses
		`make_addressed', whose asker is a stored member and therefore has a
		rate-limit key.
	]"
	author: "Larry Rix"

class
	PARTICIPANT_REQUEST

create
	make,
	make_addressed

feature {NONE} -- Initialization

	make (a_asker_display_name, a_text: READABLE_STRING_GENERAL; a_room_id: INTEGER_64; a_room_name: READABLE_STRING_GENERAL;
			a_max_characters: INTEGER; a_via: detachable READABLE_STRING_GENERAL)
			-- A request from an asker the store does not know.
		require
			asker_named: not a_asker_display_name.is_empty
			text_given: not a_text.is_empty
			positive_room: a_room_id > 0
			room_named: not a_room_name.is_empty
			max_positive: a_max_characters > 0
			via_given_if_attached: attached a_via as v implies not v.is_empty
			via_shape: attached a_via as v implies (create {PARTICIPANT_RULES}).is_via_choice (v)
		do
			set_fields (0, a_asker_display_name, a_text, a_room_id, a_room_name, a_max_characters, a_via)
		ensure
			set: room_id = a_room_id and max_characters = a_max_characters
			text_set: text.same_string_general (a_text)
			asker_unknown: asker_id = 0
			via_set: (via = Void) = (a_via = Void)
		end

	make_addressed (a_asker_id: INTEGER_64; a_asker_display_name, a_text: READABLE_STRING_GENERAL; a_room_id: INTEGER_64;
			a_room_name: READABLE_STRING_GENERAL; a_max_characters: INTEGER; a_via: detachable READABLE_STRING_GENERAL)
			-- A request from stored member `a_asker_id'.
		require
			asker_positive: a_asker_id > 0
			asker_named: not a_asker_display_name.is_empty
			text_given: not a_text.is_empty
			positive_room: a_room_id > 0
			room_named: not a_room_name.is_empty
			max_positive: a_max_characters > 0
			via_given_if_attached: attached a_via as v implies not v.is_empty
			via_shape: attached a_via as v implies (create {PARTICIPANT_RULES}).is_via_choice (v)
		do
			set_fields (a_asker_id, a_asker_display_name, a_text, a_room_id, a_room_name, a_max_characters, a_via)
		ensure
			set: room_id = a_room_id and max_characters = a_max_characters
			text_set: text.same_string_general (a_text)
			asker_set: asker_id = a_asker_id
			via_set: (via = Void) = (a_via = Void)
		end

	set_fields (a_asker_id: INTEGER_64; a_asker_display_name, a_text: READABLE_STRING_GENERAL; a_room_id: INTEGER_64;
			a_room_name: READABLE_STRING_GENERAL; a_max_characters: INTEGER; a_via: detachable READABLE_STRING_GENERAL)
		do
			asker_id := a_asker_id
			create asker_display_name.make_from_string_general (a_asker_display_name)
			create text.make_from_string_general (a_text)
			room_id := a_room_id
			create room_name.make_from_string_general (a_room_name)
			max_characters := a_max_characters
			if attached a_via as v then
				via := v.to_string_32
			end
			create context_lines.make (0)
			is_private := False
		end

feature -- Access

	asker_id: INTEGER_64
			-- The asker's stored id; 0 when the asker is not a stored member.

	asker_display_name: STRING_32
	text: STRING_32
	room_id: INTEGER_64
	room_name: STRING_32
	max_characters: INTEGER
	via: detachable STRING_32
			-- "plain", "@qwen", "@claude" when the member chose a shaper.

	context_lines: ARRAYED_LIST [STRING_32]
			-- The room's recent messages, oldest first, each "<sender>: <text>";
			-- empty when the participant carries no context window.

feature -- Element change

	set_private
			-- Mark this ask one member's own: answered to the asker alone,
			-- so no engine session may be continued into it and none kept
			-- from it.
		do
			is_private := True
		ensure
			private: is_private
			text_untouched: text.same_string (old text)
			context_kept: context_lines.count = old context_lines.count
		end

	set_context (a_lines: ARRAYED_LIST [STRING_32])
			-- Give this request `a_lines' as the room's recent conversation.
		require
			none_empty: across a_lines as l all not l.is_empty end
		do
			create context_lines.make (a_lines.count)
			across a_lines as l loop
				context_lines.extend (l.twin)
			end
		ensure
			same_count: context_lines.count = a_lines.count
			a_copy: context_lines /= a_lines
			same_lines: across 1 |..| a_lines.count as i all context_lines [i].same_string (a_lines [i]) end
			text_untouched: text.same_string (old text)
		end

feature -- Status report

	is_private: BOOLEAN
			-- Is this ask one member's own - a summary, answered into the
			-- asker's window and never posted to the room? A participant
			-- that remembers a conversation per room must neither resume
			-- one into a private ask nor keep one from it: what it is to
			-- work from is `context_lines' and nothing else. False for
			-- every ordinary request.

	is_asker_known: BOOLEAN
			-- Is the asker a stored member (one with a rate-limit key)?
		do
			Result := asker_id > 0
		ensure
			definition: Result = (asker_id > 0)
		end

invariant
	asker_non_negative: asker_id >= 0
	asker_named: not asker_display_name.is_empty
	text_given: not text.is_empty
	positive_room: room_id > 0
	room_named: not room_name.is_empty
	max_positive: max_characters > 0
	via_given_if_attached: attached via as v implies not v.is_empty
	via_shape: attached via as v implies (create {PARTICIPANT_RULES}).is_via_choice (v)
	context_lines_given: across context_lines as l all not l.is_empty end

end
