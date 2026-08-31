note
	description: "[
		A transient notice on the live stream that is never stored:
		"robot thinking...", "queued behind 1", typing later (DR-009).
		`make_from_separate' copies one across processors (D1): the bus
		hands statuses to subscribers on other processors.

		Value semantics (Issue 23 / M-D3): `make' copies its incoming text,
		`is_equal' compares by value, `duplicate' builds an independent copy.
		The attributes stay STRING_32; moving them to READABLE_/IMMUTABLE_
		types is a Phase 4 task.
	]"
	author: "Larry Rix"

class
	CHAT_STATUS

inherit
	ANY
		redefine
			is_equal
		end

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
			create from_display_name.make_from_string_general (a_from_display_name)
			create text.make_from_string_general (a_text)
		ensure
			set: room_id = a_room_id
			from_set: from_display_name.same_string_general (a_from_display_name)
			text_set: text.same_string_general (a_text)
			owns_text: from_display_name /= a_from_display_name and text /= a_text
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

feature -- Comparison

	is_equal (a_other: like Current): BOOLEAN
			-- Do `Current' and `a_other' carry the same values, text compared by content?
		do
			Result := room_id = a_other.room_id
				and from_display_name.same_string (a_other.from_display_name)
				and text.same_string (a_other.text)
		ensure then
			definition: Result = (room_id = a_other.room_id
				and from_display_name.same_string (a_other.from_display_name)
				and text.same_string (a_other.text))
		end

feature -- Duplication

	duplicate: like Current
			-- An independent copy with fresh strings, equal to `Current' by value.
		do
			create Result.make (room_id, from_display_name, text)
		ensure
			equal_value: Result ~ Current
			distinct: Result /= Current
			own_text: Result.from_display_name /= from_display_name and Result.text /= text
		end

feature -- Constants

	Text_maximum: INTEGER = 200

invariant
	positive_room: room_id > 0
	from_given: not from_display_name.is_empty
	text_given: not text.is_empty
	bounded: from_display_name.count <= {CHAT_USER}.Display_name_maximum and text.count <= Text_maximum

end
