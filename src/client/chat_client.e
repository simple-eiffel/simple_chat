note
	description: "[
		The client's side of the JSON API. Owns the session token, which
		lives in memory only and leaves this class in two ways only: as
		an `Authorization: Bearer' header to an endpoint that is https or
		loopback (never plaintext - a precondition at creation and an
		invariant after), or into another CHAT_CLIENT on the poller's
		processor (`hand_session_to'). Never in a URL, never in a body,
		never through a public query; dropped by `logout' (which tells
		the server) or by `forget_session' (which does not - the server
		has already rejected it). A token is exactly 64 lowercase hex
		digits - the shape SESSION_ISSUER mints - so nothing a hostile
		server sends can be folded into a header.

		Every call is one synchronous exchange through HTTP_TRANSPORT and
		returns a CHAT_RESULT: a network condition is a result, a reply
		that is not what the API promises is a 502 result, and no reply
		of any shape is an exception (CLIENT_CODEC). One client per
		processor: the GUI's for posting, the poller's for polling.
	]"
	author: "Larry Rix"

class
	CHAT_CLIENT

create
	make

feature {NONE} -- Initialization

	make (a_transport: HTTP_TRANSPORT; a_endpoint: CHAT_ENDPOINT)
		require
			secure: a_endpoint.is_secure
		do
			transport := a_transport
			endpoint := a_endpoint
			create token.make_empty
			create codec.make
			create header_text
		ensure
			set: transport = a_transport and endpoint = a_endpoint
			logged_out: not is_logged_in
		end

feature -- Access

	endpoint: CHAT_ENDPOINT

	me: detachable CHAT_MEMBER
			-- Who is logged in.

	last_status: INTEGER
			-- The HTTP status of the last exchange this client made, as HTTP_REPLY reports
			-- it: 0 EXACTLY when that exchange failed at the transport - nothing answered -
			-- and 0 before any exchange at all; 200..599 otherwise. CHAT_ERROR cannot carry
			-- this: a transport failure and a server's own 503 both arrive as 503, and the
			-- window has to tell them apart to say anything a member can act on
			-- (CONNECTION_ADVICE).

feature -- Status report

	is_logged_in: BOOLEAN
		do
			Result := not token.is_empty
		end

