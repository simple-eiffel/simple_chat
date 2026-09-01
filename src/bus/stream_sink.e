note
	description: "[
		Where a live stream writes: bytes out to one client. The web layer
		adapts simple_web's response to this; the tests use a memory sink.
		Keeping the transport behind this contract is what keeps every
		EWF type out of simple_chat.

		Byte counting under real sockets (M-A): `bytes_written' counts the
		bytes ACCEPTED while the sink was open, not bytes a client verifiably
		received - no HTTP server can promise the latter. A sink over a
		transport that reports a failed write may close itself during `write';
		the count then stops with it. Hence `counted_when_open', not an
		unconditional count.
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
			-- Send `a_text' to the client. A sink that learns mid-write that
			-- the client is gone closes itself instead of raising; the bytes
			-- of a failed write are not counted (M-A).
		require
			open: is_open
		deferred
		ensure
			counted_when_open: is_open implies bytes_written = old bytes_written + a_text.count
			closed_stays_closed: not old is_open implies not is_open
			never_uncounts: bytes_written >= old bytes_written
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
