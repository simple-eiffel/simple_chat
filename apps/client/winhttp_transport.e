note
	description: "[
		HTTP_TRANSPORT over WinHTTP (simple_winhttp, promoted from
		OCR_HTTP): HTTPS through SChannel with no redistributable, request
		headers, a receive timeout long enough for the long-poll, raw
		bytes for uploads. Phase 4 - the dependency task names exactly
		what OCR_HTTP lacks today (intent-v3 dependency audit). Redirects
		are never followed: the session must set
		WINHTTP_OPTION_REDIRECT_POLICY to WINHTTP_OPTION_REDIRECT_POLICY_NEVER,
		because WinHTTP's default follows a 3xx and would re-send the
		Authorization header to whatever host the reply names.
	]"
	author: "Larry Rix"

class
	WINHTTP_TRANSPORT

inherit
	HTTP_TRANSPORT

create
	make

feature {NONE} -- Initialization

	make
		do
		ensure
			nothing_sent: exchange_count = 0
		end

feature -- Access

	exchange_count: INTEGER

feature -- Basic operations

	send (a_method, a_url: READABLE_STRING_8; a_headers: HASH_TABLE [STRING_8, STRING_8]; a_body: detachable READABLE_STRING_8;
			a_timeout_seconds: INTEGER): HTTP_REPLY
		do
			exchange_count := exchange_count + 1
			-- Implementation in Phase 4 (simple_winhttp). On the session handle, before any request:
			-- WinHttpSetOption (WINHTTP_OPTION_REDIRECT_POLICY, WINHTTP_OPTION_REDIRECT_POLICY_NEVER),
			-- so that a 3xx comes back as the reply (HTTP_TRANSPORT's contract) and the bearer header
			-- is never re-sent to a redirect target.
			create Result.make_failed ("WINHTTP_TRANSPORT: not implemented (Phase 1 skeleton)")
		end

end
