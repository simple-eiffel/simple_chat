note
	description: "[
		STREAM_SINK over simple_web's response: the one place the SSE
		stream meets the transport. Phase 4 uses simple_web's streaming
		(chunked) response support - the addition Spike A lands there -
		so no EWF type is named here.
	]"
	author: "Larry Rix"

class
	WEB_STREAM_SINK

inherit
	STREAM_SINK

create
	make

feature {NONE} -- Initialization

	make (a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			response := a_response
			is_open := True
		ensure
			open: is_open
			nothing_yet: bytes_written = 0
		end

feature -- Status report

	is_open: BOOLEAN

feature -- Access

	bytes_written: INTEGER_64

feature -- Basic operations

	write (a_text: READABLE_STRING_8)
		do
			bytes_written := bytes_written + a_text.count
			-- Implementation in Phase 4: response streaming write
		end

	flush
		do
			-- Implementation in Phase 4
		end

	close
		do
			is_open := False
			-- Implementation in Phase 4
		end

feature {NONE} -- Implementation

	response: SIMPLE_WEB_SERVER_RESPONSE

end
