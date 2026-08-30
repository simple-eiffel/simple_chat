note
	description: "[
		The client's side of the JSON API. Owns the session token, which
		lives in memory only and leaves this class solely as an
		`Authorization: Bearer' header - never in a URL, never logged.
		Every call is one synchronous exchange through HTTP_TRANSPORT and
		returns a CHAT_RESULT; a network condition is a result, not an
		exception. Threading belongs to the caller (EVENT_POLLER on a
		worker; everything else from the GUI thread).
	]"
	author: "Larry Rix"

class
	CHAT_CLIENT

create
	make

feature {NONE} -- Initialization

	make (a_transport: HTTP_TRANSPORT; a_endpoint: CHAT_ENDPOINT)
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

	last_status: INTEGER
			-- HTTP status of the last exchange; 0 when the transport failed.

feature -- Status report

	is_logged_in: BOOLEAN
		do
			Result := token.count = Token_length
		end

feature -- Session

	login (a_username: READABLE_STRING_8; a_password: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_MEMBER]
			-- POST /login; on success the token is kept and `me' is set.
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
			l_reply := exchange ("POST", Path_login, plain_headers, codec.bytes_of (l_body), Default_timeout_seconds)
			if l_reply.is_success and then attached codec.login_from_bytes (l_reply.body) as l_login then
				token := l_login.token
				me := l_login.member
				create Result.make_success (l_login.member)
			else
				create Result.make_error (error_of (l_reply))
			end
		ensure
			outcome: Result.is_success = is_logged_in
			me_on_success: Result.is_success implies (attached me as m and then attached Result.value as v and then m = v)
		end

	logout
			-- POST /logout; the token is forgotten whatever the server says.
		require
			logged_in: is_logged_in
		local
			l_reply: HTTP_REPLY
		do
			l_reply := exchange ("POST", Path_logout, authorized_headers, Void, Default_timeout_seconds)
			create token.make_empty
			me := Void
		ensure
			logged_out: not is_logged_in
			forgotten: me = Void
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
			Result := page_result (l_reply, a_since_id, a_limit)
		ensure
			bounded: (Result.is_success and then attached Result.value as p) implies p.events.count <= a_limit
			all_after: (Result.is_success and then attached Result.value as p) implies across p.events as e all e.id > a_since_id end
		end

	wait_for_events (a_room_id, a_since_id: INTEGER_64; a_limit, a_seconds: INTEGER): CHAT_RESULT [CHAT_PAGE]
			-- GET /rooms/{id}/wait?since=N&limit=M&seconds=S - the long-poll (D-018):
			-- returns when something is there, or empty after `a_seconds'.
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
			Result := page_result (l_reply, a_since_id, a_limit)
		ensure
			bounded: (Result.is_success and then attached Result.value as p) implies p.events.count <= a_limit
			all_after: (Result.is_success and then attached Result.value as p) implies across p.events as e all e.id > a_since_id end
		end

	members (a_room_id: INTEGER_64): CHAT_RESULT [ARRAYED_LIST [CHAT_MEMBER]]
			-- GET /rooms/{id}/members - the roster, for names and @ completion.
		require
			logged_in: is_logged_in
			positive_room: a_room_id > 0
		local
			l_reply: HTTP_REPLY
		do
			l_reply := exchange ("GET", room_path (a_room_id, "/members"), authorized_headers, Void, Default_timeout_seconds)
			if l_reply.is_success and then attached codec.members_from_bytes (l_reply.body) as l_list then
				create Result.make_success (l_list)
			else
				create Result.make_error (error_of (l_reply))
			end
		end

feature -- Posting

	post_message (a_room_id: INTEGER_64; a_body: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_EVENT]
			-- POST /rooms/{id}/messages {"body": ...}; 201 with the stored event.
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
			l_reply := exchange ("POST", room_path (a_room_id, "/messages"), authorized_headers, codec.bytes_of (l_json), Default_timeout_seconds)
			if l_reply.is_success and then attached codec.event_from_bytes (l_reply.body) as e then
				create Result.make_success (e)
			else
				create Result.make_error (error_of (l_reply))
			end
		ensure
			echoed: (Result.is_success and then attached Result.value as e) implies e.room_id = a_room_id
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
		end

feature -- Requests (contract support)

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

	room_path (a_room_id: INTEGER_64; a_suffix: READABLE_STRING_8): STRING_8
		require
			positive_room: a_room_id > 0
			rooted: a_suffix.starts_with ("/")
		do
			Result := "/rooms/" + a_room_id.out + a_suffix
		ensure
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

feature {NONE} -- Implementation

	transport: HTTP_TRANSPORT
	codec: CHAT_JSON

	token: STRING_8
			-- Empty, or exactly `Token_length' characters.

	exchange (a_method, a_path: READABLE_STRING_8; a_headers: HASH_TABLE [STRING_8, STRING_8]; a_body: detachable READABLE_STRING_8;
			a_timeout_seconds: INTEGER): HTTP_REPLY
			-- One exchange against `endpoint'; records `last_status'.
		require
			rooted: a_path.starts_with ("/")
		do
			Result := transport.send (a_method, endpoint.url_for (a_path), a_headers, a_body, a_timeout_seconds)
			last_status := Result.status
		ensure
			recorded: last_status = Result.status
		end

	page_result (a_reply: HTTP_REPLY; a_since_id: INTEGER_64; a_limit: INTEGER): CHAT_RESULT [CHAT_PAGE]
			-- A page the server's contract allows, or an error.
		do
			if a_reply.is_success and then attached codec.page_from_bytes (a_reply.body) as p
				and then p.events.count <= a_limit and then (p.events.is_empty or else p.events.first.id > a_since_id)
			then
				create Result.make_success (p)
			elseif a_reply.is_success then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "The server's answer was not a valid page", 502))
			else
				create Result.make_error (error_of (a_reply))
			end
		end

	error_of (a_reply: HTTP_REPLY): CHAT_ERROR
			-- The server's own error when it sent one; otherwise the transport's reason or the bare status.
		do
			if not a_reply.is_exchanged then
				create Result.make ({CHAT_ERROR}.Code_unavailable, a_reply.error, 503)
			elseif attached codec.error_from_bytes (a_reply.body, a_reply.status) as e then
				Result := e
			else
				create Result.make ({CHAT_ERROR}.Code_unavailable, "HTTP " + a_reply.status.out, a_reply.status)
			end
		end

invariant
	token_shape: token.is_empty or token.count = Token_length
	me_iff_logged_in: (me /= Void) = is_logged_in

end
