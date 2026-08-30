note
	description: "[
		Where a live stream writes: bytes out to one client. The web layer
		adapts simple_web's response to this; the tests use a memory sink.
		Keeping the transport behind this contract is what keeps every
		EWF type out of simple_chat.
	]"
	author: "Larry Rix"

deferred class
	STREAM_SINK

feature -- Status report

	is_open: BOOLEAN
		deferred
		end

feature -- Access

	bytes_written: INTEGER_64
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Basic operations

	write (a_text: READABLE_STRING_8)
			-- Send `a_text' to the client.
		require
			open: is_open
		deferred
		ensure
			counted: bytes_written = old bytes_written + a_text.count
		end

	flush
			-- Push buffered bytes to the wire now.
		require
			open: is_open
		deferred
		end

	close
		deferred
		ensure
			closed: not is_open
		end

end
