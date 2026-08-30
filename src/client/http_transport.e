note
	description: "[
		The one place bytes leave the client. One synchronous exchange per
		call, bounded by a timeout; the caller owns threading. The real one
		(WINHTTP_TRANSPORT, apps/client) rides simple_winhttp; the test one
		(MEMORY_HTTP_TRANSPORT) replays a script and records every request,
		which is how the assault proves what was sent.
	]"
	author: "Larry Rix"

deferred class
	HTTP_TRANSPORT

feature -- Access

	exchange_count: INTEGER
			-- Requests attempted so far.
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Basic operations

	send (a_method, a_url: READABLE_STRING_8; a_headers: HASH_TABLE [STRING_8, STRING_8]; a_body: detachable READABLE_STRING_8;
			a_timeout_seconds: INTEGER): HTTP_REPLY
			-- One exchange; never raises for a network condition.
		require
			known_method: is_known_method (a_method)
			web_url: a_url.starts_with ("http://") or a_url.starts_with ("https://")
			positive_timeout: a_timeout_seconds > 0
		deferred
		ensure
			attempted: exchange_count = old exchange_count + 1
			attached_result: Result /= Void
		end

feature -- Validation (contract support)

	is_known_method (a_method: READABLE_STRING_8): BOOLEAN
		do
			Result := a_method.same_string ("GET") or a_method.same_string ("POST") or a_method.same_string ("DELETE")
		end

end