feature -- Session

	login (a_username: READABLE_STRING_8; a_password: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_MEMBER]
			-- POST /login; on success the token is kept and `me' is set. A 200 whose token
			-- is not 64 hex digits, or whose body is not a login reply, is a 502 result.
		require
			logged_out: not is_logged_in
			username_given: not a_username.is_empty
			password_given: not a_password.is_empty
		local
			l_body: SIMPLE_JSON_OBJECT
			l_reply: HTTP_REPLY
		do
			create l_body.make
			l_body.put_string (a_username.to_string_32, Key_username).do_nothing
			l_body.put_string (a_password.to_string_32, Key_password).do_nothing
			l_reply := exchange ("POST", Path_login, plain_headers, codec.json.bytes_of (l_body), Default_timeout_seconds)
			if l_reply.is_success and then attached codec.login (l_reply.body) as l_login and then is_hex_64 (l_login.token) then
				token := l_login.token
				me := l_login.member
				create Result.make_success (l_login.member)
			else
				create Result.make_error (error_of (l_reply))
			end
		ensure
			outcome: Result.is_success = is_logged_in
			me_on_success: Result.is_success implies (attached me as m and then attached Result.value as v and then m = v)
			endpoint_kept: endpoint = old endpoint
		end

	logout
			-- POST /logout; the token is forgotten before the request goes out, whatever the server says.
		require
			logged_in: is_logged_in
		local
			l_headers: HASH_TABLE [STRING_8, STRING_8]
			l_reply: HTTP_REPLY
		do
			l_headers := authorized_headers
			create token.make_empty
			me := Void
			l_reply := exchange ("POST", Path_logout, l_headers, Void, Default_timeout_seconds)
		ensure
			logged_out: not is_logged_in
			forgotten: me = Void
		end

	forget_session
			-- Drop the session without telling the server: it has already rejected the token (a 401
			-- met by the poller), so there is nothing to revoke and no exchange is made.
		require
			logged_in: is_logged_in
		do
			create token.make_empty
			me := Void
		ensure
			logged_out: not is_logged_in
			forgotten: me = Void
			no_exchange: transport.exchange_count = old transport.exchange_count
			endpoint_kept: endpoint = old endpoint
		end

	resume (a_token: READABLE_STRING_8): CHAT_RESULT [CHAT_MEMBER]
			-- Take up a session remembered from an earlier run (CLIENT_CONFIG.load_session):
			-- GET /me both proves the token is still live and says whose it is. Any other
			-- answer drops the token again, so a stale blob can never leave a half-session
			-- behind - the window then asks for a password, exactly as on a first run.
		require
			logged_out: not is_logged_in
			token_shape: is_hex_64 (a_token)
		local
			l_reply: HTTP_REPLY
		do
			token := a_token.to_string_8
			l_reply := exchange ("GET", Path_me, authorized_headers, Void, Default_timeout_seconds)
			if l_reply.is_success and then attached codec.member (l_reply.body) as m then
				me := m
				create Result.make_success (m)
			else
				create token.make_empty
				me := Void
				create Result.make_error (error_of (l_reply))
			end
		ensure
			outcome: Result.is_success = is_logged_in
			me_on_success: Result.is_success implies (attached me as m and then attached Result.value as v and then m = v)
			nothing_kept_on_failure: not Result.is_success implies me = Void
			endpoint_kept: endpoint = old endpoint
		end

	remember_session_in (a_config: CLIENT_CONFIG)
			-- Seal the live session into `a_config' (DPAPI, `CLIENT_CONFIG.save_session').
			-- The command lives HERE and not on the window because the token never
			-- leaves this object in clear: "remember me" is a request, not a getter.
		require
			logged_in: is_logged_in
		do
			a_config.save_session (token)
		ensure
			session_kept: is_logged_in and me = old me
			remembered_or_no_dpapi: a_config.has_session or not (create {SIMPLE_ENCRYPTION}.make).is_dpapi_available
			written: a_config.file_exists (a_config.storage_path)
			endpoint_kept: endpoint = old endpoint
		end

	hand_session_to (a_other: separate CHAT_CLIENT)
			-- Copy this session into `a_other' (the poller's client on its own processor).
		require
			logged_in: is_logged_in
		do
			if attached me as m then
				a_other.adopt_session (token, m)
			end
		ensure
			session_kept: is_logged_in and me = old me
			handed: a_other.is_logged_in
		end

feature {CHAT_CLIENT} -- Session transfer

	adopt_session (a_token: separate READABLE_STRING_8; a_member: separate CHAT_MEMBER)
			-- Take over a session copied from another CHAT_CLIENT: the token and `me' are copied here.
			-- Once only: a live session is never replaced under a poller's feet.
		require
			logged_out: not is_logged_in
		local
			l_token, l_username: STRING_8
			l_display: STRING_32
		do
			create l_token.make_from_separate (a_token)
			create l_username.make_from_separate (a_member.username)
			create l_display.make_from_separate (a_member.display_name)
			check token_shape: is_hex_64 (l_token) end
			token := l_token
			create me.make (a_member.id, l_username, l_display, a_member.is_admin, a_member.is_bot)
		ensure
			logged_in: is_logged_in
			same_member: attached me as m and then m.id = a_member.id
		end

