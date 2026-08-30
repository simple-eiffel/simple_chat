note
	description: "[
		A transient notice on the live stream that is never stored:
		"robot thinking...", "queued behind 1", typing later (DR-009).
	]"
	author: "Larry Rix"

class
	CHAT_STATUS

create
	make

feature {NONE} -- Initialization

	make (a_room_id: INTEGER_64; a_from_display_name, a_text: READABLE_STRING_GENERAL)
		require
			positive_room: a_room_id > 0
			from_given: not a_from_display_name.is_empty
			text_given: not a_text.is_empty
		do
			room_id := a_room_id
			from_display_name := a_from_display_name.to_string_32
			text := a_text.to_string_32
		ensure
			set: room_id = a_room_id
			from_set: from_display_name.same_string_general (a_from_display_name)
			text_set: text.same_string_general (a_text)
		end

feature -- Access

	room_id: INTEGER_64
	from_display_name: STRING_32
	text: STRING_32

invariant
	positive_room: room_id > 0
	from_given: not from_display_name.is_empty
	text_given: not text.is_empty

end
