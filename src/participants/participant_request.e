note
	description: "[
		What a participant is asked: who asked (the stored member's id and
		display name), what, in which room, how long an answer may be, and
		any `via' choice - shaped exactly like ADDRESSED_REQUEST's `via'
		(M2), so a request can never carry a choice the parser would not
		have produced.

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

feature -- Status report

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

end
