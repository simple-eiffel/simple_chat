note
	description: "What a participant is asked: who asked, what, in which room, how long an answer may be, and any `via' choice."
	author: "Larry Rix"

class
	PARTICIPANT_REQUEST

create
	make

feature {NONE} -- Initialization

	make (a_asker_display_name, a_text: READABLE_STRING_GENERAL; a_room_id: INTEGER_64; a_room_name: READABLE_STRING_GENERAL;
			a_max_characters: INTEGER; a_via: detachable READABLE_STRING_GENERAL)
		require
			asker_named: not a_asker_display_name.is_empty
			text_given: not a_text.is_empty
			positive_room: a_room_id > 0
			max_positive: a_max_characters > 0
		do
			asker_display_name := a_asker_display_name.to_string_32
			text := a_text.to_string_32
			room_id := a_room_id
			room_name := a_room_name.to_string_32
			max_characters := a_max_characters
			if attached a_via as v then
				via := v.to_string_32
			end
		ensure
			set: room_id = a_room_id and max_characters = a_max_characters
			text_set: text.same_string_general (a_text)
		end

feature -- Access

	asker_display_name: STRING_32
	text: STRING_32
	room_id: INTEGER_64
	room_name: STRING_32
	max_characters: INTEGER
	via: detachable STRING_32

invariant
	asker_named: not asker_display_name.is_empty
	text_given: not text.is_empty
	positive_room: room_id > 0
	max_positive: max_characters > 0

end
