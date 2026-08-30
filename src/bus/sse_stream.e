note
	description: "[
		One client's live stream in Server-Sent Events form, driven by the
		request's handler on the request's processor: the handler waits on
		a POLL_WAITER (POLL_WAIT), pulls the page after `last_delivered_id'
		from the API, and hands it to `deliver'; on a timeout it calls
		`heartbeat'. This class only formats and keeps the cursor - it is
		an EVENT_SOURCE, never a subscriber, and never does I/O on anyone
		else's processor.

		Wire form per event: "id: <id>\nevent: message\ndata: <json>\n\n";
		statuses "event: status\ndata: <json>\n\n"; heartbeats ": hb\n\n".
	]"
	author: "Larry Rix"

class
	SSE_STREAM

inherit
	EVENT_SOURCE

create
	make

feature {NONE} -- Initialization

	make (a_sink: STREAM_SINK)
		require
			sink_open: a_sink.is_open
		do
			sink := a_sink
			create delivered.make (16)
			create codec.make
			heartbeat_seconds := Default_heartbeat_seconds
		ensure
			not_open: not is_open
			nothing_delivered: delivered_model.is_empty
		end

feature -- Model Queries (for MML postconditions)

	delivered_model: MML_SEQUENCE [INTEGER_64]
		do
			create Result
			across delivered as ic loop
				Result := Result & ic
			end
		ensure then
			same_count: Result.count = delivered.count
		end

feature -- Access

	heartbeat_seconds: INTEGER

	bytes_written: INTEGER_64
		do
			Result := sink.bytes_written
		end

feature -- Status report

	is_open: BOOLEAN
		do
			Result := is_opened and sink.is_open
		end

feature -- Basic operations

	open (a_room_id, a_since_id: INTEGER_64)
		do
			room_id := a_room_id
			since_id := a_since_id
			last_delivered_id := a_since_id
			is_opened := True
			sink.write (Preamble)
		ensure then
			preamble_written: sink.bytes_written = old sink.bytes_written + Preamble.count
		end

	close
		do
			is_opened := False
			if sink.is_open then
				sink.close
			end
		ensure then
			sink_closed: not sink.is_open
		end

	deliver (a_page: CHAT_PAGE)
		do
			across a_page.events as e loop
				sink.write (format_event (e))
				delivered.extend (e.id)
				last_delivered_id := e.id
			end
			across a_page.statuses as s loop
				sink.write (format_status (s))
			end
			sink.flush
		end

	heartbeat
			-- A comment line, so the connection is seen to be alive.
		require
			open: is_open
		do
			sink.write (Heartbeat_line)
			sink.flush
		ensure
			written: sink.bytes_written = old sink.bytes_written + Heartbeat_line.count
			nothing_delivered: delivered_model |=| old delivered_model
		end

feature -- Conversion (contract support)

	format_event (a_event: CHAT_EVENT): STRING_8
			-- The SSE record for `a_event'.
		do
			Result := "id: " + a_event.id.out + "%Nevent: message%Ndata: " + codec.bytes_of (a_event.to_json) + "%N%N"
		ensure
			terminated: Result.ends_with ("%N%N")
			carries_id: Result.starts_with ("id: " + a_event.id.out + "%N")
			one_record: not Result.substring (1, Result.count - 2).has_substring ("%N%N")
		end

	format_status (a_status: CHAT_STATUS): STRING_8
		do
			Result := "event: status%Ndata: " + codec.bytes_of (codec.status_to_json (a_status)) + "%N%N"
		ensure
			terminated: Result.ends_with ("%N%N")
			is_status: Result.starts_with ("event: status%N")
			one_record: not Result.substring (1, Result.count - 2).has_substring ("%N%N")
		end

feature -- Constants

	Default_heartbeat_seconds: INTEGER = 20

	Preamble: STRING_8 = ": simple_chat stream%N%N"

	Heartbeat_line: STRING_8 = ": hb%N%N"

feature {NONE} -- Implementation

	sink: STREAM_SINK
	codec: CHAT_JSON
	delivered: ARRAYED_LIST [INTEGER_64]
	is_opened: BOOLEAN

invariant
	heartbeat_positive: heartbeat_seconds > 0
	model_consistent: delivered_model.count = delivered.count

end
