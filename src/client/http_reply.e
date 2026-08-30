note
	description: "[
		What a transport brings back: an HTTP status and body when the
		exchange happened, or a transport error (no connection, timeout)
		when it did not. `status' = 0 exactly when the transport failed.
		A final status is 200..599 - a 1xx is never an answer - and the
		body never exceeds HTTP_TRANSPORT.Body_maximum.
	]"
	author: "Larry Rix"

class
	HTTP_REPLY

create
	make,
	make_failed

feature {NONE} -- Initialization

	make (a_status: INTEGER; a_body: READABLE_STRING_8)
			-- An answer from the server.
		require
			final_status: a_status >= 200 and a_status <= 599
			bounded: a_body.count <= {HTTP_TRANSPORT}.Body_maximum
		do
			status := a_status
			body := a_body.to_string_8
			create error.make_empty
		ensure
			set: status = a_status and body.same_string (a_body)
			exchanged: is_exchanged
		end

	make_failed (a_error: READABLE_STRING_GENERAL)
			-- No exchange: `a_error' says why.
		require
			explained: not a_error.is_empty
		do
			create body.make_empty
			error := a_error.to_string_32
		ensure
			failed: not is_exchanged
			explained: error.same_string_general (a_error)
			no_body: body.is_empty
		end

feature -- Access

	status: INTEGER
			-- HTTP status; 0 when the transport failed.

	body: STRING_8
			-- Raw body bytes (UTF-8 for JSON).

	error: STRING_32
			-- Transport failure reason; empty when `is_exchanged'.

feature -- Status report

	is_exchanged: BOOLEAN
			-- Did a request reach the server and an answer come back?
		do
			Result := status > 0
		ensure
			definition: Result = (status > 0)
		end

	is_success: BOOLEAN
			-- 2xx?
		do
			Result := status >= 200 and status <= 299
		ensure
			definition: Result = (status >= 200 and status <= 299)
		end

invariant
	failed_is_explained: (status = 0) = not error.is_empty
	status_range: status = 0 or (status >= 200 and status <= 599)
	bounded: body.count <= {HTTP_TRANSPORT}.Body_maximum

end
