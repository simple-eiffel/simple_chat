note
	description: "[
		STREAM_SINK over simple_web's response: the one place the SSE
		stream meets the transport. `write' rides send_chunk (write +
		flush); a connector that reports a dead client flips the
		response's is_streaming, and this sink closes with it - the M-A
		reading: bytes_written counts bytes accepted while open. EWF's
		standalone connector never reports a dead client, so there the
		sink stays open and the handler bounds the stream's lifetime.
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
			-- A sink over `a_response', whose stream head is already sent.
		require
			streaming: a_response.is_streaming
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
			-- Hand `a_text' to the response (written and flushed at once);
			-- close with the response when the connector reports the client gone.
		do
			response.send_chunk (a_text)
			if response.is_streaming then
				bytes_written := bytes_written + a_text.count
			else
				is_open := False
			end
		end

	flush
			-- Nothing buffered here: every `write' already flushed (send_chunk).
		do
		end

	close
			-- The stream is over; the connection closes when the handler returns
			-- (Connection: close - simple_web's streaming head has no trailer).
		do
			is_open := False
		end

feature {NONE} -- Implementation

	response: SIMPLE_WEB_SERVER_RESPONSE

invariant
	closed_when_response_hung_up: is_open implies response.is_streaming

end
