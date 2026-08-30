note
	description: "[
		CHAT_JSON as the client must use it: a decoder that cannot bring
		the client down. The codec promises that decoding never raises,
		but a hostile server can still reach seams that promise does not
		cover today - a non-Latin-1 `kind' or `token' (`to_string_8'), an
		unparseable `created_at', an error reply with an empty message -
		and each is a precondition violation deep inside the codec: on the
		GUI, or on the poller's processor with no rescue. Every query here
		answers Void instead: the exception is caught, the attempt is not
		repeated, and the caller turns Void into a 502 result. The guard
		is defence in depth; the codec's own guards are the domain
		cluster's to add. Stateless apart from the codec it wraps.
	]"
	author: "Larry Rix"

class
	CLIENT_CODEC

create
	make

feature {NONE} -- Initialization

	make
		do
			create json.make
		end

feature -- Access

	json: CHAT_JSON
			-- The codec itself, for encoding (which never sees hostile input).

feature -- Decoding (never raises)

	object (a_bytes: READABLE_STRING_8): detachable SIMPLE_JSON_OBJECT
			-- The JSON object `a_bytes' encodes, or Void.
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				Result := json.object_from_bytes (a_bytes)
			end
		rescue
			l_failed := True
			retry
		end

	page (a_bytes: READABLE_STRING_8): detachable CHAT_PAGE
			-- The page `a_bytes' encodes (events ascending, statuses), or Void.
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				Result := json.page_from_bytes (a_bytes)
			end
		rescue
			l_failed := True
			retry
		end

	event (a_bytes: READABLE_STRING_8): detachable CHAT_EVENT
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				Result := json.event_from_bytes (a_bytes)
			end
		rescue
			l_failed := True
			retry
		end

	members (a_bytes: READABLE_STRING_8): detachable ARRAYED_LIST [CHAT_MEMBER]
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				Result := json.members_from_bytes (a_bytes)
			end
		rescue
			l_failed := True
			retry
		end

	login (a_bytes: READABLE_STRING_8): detachable TUPLE [token: STRING_8; member: CHAT_MEMBER]
			-- The token and member of a login reply; the token's shape is the caller's to check.
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				Result := json.login_from_bytes (a_bytes)
			end
		rescue
			l_failed := True
			retry
		end

	error (a_bytes: READABLE_STRING_8; a_http_status: INTEGER): detachable CHAT_ERROR
			-- The server's error reply, or Void (also when its message is empty).
		require
			error_status: a_http_status >= 400 and a_http_status <= 599
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				Result := json.error_from_bytes (a_bytes, a_http_status)
			end
		ensure
			right_status: attached Result as e implies e.http_status = a_http_status
		rescue
			l_failed := True
			retry
		end

end
