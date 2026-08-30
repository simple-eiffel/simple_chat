note
	description: "[
		One client's live stream in Server-Sent Events form: replays
		everything after `since_id' from the store, then, on each `wake' for
		its room, pulls and writes what is new; heartbeats keep proxies and
		browsers from closing an idle connection. It is both an EVENT_SOURCE
		(to its client) and an EVENT_SUBSCRIBER (to the bus).

		Wire form per event: "id: <id>\nevent: message\ndata: <json>\n\n";
		statuses as "event: status\ndata: <json>\n\n"; heartbeats ": hb\n\n".
	]"
	author: "Larry Rix"

class
	SSE_STREAM

inherit
	EVENT_SOURCE
	EVENT_SUBSCRIBER

create
	make

feature {NONE} -- Initialization

	make (a_sink: STREAM_SINK; a_store: CHAT_STORE; a_page_size: INTEGER)
		require
			sink_open: a_sink.is_open
			store_open: a_store.is_open
			page_positive: a_page_size > 0
		do
			sink := a_sink
			store := a_store
			page_size := a_page_size
			heartbeat_seconds := Default_heartbeat_seconds
			subscriber_name := "sse"
		ensure
			not_open: not is_open
			page_set: page_size = a_page_size
		end

feature -- Access

	subscriber_name: STRING_8
	wake_count: INTEGER
	heartbeat_seconds: INTEGER
	page_size: INTEGER

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
			-- Implementation in Phase 4: write the SSE preamble, replay via deliver_pending
		end

	close
		do
			is_opened := False
			-- Implementation in Phase 4: sink.close
		end

	deliver_pending
			-- Pull events after `last_delivered_id' in pages and write them.
		do
			-- Implementation in Phase 4
		ensure then
			caught_up_or_closed: last_delivered_id >= store.last_event_id or else not is_open
		end

	wake (a_room_id: INTEGER_64)
		do
			wake_count := wake_count + 1
			-- Implementation in Phase 4: if a_room_id = room_id and is_open then deliver_pending end
		ensure then
			other_rooms_ignored: a_room_id /= room_id implies last_delivered_id = old last_delivered_id
		end

	receive_status (a_status: CHAT_STATUS)
		do
			-- Implementation in Phase 4: if a_status.room_id = room_id then write format_status end
		end

	heartbeat
			-- A comment line, so the connection is seen to be alive.
		require
			open: is_open
		do
			-- Implementation in Phase 4: sink.write (": hb%N%N"); sink.flush
		ensure
			written: sink.bytes_written > old sink.bytes_written
		end

feature -- Conversion (contract support)

	format_event (a_event: CHAT_EVENT): STRING_8
			-- The SSE record for `a_event'.
		do
			create Result.make (64)
			-- Implementation in Phase 4
		ensure
			terminated: Result.ends_with ("%N%N")
			carries_id: Result.starts_with ("id: " + a_event.id.out)
		end

	format_status (a_status: CHAT_STATUS): STRING_8
		do
			create Result.make (64)
			-- Implementation in Phase 4
		ensure
			terminated: Result.ends_with ("%N%N")
			is_status: Result.starts_with ("event: status")
		end

feature -- Constants

	Default_heartbeat_seconds: INTEGER = 20

feature {NONE} -- Implementation

	sink: STREAM_SINK
	store: CHAT_STORE
	is_opened: BOOLEAN

invariant
	heartbeat_positive: heartbeat_seconds > 0
	page_positive: page_size > 0
	named: not subscriber_name.is_empty

end
