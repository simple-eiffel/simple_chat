note
	description: "[
		The client's side of the JSON API. Owns the session token, which
		lives in memory only and leaves this class in two ways only: as
		an `Authorization: Bearer' header to an endpoint that is https or
		loopback (never plaintext - a precondition at creation and an
		invariant after), or into another CHAT_CLIENT on the poller's
		processor (`hand_session_to'). Never in a URL, never in a body,
		never through a public query. A token is exactly 64 lowercase hex
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
		ensure
			set: transport = a_transport and endpoint = a_endpoint
			logged_out: not is_logged_in
		end

feature -- Access

	endpoint: CHAT_ENDPOINT

	me: detachable CHAT_MEMBER
			-- Who is logged in.

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
			-- POST /rooms/{id}/images (multipart).
		require
			logged_in: is_logged_in
			positive_room: a_room_id > 0
			has_bytes: a_bytes.count > 0
		do
			-- Implementation in Phase 4 (multipart body through the transport)
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
		ensure
			image_on_success: (Result.is_success and then attached Result.value as e) implies e.is_image
			echoed: (Result.is_success and then attached Result.value as e) implies e.room_id = a_room_id
			session_kept: is_logged_in and me = old me
		end

feature -- Validation (contract support)

	is_hex_64 (a_text: READABLE_STRING_8): BOOLEAN
			-- Exactly `Token_length' lowercase hex digits - the shape SESSION_ISSUER mints,
			-- and nothing a header could be broken with.
		do
			Result := a_text.count = Token_length
				and then across a_text as c all ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f')) end
		ensure
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

	Path_login: STRING_8 = "/login"
	Path_logout: STRING_8 = "/logout"
	Header_authorization: STRING_8 = "Authorization"
	Key_username: STRING_32 = "username"
	Key_password: STRING_32 = "password"
	Key_body: STRING_32 = "body"

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

	exchange (a_method, a_path: READABLE_STRING_8; a_headers: HASH_TABLE [STRING_8, STRING_8]; a_body: detachable READABLE_STRING_8;
			a_timeout_seconds: INTEGER): HTTP_REPLY
			-- One exchange against `endpoint'.
		require
			rooted: a_path.starts_with ("/")
			token_over_tls: a_headers.has (Header_authorization) implies endpoint.is_secure
			positive_timeout: a_timeout_seconds > 0
		do
			Result := transport.send (a_method, endpoint.url_for (a_path), a_headers, a_body, a_timeout_seconds)
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
			-- The "code" of an error reply whose message was unusable, when it is a short printable
			-- ASCII word; else "unavailable".
		do
			if attached codec.object (a_body) as o and then attached o.string_item ({CHAT_JSON}.Key_code) as c
				and then not c.is_empty and then c.count <= Code_maximum
				and then across c as ch all (ch.natural_32_code >= 33 and ch.natural_32_code <= 126) end
			then
				Result := c.to_string_8
			else
				Result := {CHAT_ERROR}.Code_unavailable
			end
		ensure
			given: not Result.is_empty
		end

	Code_maximum: INTEGER = 32

feature {NONE} -- Implementation

	transport: HTTP_TRANSPORT
	codec: CLIENT_CODEC

	token: STRING_8
			-- Empty, or exactly `Token_length' lowercase hex digits.

invariant
	token_shape: token.is_empty or is_hex_64 (token)
	me_iff_logged_in: (me /= Void) = is_logged_in
	never_plaintext: endpoint.is_secure

end
