note
	description: "[
		What the service hands the store to append: an event without an id
		or timestamp - the store assigns both, atomically, in order.
	]"
	author: "Larry Rix"

class
	CHAT_EVENT_DRAFT

create
	make

feature {NONE} -- Initialization

	make (a_room_id, a_sender_id: INTEGER_64; a_kind: READABLE_STRING_8; a_body: READABLE_STRING_GENERAL;
			a_attachment: detachable CHAT_ATTACHMENT; a_payload: SIMPLE_JSON_OBJECT; a_bot: BOOLEAN)
		require
			positive_room: a_room_id > 0
			known_kind: (create {CHAT_EVENT_KINDS}).is_known_kind (a_kind)
			sender_or_system: a_sender_id > 0 or a_kind.same_string ({CHAT_EVENT_KINDS}.Kind_system)
			message_has_body: a_kind.same_string ({CHAT_EVENT_KINDS}.Kind_message) implies not a_body.is_empty
			image_has_attachment: a_kind.same_string ({CHAT_EVENT_KINDS}.Kind_image) implies a_attachment /= Void
			bot_marked: (a_bot and a_kind.same_string ({CHAT_EVENT_KINDS}.Kind_message)) implies a_body.to_string_32.starts_with ({CHAT_EVENT_KINDS}.Bot_marker)
		do
			room_id := a_room_id
			sender_id := a_sender_id
			kind := a_kind.to_string_8
			body := a_body.to_string_32
			attachment := a_attachment
			payload := a_payload
			is_bot_authored := a_bot
		ensure
			set: room_id = a_room_id and sender_id = a_sender_id and is_bot_authored = a_bot
			kind_set: kind.same_string (a_kind)
			body_set: body.same_string_general (a_body)
		end

feature -- Access

	room_id, sender_id: INTEGER_64
	kind: STRING_8
	body: STRING_32
	attachment: detachable CHAT_ATTACHMENT
	payload: SIMPLE_JSON_OBJECT
	is_bot_authored: BOOLEAN

invariant
	positive_room: room_id > 0
	known_kind: (create {CHAT_EVENT_KINDS}).is_known_kind (kind)

end
