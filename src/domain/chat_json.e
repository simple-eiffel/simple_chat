note
	description: "[
		The wire codec, both directions, in one place: events, members,
		pages (events + ephemeral statuses), the login reply and the error
		reply. The server encodes with it; the thick client decodes with
		it; the assault proves the round trip. Text travels as UTF-8 bytes
		(STRING_8) and lives as STRING_32 on either side.

		Decoding never raises on bad input: every `*_from_*' returns Void
		for anything that is not the expected shape.
	]"
	author: "Larry Rix"

class
	CHAT_JSON

create
	make

feature {NONE} -- Initialization

	make
		do
			create parser
		end

feature -- Encoding

	event_to_json (a_event: CHAT_EVENT): SIMPLE_JSON_OBJECT
			-- id, room_id, sender_id, kind, created_at, body, attachment | null, payload, is_bot.
		do
			create Result.make
			Result.put_integer (a_event.id, Key_id).do_nothing
			Result.put_integer (a_event.room_id, Key_room_id).do_nothing
			Result.put_integer (a_event.sender_id, Key_sender_id).do_nothing
			Result.put_string (a_event.kind.to_string_32, Key_kind).do_nothing
			Result.put_string (a_event.created_at.to_iso8601.to_string_32, Key_created_at).do_nothing
			Result.put_string (a_event.body, Key_body).do_nothing
			if attached a_event.attachment as a then
				Result.put_object (attachment_to_json (a), Key_attachment).do_nothing
			else
				Result.put_null (Key_attachment).do_nothing
			end
			Result.put_object (a_event.payload, Key_payload).do_nothing
			Result.put_boolean (a_event.is_bot_authored, Key_is_bot).do_nothing
		ensure
			carries_id: Result.integer_item (Key_id) = a_event.id
			carries_body: attached Result.string_item (Key_body) as b and then b.same_string (a_event.body)
		end

	attachment_to_json (a_attachment: CHAT_ATTACHMENT): SIMPLE_JSON_OBJECT
			-- id, mime, size, name, sha256 - enough for a client to fetch and to rebuild the stored path.
		do
			create Result.make
			Result.put_integer (a_attachment.id, Key_id).do_nothing
			Result.put_string (a_attachment.mime.to_string_32, Key_mime).do_nothing
			Result.put_integer (a_attachment.size, Key_size).do_nothing
			Result.put_string (a_attachment.original_name, Key_name).do_nothing
			Result.put_string (a_attachment.sha256.to_string_32, Key_sha256).do_nothing
		end

	member_to_json (a_member: CHAT_MEMBER): SIMPLE_JSON_OBJECT
		do
			create Result.make
			Result.put_integer (a_member.id, Key_id).do_nothing
			Result.put_string (a_member.username.to_string_32, Key_username).do_nothing
			Result.put_string (a_member.display_name, Key_display_name).do_nothing
			Result.put_boolean (a_member.is_admin, Key_is_admin).do_nothing
			Result.put_boolean (a_member.is_bot, Key_is_bot).do_nothing
		end

	member_of (a_user: CHAT_USER): CHAT_MEMBER
			-- The public view of a stored user.
		require
			stored: a_user.is_stored
		do
			create Result.make (a_user.id, a_user.username, a_user.display_name, a_user.is_admin, a_user.is_bot)
		ensure
			same_identity: Result.id = a_user.id and Result.username.same_string (a_user.username)
		end

	status_to_json (a_status: CHAT_STATUS): SIMPLE_JSON_OBJECT
		do
			create Result.make
			Result.put_integer (a_status.room_id, Key_room_id).do_nothing
			Result.put_string (a_status.from_display_name, Key_from).do_nothing
			Result.put_string (a_status.text, Key_text).do_nothing
		end

	statuses_to_json (a_statuses: LIST [CHAT_STATUS]): SIMPLE_JSON_ARRAY
		do
			create Result.make
			across a_statuses as s loop
				Result.add_object (status_to_json (s)).do_nothing
			end
		ensure
			same_count: Result.count = a_statuses.count
		end

	page_to_json (a_events: LIST [CHAT_EVENT]; a_statuses: LIST [CHAT_STATUS]): SIMPLE_JSON_OBJECT
			-- {"events": [...], "statuses": [...], "last_id": N}
		do
			Result := page_to_json_merged (a_events, statuses_to_json (a_statuses))
		ensure
			counted: attached Result.array_item (Key_events) as arr and then arr.count = a_events.count
		end

	page_to_json_merged (a_events: LIST [CHAT_EVENT]; a_statuses: SIMPLE_JSON_ARRAY): SIMPLE_JSON_OBJECT
			-- A page whose statuses arrive already encoded (a long-poll's waiter keeps them as JSON).
		local
			l_events: SIMPLE_JSON_ARRAY
			l_last: INTEGER_64
		do
			create l_events.make
			across a_events as e loop
				l_events.add_object (event_to_json (e)).do_nothing
				l_last := l_last.max (e.id)
			end
			create Result.make
			Result.put_array (l_events, Key_events).do_nothing
			Result.put_array (a_statuses, Key_statuses).do_nothing
			Result.put_integer (l_last, Key_last_id).do_nothing
		ensure
			counted: attached Result.array_item (Key_events) as arr and then arr.count = a_events.count
			statuses_kept: attached Result.array_item (Key_statuses) as sarr and then sarr.count = a_statuses.count
		end

	bytes_of_array (a_array: SIMPLE_JSON_ARRAY): STRING_8
			-- UTF-8 for the wire.
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_array.to_json_string)
		ensure
			array_text: Result.starts_with ("[") and Result.ends_with ("]")
		end

	login_to_json (a_token: READABLE_STRING_8; a_member: CHAT_MEMBER): SIMPLE_JSON_OBJECT
		require
			token_shape: a_token.count = 64
		do
			create Result.make
			Result.put_string (a_token.to_string_32, Key_token).do_nothing
			Result.put_object (member_to_json (a_member), Key_member).do_nothing
		end

	error_to_json (a_error: CHAT_ERROR): SIMPLE_JSON_OBJECT
		do
			create Result.make
			Result.put_string (a_error.code.to_string_32, Key_code).do_nothing
			Result.put_string (a_error.message, Key_message).do_nothing
		end

	bytes_of (a_object: SIMPLE_JSON_OBJECT): STRING_8
			-- UTF-8 for the wire.
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_object.to_json_string)
		end

feature -- Decoding

	object_from_bytes (a_bytes: READABLE_STRING_8): detachable SIMPLE_JSON_OBJECT
			-- The JSON object `a_bytes' (UTF-8) encodes, or Void.
		do
			if attached parser.parse_message ({UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_bytes)) as v and then v.is_object then
				Result := v.as_object
			end
		end

	array_from_bytes (a_bytes: READABLE_STRING_8): detachable SIMPLE_JSON_ARRAY
			-- The JSON array `a_bytes' (UTF-8) encodes, or Void.
		do
			if attached parser.parse_message ({UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_bytes)) as v and then v.is_array then
				Result := v.as_array
			end
		end

	event_from_json (a_object: SIMPLE_JSON_OBJECT): detachable CHAT_EVENT
			-- Void unless every required field is present and CHAT_EVENT's rules hold.
		local
			l_kind: STRING_8
			l_at: SIMPLE_DATE_TIME
			l_id, l_room, l_sender: INTEGER_64
			l_body: STRING_32
			l_attachment: detachable CHAT_ATTACHMENT
			l_payload: SIMPLE_JSON_OBJECT
			l_bot: BOOLEAN
			l_rules: CHAT_EVENT_KINDS
		do
			create l_rules
			l_id := a_object.integer_item (Key_id)
			l_room := a_object.integer_item (Key_room_id)
			l_sender := a_object.integer_item (Key_sender_id)
			l_bot := a_object.boolean_item (Key_is_bot)
			if attached a_object.string_item (Key_kind) as k and then l_rules.is_known_kind (k.to_string_8)
				and then attached a_object.string_item (Key_created_at) as t and then attached a_object.string_item (Key_body) as b
			then
				l_kind := k.to_string_8
				l_body := b
				create l_at.make_from_iso8601 (t.to_string_8)
				if attached a_object.object_item (Key_attachment) as ao then
					l_attachment := attachment_from_json (ao, l_sender, l_at)
				end
				if attached a_object.object_item (Key_payload) as po then
					l_payload := po
				else
					create l_payload.make
				end
				if l_id > 0 and l_room > 0 and (l_sender > 0 or l_kind.same_string ({CHAT_EVENT_KINDS}.Kind_system))
					and (not l_kind.same_string ({CHAT_EVENT_KINDS}.Kind_message) or not l_body.is_empty)
					and (not l_kind.same_string ({CHAT_EVENT_KINDS}.Kind_image) or l_attachment /= Void)
					and (not (l_bot and l_kind.same_string ({CHAT_EVENT_KINDS}.Kind_message)) or l_body.starts_with ({CHAT_EVENT_KINDS}.Bot_marker))
				then
					create Result.make (l_id, l_room, l_sender, l_kind, l_at, l_body, l_attachment, l_payload, l_bot)
				end
			end
		ensure
			faithful: attached Result as e implies (e.id = a_object.integer_item (Key_id) and e.room_id = a_object.integer_item (Key_room_id))
		end

	attachment_from_json (a_object: SIMPLE_JSON_OBJECT; a_uploader_id: INTEGER_64; a_created_at: SIMPLE_DATE_TIME): detachable CHAT_ATTACHMENT
			-- The stored path is rebuilt from the hash and the mime type (uploads/<sha256>.<ext>).
		local
			l_mime: STRING_8
			l_sha: STRING_8
			l_relpath: STRING_8
			l_name: STRING_32
			l_probe: CHAT_ATTACHMENT_RULES
		do
			create l_probe
			if attached a_object.string_item (Key_mime) as m and then attached a_object.string_item (Key_sha256) as h then
				l_mime := m.to_string_8
				l_sha := h.to_string_8
				if attached a_object.string_item (Key_name) as n then
					l_name := n
				else
					create l_name.make_empty
				end
				if l_probe.is_allowed_mime (l_mime) and l_sha.count = 64 and a_uploader_id > 0 and a_object.integer_item (Key_size) > 0 and a_object.integer_item (Key_id) >= 0 then
					l_relpath := {CHAT_ATTACHMENT}.Uploads_prefix + l_sha + l_probe.extension_of (l_mime)
					create Result.make (a_object.integer_item (Key_id), a_uploader_id, l_name, l_mime, a_object.integer_item (Key_size), l_sha, l_relpath, a_created_at)
				end
			end
		end

	member_from_json (a_object: SIMPLE_JSON_OBJECT): detachable CHAT_MEMBER
		local
			l_rules: CHAT_USER_RULES
		do
			create l_rules
			if attached a_object.string_item (Key_username) as u and then attached a_object.string_item (Key_display_name) as d
				and then a_object.integer_item (Key_id) > 0 and then l_rules.is_valid_username (u.to_string_8) and then l_rules.is_valid_display_name (d)
			then
				create Result.make (a_object.integer_item (Key_id), u.to_string_8, d, a_object.boolean_item (Key_is_admin), a_object.boolean_item (Key_is_bot))
			end
		end

	status_from_json (a_object: SIMPLE_JSON_OBJECT): detachable CHAT_STATUS
		do
			if a_object.integer_item (Key_room_id) > 0 and then attached a_object.string_item (Key_from) as f and then not f.is_empty
				and then attached a_object.string_item (Key_text) as t and then not t.is_empty
			then
				create Result.make (a_object.integer_item (Key_room_id), f, t)
			end
		end

	page_from_bytes (a_bytes: READABLE_STRING_8): detachable CHAT_PAGE
			-- Events (ascending) and statuses; Void when the shape is wrong or any event is malformed.
		local
			l_events: ARRAYED_LIST [CHAT_EVENT]
			l_statuses: ARRAYED_LIST [CHAT_STATUS]
			l_ok: BOOLEAN
			i: INTEGER
		do
			if attached object_from_bytes (a_bytes) as o and then attached o.array_item (Key_events) as arr then
				l_ok := True
				create l_events.make (arr.count)
				from i := 1 until i > arr.count or not l_ok loop
					if attached arr.object_item (i) as eo and then attached event_from_json (eo) as e and then (l_events.is_empty or else e.id > l_events.last.id) then
						l_events.extend (e)
					else
						l_ok := False
					end
					i := i + 1
				end
				create l_statuses.make (2)
				if attached o.array_item (Key_statuses) as sarr then
					from i := 1 until i > sarr.count loop
						if attached sarr.object_item (i) as so and then attached status_from_json (so) as s then
							l_statuses.extend (s)
						end
						i := i + 1
					end
				end
				if l_ok then
					create Result.make (l_events, l_statuses)
				end
			end
		end

	event_from_bytes (a_bytes: READABLE_STRING_8): detachable CHAT_EVENT
		do
			if attached object_from_bytes (a_bytes) as o then
				Result := event_from_json (o)
			end
		end

	members_from_bytes (a_bytes: READABLE_STRING_8): detachable ARRAYED_LIST [CHAT_MEMBER]
			-- {"members": [...]}; Void when the shape is wrong or any member is malformed.
		local
			i: INTEGER
			l_ok: BOOLEAN
		do
			if attached object_from_bytes (a_bytes) as o and then attached o.array_item (Key_members) as arr then
				l_ok := True
				create Result.make (arr.count)
				from i := 1 until i > arr.count or not l_ok loop
					if attached arr.object_item (i) as mo and then attached member_from_json (mo) as m then
						Result.extend (m)
					else
						l_ok := False
					end
					i := i + 1
				end
				if not l_ok then
					Result := Void
				end
			end
		end

	login_from_bytes (a_bytes: READABLE_STRING_8): detachable TUPLE [token: STRING_8; member: CHAT_MEMBER]
		do
			if attached object_from_bytes (a_bytes) as o and then attached o.string_item (Key_token) as t and then t.count = 64
				and then attached o.object_item (Key_member) as mo and then attached member_from_json (mo) as m
			then
				Result := [t.to_string_8, m]
			end
		ensure
			token_shape: attached Result as r implies r.token.count = 64
		end

	error_from_bytes (a_bytes: READABLE_STRING_8; a_http_status: INTEGER): detachable CHAT_ERROR
		do
			if attached object_from_bytes (a_bytes) as o and then attached o.string_item (Key_code) as c and then not c.is_empty
				and then attached o.string_item (Key_message) as m
			then
				create Result.make (c.to_string_8, m, a_http_status)
			end
		end

feature -- Constants (wire keys)

	Key_id: STRING_32 = "id"
	Key_room_id: STRING_32 = "room_id"
	Key_sender_id: STRING_32 = "sender_id"
	Key_kind: STRING_32 = "kind"
	Key_created_at: STRING_32 = "created_at"
	Key_body: STRING_32 = "body"
	Key_attachment: STRING_32 = "attachment"
	Key_payload: STRING_32 = "payload"
	Key_is_bot: STRING_32 = "is_bot"
	Key_mime: STRING_32 = "mime"
	Key_size: STRING_32 = "size"
	Key_name: STRING_32 = "name"
	Key_sha256: STRING_32 = "sha256"
	Key_username: STRING_32 = "username"
	Key_display_name: STRING_32 = "display_name"
	Key_is_admin: STRING_32 = "is_admin"
	Key_from: STRING_32 = "from"
	Key_text: STRING_32 = "text"
	Key_events: STRING_32 = "events"
	Key_statuses: STRING_32 = "statuses"
	Key_last_id: STRING_32 = "last_id"
	Key_members: STRING_32 = "members"
	Key_token: STRING_32 = "token"
	Key_member: STRING_32 = "member"
	Key_code: STRING_32 = "code"
	Key_message: STRING_32 = "message"

feature {NONE} -- Implementation

	parser: SIMPLE_JSON

end