feature -- Reading

	events_since (a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): CHAT_RESULT [CHAT_PAGE]
			-- GET /rooms/{id}/events?since=N&limit=M - returns at once.
		require
			logged_in: is_logged_in
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
			limit_in_range: a_limit > 0 and a_limit <= Page_maximum
		local
			l_reply: HTTP_REPLY
		do
			l_reply := exchange ("GET", room_path (a_room_id, "/events") + "?since=" + a_since_id.out + "&limit=" + a_limit.out,
				authorized_headers, Void, Default_timeout_seconds)
			Result := page_result (l_reply, a_room_id, a_since_id, a_limit)
		ensure
			bounded: (Result.is_success and then attached Result.value as p) implies p.events.count <= a_limit
			all_after: (Result.is_success and then attached Result.value as p) implies across p.events as e all e.id > a_since_id end
			same_room: (Result.is_success and then attached Result.value as p) implies (across p.events as e all e.room_id = a_room_id end and across p.statuses as s all s.room_id = a_room_id end)
			session_kept: is_logged_in and me = old me
		end

	wait_for_events (a_room_id, a_since_id: INTEGER_64; a_limit, a_seconds: INTEGER): CHAT_RESULT [CHAT_PAGE]
			-- GET /rooms/{id}/wait?since=N&limit=M&seconds=S - the long-poll (D-018):
			-- returns when something is there, or empty after `a_seconds'. The transport
			-- waits `a_seconds' + `Wait_slack_seconds'.
		require
			logged_in: is_logged_in
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
			limit_in_range: a_limit > 0 and a_limit <= Page_maximum
			seconds_in_range: a_seconds >= 0 and a_seconds <= Max_wait_seconds
		local
			l_reply: HTTP_REPLY
		do
			l_reply := exchange ("GET", room_path (a_room_id, "/wait") + "?since=" + a_since_id.out + "&limit=" + a_limit.out + "&seconds=" + a_seconds.out,
				authorized_headers, Void, a_seconds + Wait_slack_seconds)
			Result := page_result (l_reply, a_room_id, a_since_id, a_limit)
		ensure
			bounded: (Result.is_success and then attached Result.value as p) implies p.events.count <= a_limit
			all_after: (Result.is_success and then attached Result.value as p) implies across p.events as e all e.id > a_since_id end
			same_room: (Result.is_success and then attached Result.value as p) implies (across p.events as e all e.room_id = a_room_id end and across p.statuses as s all s.room_id = a_room_id end)
			session_kept: is_logged_in and me = old me
		end

	participant_handles: CHAT_RESULT [ARRAYED_LIST [STRING_32]]
			-- GET /participants - the HANDLES the server answers to ("@claude"),
			-- which are NOT the bots' usernames ("claude_bot"). The roster gives
			-- usernames and only usernames, so a client that builds a mention out
			-- of the roster tells the member to type something the address parser
			-- will never match. Larry was told exactly that, and the summary rule
			-- missed "@claude sum" for the same reason - it looked for
			-- "@claude_bot". Handles come from here or from nowhere.
		require
			logged_in: is_logged_in
		local
			l_reply: HTTP_REPLY
			l_list: ARRAYED_LIST [STRING_32]
			i: INTEGER
		do
			l_reply := exchange ("GET", Path_participants, authorized_headers, Void, Default_timeout_seconds)
				-- {"participants": [...]} - an OBJECT wrapping the array, not a bare
				-- array like /rooms. Decoding it as a bare array fails silently,
				-- leaves the client with no handles, and every summary line is then
				-- posted to the room as an ordinary message. That is exactly what
				-- happened to "@claude sum".
			if l_reply.is_success and then attached codec.object (l_reply.body) as ob
				and then attached ob.array_item ({CHAT_JSON}.Key_participants) as a
			then
				create l_list.make (a.count)
				from i := 1 until i > a.count loop
					if attached a.object_item (i) as o and then attached o.string_item ({CHAT_JSON}.Key_handle) as h
						and then h.count >= 2 and then h.item (1) = '@'
					then
						l_list.extend (h.to_string_32)
					end
					i := i + 1
				end
				create Result.make_success (l_list)
			else
				create Result.make_error (error_of (l_reply))
			end
		ensure
			all_addressable: (Result.is_success and then attached Result.value as v) implies across v as h all h.starts_with ({STRING_32} "@") end
		end

	rooms: CHAT_RESULT [ARRAYED_LIST [TUPLE [id: INTEGER_64; name: STRING_32]]]
			-- GET /rooms - [{id, name}] for this member, in the server's order. A bare
			-- array, so it is decoded through CLIENT_CODEC.array; one malformed entry
			-- makes the whole answer a 502 result, never a half-list.
		require
			logged_in: is_logged_in
		local
			l_reply: HTTP_REPLY
			l_list: ARRAYED_LIST [TUPLE [id: INTEGER_64; name: STRING_32]]
			l_ok: BOOLEAN
			i: INTEGER
		do
			l_reply := exchange ("GET", Path_rooms, authorized_headers, Void, Default_timeout_seconds)
			if l_reply.is_success and then attached codec.array (l_reply.body) as a then
				create l_list.make (a.count)
				l_ok := True
				from
					i := 1
				until
					i > a.count or not l_ok
				loop
					if attached a.object_item (i) as o and then o.integer_item ({CHAT_JSON}.Key_id) > 0
						and then attached o.string_item ({CHAT_JSON}.Key_name) as n and then not n.is_empty
					then
						l_list.extend ([o.integer_item ({CHAT_JSON}.Key_id), n.to_string_32])
					else
						l_ok := False
					end
					i := i + 1
				variant
					a.count - i + 1
				end
			end
			if l_ok and then attached l_list as l_rooms then
				create Result.make_success (l_rooms)
			else
				create Result.make_error (error_of (l_reply))
			end
		ensure
			all_identified: (Result.is_success and then attached Result.value as l_r) implies across l_r as l_one all l_one.id > 0 end
			all_named: (Result.is_success and then attached Result.value as l_r) implies across l_r as l_one all not l_one.name.is_empty end
			session_kept: is_logged_in and me = old me
		end

	members (a_room_id: INTEGER_64): CHAT_RESULT [ARRAYED_LIST [CHAT_MEMBER]]
			-- GET /rooms/{id}/members - the roster, for names and @ completion. A roster
			-- naming a member twice is a 502 result.
		require
			logged_in: is_logged_in
			positive_room: a_room_id > 0
		local
			l_reply: HTTP_REPLY
		do
			l_reply := exchange ("GET", room_path (a_room_id, "/members"), authorized_headers, Void, Default_timeout_seconds)
			if l_reply.is_success and then attached codec.members (l_reply.body) as l_list and then has_distinct_ids (l_list) then
				create Result.make_success (l_list)
			else
				create Result.make_error (error_of (l_reply))
			end
		ensure
			distinct_ids: (Result.is_success and then attached Result.value as l) implies has_distinct_ids (l)
			session_kept: is_logged_in and me = old me
		end

