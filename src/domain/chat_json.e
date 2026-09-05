note
	description: "[
		The wire codec, both directions, in one place: events, members,
		pages (events + ephemeral statuses), the login reply and the error
		reply. The server encodes with it; the thick client decodes with
		it; the assault proves the round trip. Text travels as UTF-8 bytes
		(STRING_8) and lives as STRING_32 on either side.

		Decoding never raises on bad input: every `*_from_*' returns Void
		for anything that is not the expected shape - including a field
		that ought to be ASCII but is not (kind, mime, sha256, username,
		token, code), a timestamp that is not ISO 8601, an attachment on a
		non-image event, an unstored attachment, or an error whose status
		is not an error status.
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

	login_to_json (a_token: READABLE_STRING_8; a_member: CHAT_MEMBER): SIMPLE_JSON_OBJECT
		require
			token_shape: is_hex_64 (a_token)
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

	bytes_of_array (a_array: SIMPLE_JSON_ARRAY): STRING_8
			-- UTF-8 for the wire.
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_array.to_json_string)
		ensure
			array_text: Result.starts_with ("[") and Result.ends_with ("]")
		end

feature -- Decoding

	object_from_bytes (a_bytes: READABLE_STRING_8): detachable SIMPLE_JSON_OBJECT
			-- The JSON object `a_bytes' (UTF-8) encodes, or Void - also Void for empty
			-- bytes (the parser requires text) and for nesting deeper than
			-- `Nesting_maximum' (a recursive parser's stack is nobody's contract).
		do
			if not a_bytes.is_empty and then max_nesting (a_bytes) <= Nesting_maximum
				and then attached parser.parse_message ({UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_bytes)) as v and then v.is_object
			then
				Result := v.as_object
			end
		ensure
			empty_is_void: a_bytes.is_empty implies Result = Void
			shallow: attached Result implies max_nesting (a_bytes) <= Nesting_maximum
		end

	array_from_bytes (a_bytes: READABLE_STRING_8): detachable SIMPLE_JSON_ARRAY
			-- The JSON array `a_bytes' (UTF-8) encodes, or Void - Void too for empty bytes and deep nesting.
		do
			if not a_bytes.is_empty and then max_nesting (a_bytes) <= Nesting_maximum
				and then attached parser.parse_message ({UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_bytes)) as v and then v.is_array
			then
				Result := v.as_array
			end
		ensure
			empty_is_void: a_bytes.is_empty implies Result = Void
			shallow: attached Result implies max_nesting (a_bytes) <= Nesting_maximum
		end

	event_from_json (a_object: SIMPLE_JSON_OBJECT): detachable CHAT_EVENT
			-- Void unless every required field is present, ASCII where it must be, and CHAT_EVENT's rules hold.
		local
			l_kind: STRING_8
			l_at: SIMPLE_DATE_TIME
			l_id, l_room, l_sender: INTEGER_64
			l_body: STRING_32
			l_attachment: detachable CHAT_ATTACHMENT
			l_payload: SIMPLE_JSON_OBJECT
			l_bot: BOOLEAN
			l_ok: BOOLEAN
			l_rules: CHAT_EVENT_KINDS
		do
			create l_rules
			l_id := a_object.integer_item (Key_id)
			l_room := a_object.integer_item (Key_room_id)
			l_sender := a_object.integer_item (Key_sender_id)
			l_bot := a_object.boolean_item (Key_is_bot)
			if attached ascii_item (a_object, Key_kind) as k and then l_rules.is_known_kind (k)
				and then attached ascii_item (a_object, Key_created_at) as t and then is_iso8601 (t)
				and then attached a_object.string_item (Key_body) as b
			then
				l_kind := k
				l_body := b
				create l_at.make_from_iso8601 (t)
				l_ok := True
				if attached a_object.object_item (Key_attachment) as ao then
					l_attachment := attachment_from_json (ao, l_sender, l_at)
					l_ok := l_attachment /= Void and l_kind.same_string ({CHAT_EVENT_KINDS}.Kind_image)
				end
				if attached a_object.object_item (Key_payload) as po then
					l_payload := po
				else
					create l_payload.make
				end
				if l_ok and l_id > 0 and l_room > 0
					and (l_sender > 0 or (l_sender = 0 and l_kind.same_string ({CHAT_EVENT_KINDS}.Kind_system)))
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
			-- A stored attachment (id > 0, hex sha256, allowed mime, valid name); its path is rebuilt, never read.
		local
			l_name: STRING_32
			l_probe: CHAT_ATTACHMENT_RULES
		do
			create l_probe
			if attached ascii_item (a_object, Key_mime) as m and then l_probe.is_allowed_mime (m)
				and then attached ascii_item (a_object, Key_sha256) as h and then l_probe.is_sha256_hex (h)
			then
				if attached a_object.string_item (Key_name) as n then
					l_name := n
				else
					create l_name.make_from_string ("image")
				end
				if a_uploader_id > 0 and a_object.integer_item (Key_size) > 0 and a_object.integer_item (Key_id) > 0 and l_probe.is_valid_name (l_name) then
					create Result.make (a_object.integer_item (Key_id), a_uploader_id, l_name, m, a_object.integer_item (Key_size), h, a_created_at)
				end
			end
		ensure
			stored: attached Result as a implies a.is_stored
		end

	member_from_json (a_object: SIMPLE_JSON_OBJECT): detachable CHAT_MEMBER
		local
			l_rules: CHAT_USER_RULES
		do
			create l_rules
			if attached ascii_item (a_object, Key_username) as u and then l_rules.is_valid_username (u)
				and then attached a_object.string_item (Key_display_name) as d and then l_rules.is_valid_display_name (d)
				and then a_object.integer_item (Key_id) > 0
			then
				create Result.make (a_object.integer_item (Key_id), u, d, a_object.boolean_item (Key_is_admin), a_object.boolean_item (Key_is_bot))
			end
		end

	status_from_json (a_object: SIMPLE_JSON_OBJECT): detachable CHAT_STATUS
		do
			if a_object.integer_item (Key_room_id) > 0 and then attached a_object.string_item (Key_from) as f
				and then attached a_object.string_item (Key_text) as t
				and then (not f.is_empty and f.count <= {CHAT_USER}.Display_name_maximum)
				and then (not t.is_empty and t.count <= {CHAT_STATUS}.Text_maximum)
			then
				create Result.make (a_object.integer_item (Key_room_id), f, t)
			end
		end

	page_from_bytes (a_bytes: READABLE_STRING_8): detachable CHAT_PAGE
			-- Events (strictly ascending) and statuses; Void when the shape is wrong or any event is malformed.
		local
			l_events: ARRAYED_LIST [CHAT_EVENT]
			l_statuses: ARRAYED_LIST [CHAT_STATUS]
			l_ok: BOOLEAN
			i: INTEGER
		do
			if attached object_from_bytes (a_bytes) as o and then attached o.array_item (Key_events) as arr then
				l_ok := True
				create l_events.make (arr.count)
				from
					i := 1
				until
					i > arr.count or not l_ok
				loop
					if attached arr.object_item (i) as eo and then attached event_from_json (eo) as e and then (l_events.is_empty or else e.id > l_events.last.id) then
						l_events.extend (e)
					else
						l_ok := False
					end
					i := i + 1
				end
				create l_statuses.make (2)
				if attached o.array_item (Key_statuses) as sarr then
					from
						i := 1
					until
						i > sarr.count
					loop
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
				from
					i := 1
				until
					i > arr.count or not l_ok
				loop
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

	users_from_bytes (a_bytes: READABLE_STRING_8): detachable ARRAYED_LIST [CHAT_MEMBER]
			-- {"users": [...]} - the administrator's list, people and bots alike;
			-- Void when the shape is wrong or any member is malformed. The same
			-- shape as `members_from_bytes' under the other key: an object
			-- wrapping an array, never a bare array (the /participants lesson).
		local
			i: INTEGER
			l_ok: BOOLEAN
		do
			if attached object_from_bytes (a_bytes) as o and then attached o.array_item (Key_users) as arr then
				l_ok := True
				create Result.make (arr.count)
				from
					i := 1
				until
					i > arr.count or not l_ok
				loop
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
			-- A 64-hex token and a member, or Void.
		do
			if attached object_from_bytes (a_bytes) as o and then attached ascii_item (o, Key_token) as t and then is_hex_64 (t)
				and then attached o.object_item (Key_member) as mo and then attached member_from_json (mo) as m
			then
				Result := [t, m]
			end
		ensure
			token_shape: attached Result as r implies is_hex_64 (r.token)
		end

	error_from_bytes (a_bytes: READABLE_STRING_8; a_http_status: INTEGER): detachable CHAT_ERROR
			-- The server's error, when `a_http_status' is an error status and the body names a known code with a message.
		local
			l_code: STRING_8
		do
			if a_http_status >= 400 and a_http_status <= 599 and then attached object_from_bytes (a_bytes) as o
				and then attached ascii_item (o, Key_code) as c and then not c.is_empty
				and then attached o.string_item (Key_message) as m and then not m.is_empty
			then
				if (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "probe", 503)).is_known_code (c) then
					l_code := c
				else
					l_code := {CHAT_ERROR}.Code_unavailable
				end
				create Result.make (l_code, m, a_http_status)
			end
		ensure
			only_error_statuses: (a_http_status < 400 or a_http_status > 599) implies Result = Void
			status_kept: attached Result as e implies e.http_status = a_http_status
		end

