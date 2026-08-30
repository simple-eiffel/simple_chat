note
	description: "[
		One entry in a room's ordered log - the unit of history and of live
		delivery. Messages, image posts and system notices are events;
		`kind' plus a JSON `payload' keep new kinds (edits, reactions,
		replies) free of schema changes. Immutable once appended, and ids
		are strictly increasing across the whole store (DR-001).

		A bot-authored message begins with the marker (DR-002) and, since
		D4, the store refuses a draft whose bot flag disagrees with its
		sender - so the marker authenticates, not merely decorates. System
		events have sender 0 and nothing else does; an attachment rides
		only on an image event and is always a stored one.
	]"
	author: "Larry Rix"

class
	CHAT_EVENT

create
	make

feature {NONE} -- Initialization

	make (a_id, a_room_id, a_sender_id: INTEGER_64; a_kind: READABLE_STRING_8; a_created_at: SIMPLE_DATE_TIME;
			a_body: READABLE_STRING_GENERAL; a_attachment: detachable CHAT_ATTACHMENT; a_payload: SIMPLE_JSON_OBJECT; a_bot: BOOLEAN)
		require
			positive_id: a_id > 0
			positive_room: a_room_id > 0
			known_kind: is_known_kind (a_kind)
			sender_or_system: a_sender_id > 0 or (a_sender_id = 0 and a_kind.same_string (Kind_system))
			message_has_body: a_kind.same_string (Kind_message) implies not a_body.is_empty
			image_has_attachment: a_kind.same_string (Kind_image) implies a_attachment /= Void
			attachment_only_on_images: a_attachment /= Void implies a_kind.same_string (Kind_image)
			attachment_stored: attached a_attachment as a implies a.is_stored
			bot_marked: (a_bot and a_kind.same_string (Kind_message)) implies a_body.to_string_32.starts_with (Bot_marker)
		do
			id := a_id
			room_id := a_room_id
			sender_id := a_sender_id
			kind := a_kind.to_string_8
			created_at := a_created_at
			body := a_body.to_string_32
			attachment := a_attachment
			payload := a_payload
			is_bot_authored := a_bot
		ensure
			set: id = a_id and room_id = a_room_id and sender_id = a_sender_id
			kind_set: kind.same_string (a_kind)
			body_set: body.same_string_general (a_body)
			bot_set: is_bot_authored = a_bot
			created_set: created_at = a_created_at
			attachment_set: attachment = a_attachment
			payload_set: payload = a_payload
		end

feature -- Access

	id: INTEGER_64
	room_id: INTEGER_64
	sender_id: INTEGER_64
			-- 0 for system events, and only for them.
	kind: STRING_8
	created_at: SIMPLE_DATE_TIME
	body: STRING_32
	attachment: detachable CHAT_ATTACHMENT
	payload: SIMPLE_JSON_OBJECT
	is_bot_authored: BOOLEAN

feature -- Status report

	is_message: BOOLEAN
		do
			Result := kind.same_string (Kind_message)
		end

	is_image: BOOLEAN
		do
			Result := kind.same_string (Kind_image)
		end

	is_system: BOOLEAN
		do
			Result := kind.same_string (Kind_system)
		end

feature -- Conversion

	to_json: SIMPLE_JSON_OBJECT
			-- The wire form: id, room_id, kind, sender_id, created_at, body,
			-- attachment (id, mime, size, name, sha256) or null, payload, is_bot.
		do
			Result := (create {CHAT_JSON}.make).event_to_json (Current)
		ensure
			attached_result: Result /= Void
			carries_id: Result.integer_item ({CHAT_JSON}.Key_id) = id
		end

feature -- Validation (contract support)

	is_known_kind (a_kind: READABLE_STRING_8): BOOLEAN
		do
			Result := a_kind.same_string (Kind_message) or a_kind.same_string (Kind_image) or a_kind.same_string (Kind_system)
		end

feature -- Constants

	Kind_message: STRING_8 = "message"
	Kind_image: STRING_8 = "image"
	Kind_system: STRING_8 = "system"

	Bot_marker: STRING_32 = "%/129302/"
			-- U+1F916, the robot face.

invariant
	positive_id: id > 0
	positive_room: room_id > 0
	known_kind: is_known_kind (kind)
	sender_non_negative: sender_id >= 0
	sender_or_system: sender_id > 0 or is_system
	message_has_body: is_message implies not body.is_empty
	image_has_attachment: is_image implies attachment /= Void
	attachment_only_on_images: attachment /= Void implies is_image
	attachment_stored: attached attachment as a implies a.is_stored
	marked_when_bot: (is_bot_authored and is_message) implies body.starts_with (Bot_marker)

end