feature -- Posting

	summarise (a_room_id, a_since_id, a_until_id: INTEGER_64; a_minutes: INTEGER): CHAT_RESULT [STRING_32]
			-- POST /rooms/{id}/summary {"since":, "until":, "minutes":}; 200 with
			-- the assistant's summary of that stretch, for THIS member only.
			--
			-- The answer is never a room event and is stored nowhere: it comes
			-- back in this reply and is drawn in this window alone, because the
			-- room's events are never per-person. The call waits on the engine,
			-- so it is given the upload timeout rather than the ordinary one.
		require
			logged_in: is_logged_in
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
			until_non_negative: a_until_id >= 0
			minutes_non_negative: a_minutes >= 0
		local
			l_json: SIMPLE_JSON_OBJECT
			l_reply: HTTP_REPLY
		do
			create l_json.make
			l_json.put_integer (a_since_id, Key_since).do_nothing
			l_json.put_integer (a_until_id, Key_until).do_nothing
			l_json.put_integer (a_minutes.to_integer_64, Key_minutes).do_nothing
			l_reply := exchange ("POST", room_path (a_room_id, "/summary"), authorized_headers, codec.json.bytes_of (l_json), Upload_timeout_seconds)
			if l_reply.is_success and then attached codec.object (l_reply.body) as o and then attached o.string_item (Key_summary) as l_text and then not l_text.is_empty then
				create Result.make_success (l_text)
			elseif l_reply.is_success then
				create Result.make_error (unexpected_answer)
			else
				create Result.make_error (error_of (l_reply))
			end
		ensure
			said_something: (Result.is_success and then attached Result.value as t) implies not t.is_empty
			session_kept: is_logged_in and me = old me
		end

	post_message (a_room_id: INTEGER_64; a_body: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_EVENT]
			-- POST /rooms/{id}/messages {"body": ...}; 201 with the stored event. An echo
			-- for another room, or of another kind, is a 502 result.
		require
			logged_in: is_logged_in
			positive_room: a_room_id > 0
			body_given: not a_body.is_empty
		local
			l_json: SIMPLE_JSON_OBJECT
			l_reply: HTTP_REPLY
		do
			create l_json.make
			l_json.put_string (a_body.to_string_32, Key_body).do_nothing
			l_reply := exchange ("POST", room_path (a_room_id, "/messages"), authorized_headers, codec.json.bytes_of (l_json), Default_timeout_seconds)
			if l_reply.is_success and then attached codec.event (l_reply.body) as e then
				if e.room_id = a_room_id and e.is_message then
					create Result.make_success (e)
				else
					create Result.make_error (unexpected_answer)
				end
			else
				create Result.make_error (error_of (l_reply))
			end
		ensure
			echoed: (Result.is_success and then attached Result.value as e) implies e.room_id = a_room_id
			message_kind: (Result.is_success and then attached Result.value as e) implies e.is_message
			session_kept: is_logged_in and me = old me
		end

	post_image (a_room_id: INTEGER_64; a_bytes: SPECIAL [NATURAL_8]; a_file_name: READABLE_STRING_GENERAL; a_caption: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_EVENT]
			-- POST /rooms/{id}/images: `a_bytes' ARE the body (that is what the
			-- request handler reads), the name and the caption ride on X-File-Name
			-- and X-Caption as CHAT_HEADER_TEXT writes them; 201 with the stored
			-- image event. An echo for another room, or of another kind, is a 502
			-- result, exactly as `post_message' treats one.
		require
			logged_in: is_logged_in
			positive_room: a_room_id > 0
			has_bytes: a_bytes.count > 0
		local
			l_reply: HTTP_REPLY
		do
			l_reply := exchange ("POST", room_path (a_room_id, "/images"), image_headers (a_file_name, a_caption),
				byte_string (a_bytes), Upload_timeout_seconds)
			if l_reply.is_success and then attached codec.event (l_reply.body) as e then
				if e.room_id = a_room_id and e.is_image then
					create Result.make_success (e)
				else
					create Result.make_error (unexpected_answer)
				end
			else
				create Result.make_error (error_of (l_reply))
			end
		ensure
			image_on_success: (Result.is_success and then attached Result.value as e) implies e.is_image
			echoed: (Result.is_success and then attached Result.value as e) implies e.room_id = a_room_id
			session_kept: is_logged_in and me = old me
		end

