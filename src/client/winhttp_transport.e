note
	description: "[
		HTTP_TRANSPORT over simple_winhttp: HTTPS through SChannel with
		nothing to redistribute, request headers, a per-call receive
		timeout long enough for the long-poll, raw bytes both ways.
		Redirects are never followed - SIMPLE_WINHTTP switches its session
		to WINHTTP_OPTION_REDIRECT_POLICY_NEVER before any request and
		offers no way to turn that off (`Redirects_are_never_followed') -
		so a 3xx IS the reply here and a bearer header is never re-sent
		to whatever host a redirect names (CHAT_CLIENT treats the 3xx as
		a 502 result). A network condition is a failed HTTP_REPLY, never
		an exception; a 1xx, which HTTP_REPLY does not admit as a final
		answer, is reported as a transport failure; a URL or header set
		that could not go on the wire verbatim (non-ASCII, blanks, CR or
		LF) is refused the same way, before anything is sent. Bodies are
		bounded by `Body_maximum' inside the library itself: beyond it
		the exchange fails cleanly instead of growing without bound.
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
			-- A transport with the library's safe defaults, bodies bounded
			-- by `Body_maximum' and certificate validation on.
		do
			create http.make
			http.set_body_maximum (Body_maximum)
		ensure
			nothing_sent: exchange_count = 0
			bounded: http.body_maximum = Body_maximum
			validating: http.is_certificate_validation_enabled
		end

feature -- Access

	exchange_count: INTEGER

feature -- Basic operations

	send (a_method, a_url: READABLE_STRING_8; a_headers: HASH_TABLE [STRING_8, STRING_8]; a_body: detachable READABLE_STRING_8;
			a_timeout_seconds: INTEGER): HTTP_REPLY
			-- One exchange through SIMPLE_WINHTTP, waiting up to `a_timeout_seconds'
			-- for the answer (the connect allowance is capped by it too, so a short
			-- health probe stays short). What the library cannot send verbatim is
			-- refused as a failed reply before anything goes out.
		local
			l_response: SIMPLE_WINHTTP_RESPONSE
			l_error: STRING_32
		do
			exchange_count := exchange_count + 1
			if not http.is_ascii_url (a_url) then
				create Result.make_failed ({STRING_32} "Not a wire-clean URL (printable ASCII, no blanks): nothing was sent")
			elseif not http.is_header_table_clean (a_headers) then
				create Result.make_failed ({STRING_32} "A request header is not wire-clean (printable ASCII, no CR or LF): nothing was sent")
			else
				http.set_connect_timeout_seconds (a_timeout_seconds.min (Connect_timeout_maximum_seconds))
				l_response := http.send (a_method, a_url, a_headers, a_body, a_timeout_seconds)
				if not l_response.is_exchanged then
					create Result.make_failed (l_response.error)
				elseif l_response.status < 200 then
						-- A 1xx is an interim status: HTTP_REPLY's contract admits only
						-- 200..599 as an answer, and a peer that stops there has not answered.
					l_error := {STRING_32} "HTTP "
					l_error.append_string_general (l_response.status.out)
					l_error.append_string_general (" is an interim status, not an answer")
					create Result.make_failed (l_error)
				else
					create Result.make (l_response.status, l_response.body)
				end
			end
		end

feature -- Constants

	Connect_timeout_maximum_seconds: INTEGER = 10
			-- Resolve + connect never gets more than this, nor more than the call's own timeout.

feature {NONE} -- Implementation

	http: SIMPLE_WINHTTP
			-- The one WinHTTP client. It keeps no handles between calls (the whole
			-- Win32 handle lifecycle lives inside each exchange), so one instance
			-- per transport - and one transport per processor - is safe.

invariant
	http_bounded: http.body_maximum = Body_maximum

end