feature -- Validation (contract support)

	is_hex_64 (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Exactly 64 lowercase hexadecimal characters?
		local
			i: INTEGER
			c: NATURAL_32
		do
			Result := a_text.count = 64
			from
				i := 1
			until
				i > a_text.count or not Result
			loop
				c := a_text.code (i)
				Result := (c >= 48 and c <= 57) or (c >= 97 and c <= 102)
				i := i + 1
			end
		end

	is_iso8601 (a_text: READABLE_STRING_8): BOOLEAN
			-- yyyy-mm-ddThh:mm:ss, optionally followed by Z - the shape SIMPLE_DATE_TIME
			-- writes and reads - AND a date-time that exists (no February 30, no 24:00,
			-- a year from 1970 on), so that building the date cannot raise.
		local
			i: INTEGER
			c: CHARACTER_8
		do
			Result := a_text.count = 19 or (a_text.count = 20 and then a_text [20] = 'Z')
			from
				i := 1
			until
				i > 19 or not Result
			loop
				c := a_text [i]
				if i = 5 or i = 8 then
					Result := c = '-'
				elseif i = 11 then
					Result := c = 'T'
				elseif i = 14 or i = 17 then
					Result := c = ':'
				else
					Result := c >= '0' and c <= '9'
				end
				i := i + 1
			end
			if Result then
				Result := is_valid_date_time (a_text.substring (1, 4).to_integer, a_text.substring (6, 7).to_integer, a_text.substring (9, 10).to_integer,
					a_text.substring (12, 13).to_integer, a_text.substring (15, 16).to_integer, a_text.substring (18, 19).to_integer)
			end
		ensure
			shaped: Result implies (a_text.count = 19 or a_text.count = 20)
		end

	is_valid_date_time (a_year, a_month, a_day, a_hour, a_minute, a_second: INTEGER): BOOLEAN
			-- A calendar date from 1970 to 9999 and a time of day that exist?
		do
			Result := a_year >= 1970 and a_year <= 9999 and a_month >= 1 and a_month <= 12
				and a_day >= 1 and then a_day <= days_in_month (a_year, a_month)
				and a_hour >= 0 and a_hour <= 23 and a_minute >= 0 and a_minute <= 59 and a_second >= 0 and a_second <= 59
		ensure
			day_in_month: Result implies (a_day >= 1 and a_day <= days_in_month (a_year, a_month))
			time_of_day: Result implies (a_hour <= 23 and a_minute <= 59 and a_second <= 59)
		end

	days_in_month (a_year, a_month: INTEGER): INTEGER
		require
			month_in_range: a_month >= 1 and a_month <= 12
		do
			inspect a_month
			when 4, 6, 9, 11 then
				Result := 30
			when 2 then
				if is_leap_year (a_year) then
					Result := 29
				else
					Result := 28
				end
			else
				Result := 31
			end
		ensure
			in_range: Result >= 28 and Result <= 31
		end

	is_leap_year (a_year: INTEGER): BOOLEAN
		do
			Result := (a_year \\ 4 = 0 and a_year \\ 100 /= 0) or a_year \\ 400 = 0
		end

	max_nesting (a_bytes: READABLE_STRING_8): INTEGER
			-- The deepest bracket nesting in `a_bytes', brackets inside string
			-- literals not counted (a backslash escapes the next byte).
		local
			i, l_depth: INTEGER
			l_in_string, l_escaped: BOOLEAN
			c: CHARACTER_8
		do
			from
				i := 1
			until
				i > a_bytes.count
			loop
				c := a_bytes [i]
				if l_in_string then
					if l_escaped then
						l_escaped := False
					elseif c = '%/92/' then
						l_escaped := True
					elseif c = '"' then
						l_in_string := False
					end
				elseif c = '"' then
					l_in_string := True
				elseif c = '{' or c = '[' then
					l_depth := l_depth + 1
					Result := Result.max (l_depth)
				elseif c = '}' or c = ']' then
					l_depth := l_depth - 1
				end
				i := i + 1
			end
		ensure
			non_negative: Result >= 0
			bounded_by_length: Result <= a_bytes.count
		end

feature {NONE} -- Decoding helpers

	ascii_item (a_object: SIMPLE_JSON_OBJECT; a_key: STRING_32): detachable STRING_8
			-- The string under `a_key' when it is plain ASCII; Void otherwise (never a precondition on `to_string_8').
		do
			if attached a_object.string_item (a_key) as s and then across s as c all c.natural_32_code < 128 end then
				Result := s.to_string_8
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
	Key_users: STRING_32 = "users"
	Key_participants: STRING_32 = "participants"
	Key_handle: STRING_32 = "handle"
	Key_path: STRING_32 = "path"

	Nesting_maximum: INTEGER = 32
			-- Deeper JSON is refused before parsing: nothing on the wire nests past four.
	Key_message: STRING_32 = "message"

feature {NONE} -- Implementation

	parser: SIMPLE_JSON

end