feature -- Validation (contract support)

	is_hex_64 (a_text: READABLE_STRING_8): BOOLEAN
			-- Exactly `Token_length' lowercase hex digits - the shape SESSION_ISSUER mints,
			-- and nothing a header could be broken with. CHAT_JSON's rule, the one choice.
		do
			Result := codec.json.is_hex_64 (a_text)
		ensure
			definition: Result = codec.json.is_hex_64 (a_text)
			length: Result implies a_text.count = Token_length
		end

	has_distinct_ids (a_list: LIST [CHAT_MEMBER]): BOOLEAN
			-- No two members with the same id?
		local
			l_seen: HASH_TABLE [BOOLEAN, INTEGER_64]
		do
			create l_seen.make (a_list.count)
			Result := True
			across a_list as m loop
				if l_seen.has (m.id) then
					Result := False
				else
					l_seen.force (True, m.id)
				end
			end
		end

	room_path (a_room_id: INTEGER_64; a_suffix: READABLE_STRING_8): STRING_8
		require
			positive_room: a_room_id > 0
			rooted: a_suffix.starts_with ("/")
		do
			Result := "/rooms/" + a_room_id.out + a_suffix
		ensure
			exact: Result.same_string ("/rooms/" + a_room_id.out + a_suffix)
			rooted: Result.starts_with ("/rooms/")
		end

feature -- Constants

	Token_length: INTEGER = 64
	Page_maximum: INTEGER = 500
	Max_wait_seconds: INTEGER = 25
	Wait_slack_seconds: INTEGER = 5
	Default_timeout_seconds: INTEGER = 15

	Upload_timeout_seconds: INTEGER = 60
			-- An image is up to the server's `upload_bytes' (8 MiB by default) and
			-- goes out on one exchange: a message's fifteen seconds is not enough
			-- room on a domestic uplink.

	Path_login: STRING_8 = "/login"
	Path_logout: STRING_8 = "/logout"
	Path_me: STRING_8 = "/me"
	Path_rooms: STRING_8 = "/rooms"
	Path_participants: STRING_8 = "/participants"
	Header_authorization: STRING_8 = "Authorization"
	Header_content_type: STRING_8 = "Content-Type"
	Header_file_name: STRING_8 = "X-File-Name"
	Header_caption: STRING_8 = "X-Caption"
	Content_type_octets: STRING_8 = "application/octet-stream"
	Key_username: STRING_32 = "username"
	Key_password: STRING_32 = "password"
	Key_body: STRING_32 = "body"
	Key_since: STRING_32 = "since"
	Key_until: STRING_32 = "until"
	Key_minutes: STRING_32 = "minutes"
	Key_summary: STRING_32 = "summary"

	Message_unexpected: STRING_32 = "The server's answer was not what was expected"

