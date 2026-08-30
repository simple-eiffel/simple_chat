note
	description: "[
		A transient notice on the live stream that is never stored:
		"robot thinking...", "queued behind 1", typing later (DR-009).
		`make_from_separate' copies one across processors (D1): the bus
		hands statuses to subscribers on other processors.
	]"
	author: "Larry Rix"

class
	CHAT_STATUS

create
	make,
	make_from_separate

feature {NONE} -- Initialization

	make (a_room_id: INTEGER_64; a_from_display_name, a_text: READABLE_STRING_GENERAL)
		require
			positive_room: a_room_id > 0
			from_given: not a_from_display_name.is_empty
			text_given: not a_text.is_empty
			from_bounded: a_from_display_name.count <= {CHAT_USER}.Display_name_maximum
			text_bounded: a_text.count <= Text_maximum
		do
			room_id := a_room_id
			from_display_name := a_from_display_name.to_string_32
			text := a_text.to_string_32
		ensure
			set: room_id = a_room_id
			from_set: from_display_name.same_string_general (a_from_display_name)
			text_set: text.same_string_general (a_text)
		end

	make_from_separate (a_other: separate CHAT_STATUS)
			-- A copy on this processor.
		do
			room_id := a_other.room_id
			create from_display_name.make_from_separate (a_other.from_display_name)
			create text.make_from_separate (a_other.text)
		ensure
			same_room: room_id = a_other.room_id
			same_lengths: from_display_name.count = a_other.from_display_name.count and text.count = a_other.text.count
		end

feature -- Access

	room_id: INTEGER_64
	from_display_name: STRING_32
	text: STRING_32

feature -- Constants

	Text_maximum: INTEGER = 200

invariant
	positive_room: room_id > 0
	from_given: not from_display_name.is_empty
	text_given: not text.is_empty
	bounded: from_display_name.count <= {CHAT_USER}.Display_name_maximum and text.count <= Text_maximum

end