feature {NONE} -- Requests

	authorized_headers: HASH_TABLE [STRING_8, STRING_8]
			-- Accept + the Bearer token. The token appears nowhere else.
		require
			logged_in: is_logged_in
		do
			Result := plain_headers
			Result.force ("Bearer " + token, Header_authorization)
		ensure
			bearer: attached Result [Header_authorization] as h and then h.same_string ("Bearer " + token)
		end

	plain_headers: HASH_TABLE [STRING_8, STRING_8]
		do
			create Result.make (4)
			Result.force ("application/json", "Accept")
			Result.force ("application/json; charset=utf-8", "Content-Type")
		ensure
			no_token: not Result.has (Header_authorization)
		end

	image_headers (a_file_name, a_caption: READABLE_STRING_GENERAL): HASH_TABLE [STRING_8, STRING_8]
			-- `authorized_headers' with the body typed as opaque bytes and the name
			-- and caption written the one way a header line can carry them.
		require
			logged_in: is_logged_in
		do
			Result := authorized_headers
			Result.force (Content_type_octets, Header_content_type)
			Result.force (header_text.encoded (a_file_name), Header_file_name)
			Result.force (header_text.encoded (a_caption), Header_caption)
		ensure
			bearer: attached Result [Header_authorization] as h and then h.same_string ("Bearer " + token)
			octets: attached Result [Header_content_type] as t and then t.same_string (Content_type_octets)
			name_encoded: attached Result [Header_file_name] as n and then n.same_string (header_text.encoded (a_file_name))
			caption_encoded: attached Result [Header_caption] as c and then c.same_string (header_text.encoded (a_caption))
		end

	byte_string (a_bytes: SPECIAL [NATURAL_8]): STRING_8
			-- `a_bytes' as a byte string body. SIMPLE_WINHTTP marshals a body
			-- byte for byte - it copies `code (i)' into a MANAGED_POINTER rather
			-- than handing the string to C_STRING - so every value 0..255 put
			-- here, the zero byte included, is what goes on the wire.
		local
			i: INTEGER
		do
			create Result.make_filled ('%U', a_bytes.count)
			from
				i := 0
			until
				i >= a_bytes.count
			loop
				Result.put (a_bytes [i].to_character_8, i + 1)
				i := i + 1
			variant
				a_bytes.count - i
			end
		ensure
			sized: Result.count = a_bytes.count
				-- Byte-for-byte equality is proved in the assault, not asserted here:
				-- a per-byte postcondition would walk a whole image on every upload.
			first_byte_kept: a_bytes.count > 0 implies Result.code (1) = a_bytes [0].to_natural_32
			last_byte_kept: a_bytes.count > 0 implies Result.code (a_bytes.count) = a_bytes [a_bytes.count - 1].to_natural_32
		end

	exchange (a_method, a_path: READABLE_STRING_8; a_headers: HASH_TABLE [STRING_8, STRING_8]; a_body: detachable READABLE_STRING_8;
			a_timeout_seconds: INTEGER): HTTP_REPLY
			-- One exchange against `endpoint'.
		require
			rooted: a_path.starts_with ("/")
			token_over_tls: a_headers.has (Header_authorization) implies endpoint.is_secure
			positive_timeout: a_timeout_seconds > 0
		do
			Result := transport.send (a_method, endpoint.url_for (a_path), a_headers, a_body, a_timeout_seconds)
				-- Kept because `error_of' cannot: it maps a transport failure onto 503, which
				-- a server may also answer with of its own accord (CHAT_SERVICE.backup does).
			last_status := Result.status
		ensure
			attempted: transport.exchange_count = old transport.exchange_count + 1
		end

	page_result (a_reply: HTTP_REPLY; a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): CHAT_RESULT [CHAT_PAGE]
			-- A page the server's contract allows - at most `a_limit' events, all after `a_since_id',
			-- ascending, every event and status of `a_room_id' - carrying its wire bytes; or an error
			-- (502 for a 2xx that is not such a page).
		do
			if a_reply.is_success and then attached codec.page (a_reply.body) as p
				and then p.events.count <= a_limit and then (p.events.is_empty or else p.events.first.id > a_since_id)
				and then all_in_room (p, a_room_id)
			then
				create Result.make_success (create {CHAT_PAGE}.make_from_wire (p.events, p.statuses, a_reply.body))
			else
				create Result.make_error (error_of (a_reply))
			end
		ensure
			bounded: (Result.is_success and then attached Result.value as p) implies p.events.count <= a_limit
			all_after: (Result.is_success and then attached Result.value as p) implies across p.events as e all e.id > a_since_id end
			same_room: (Result.is_success and then attached Result.value as p) implies all_in_room (p, a_room_id)
			carries_bytes: (Result.is_success and then attached Result.value as p) implies p.bytes.same_string (a_reply.body)
			only_from_success: Result.is_success implies a_reply.is_success
		end

	all_in_room (a_page: CHAT_PAGE; a_room_id: INTEGER_64): BOOLEAN
			-- Every event and status of `a_page' belongs to `a_room_id'?
		do
			Result := across a_page.events as e all e.room_id = a_room_id end
				and across a_page.statuses as s all s.room_id = a_room_id end
		end

	error_of (a_reply: HTTP_REPLY): CHAT_ERROR
			-- The server's own error when it sent a well-formed one; 503 for a transport
			-- failure; 502 for any answer below 400 that could not be used; otherwise
			-- the bare status (with the server's code when it gave a usable one).
		do
			if not a_reply.is_exchanged then
				create Result.make ({CHAT_ERROR}.Code_unavailable, a_reply.error, 503)
			elseif a_reply.status < 400 then
				Result := unexpected_answer
			elseif attached codec.error (a_reply.body, a_reply.status) as e then
				Result := e
			else
				create Result.make (salvaged_code (a_reply.body), "HTTP " + a_reply.status.out, a_reply.status)
			end
		ensure
			error_status: Result.http_status >= 400 and Result.http_status <= 599
			transport_is_503: not a_reply.is_exchanged implies Result.http_status = 503
			unusable_is_502: (a_reply.is_exchanged and a_reply.status < 400) implies Result.http_status = 502
			status_kept: (a_reply.is_exchanged and a_reply.status >= 400) implies Result.http_status = a_reply.status
		end

	unexpected_answer: CHAT_ERROR
			-- 502: the server answered, but not with what the API promises.
		do
			create Result.make ({CHAT_ERROR}.Code_unavailable, Message_unexpected, 502)
		ensure
			gateway: Result.http_status = 502
		end

	salvaged_code (a_body: READABLE_STRING_8): STRING_8
			-- The "code" of an error reply whose message was unusable, when it is one CHAT_ERROR
			-- knows; else "unavailable". Never anything CHAT_ERROR.make would refuse.
		do
			if attached codec.object (a_body) as o and then attached o.string_item ({CHAT_JSON}.Key_code) as c
				and then not c.is_empty and then c.count <= Code_maximum
				and then across c as ch all (ch.natural_32_code >= 33 and ch.natural_32_code <= 126) end
				and then error_probe.is_known_code (c.to_string_8)
			then
				Result := c.to_string_8
			else
				Result := {CHAT_ERROR}.Code_unavailable
			end
		ensure
			given: not Result.is_empty
			known: error_probe.is_known_code (Result)
		end

	error_probe: CHAT_ERROR
			-- An instance to ask `is_known_code' of (it is not a class feature).
		once
			create Result.make ({CHAT_ERROR}.Code_unavailable, "probe", 503)
		end

	Code_maximum: INTEGER = 32

feature {NONE} -- Implementation

	transport: HTTP_TRANSPORT
	codec: CLIENT_CODEC

	header_text: CHAT_HEADER_TEXT
			-- The one rule for a file name or a caption on a header line; the
			-- request handler reads them back through the same class.

	token: STRING_8
			-- Empty, or exactly `Token_length' lowercase hex digits.

invariant
	token_shape: token.is_empty or is_hex_64 (token)
	me_iff_logged_in: (me /= Void) = is_logged_in
	never_plaintext: endpoint.is_secure

end
