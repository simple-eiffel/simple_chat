note
	description: "[
		The long-poll's half of the doorbell under SCOOP (D1): a flag
		object on its own processor. The bus wakes it (asynchronously) when
		its room has news; a POLL_ALARM times it out; the request's handler
		waits on `is_ready' as a SCOOP wait condition (POLL_WAIT). Because
		one processor owns it, `wake' and `time_out' cannot interleave and
		every postcondition here is exact.

		A wake that lands before the handler starts waiting is not lost: it
		is a count, not a signal. Statuses seen meanwhile are kept as JSON
		text so the handler can copy them across with one string copy.
	]"
	author: "Larry Rix"

class
	POLL_WAITER

inherit
	EVENT_SUBSCRIBER

create
	make

feature {NONE} -- Initialization

	make (a_room_id: INTEGER_64)
			-- A waiter for `a_room_id'.
		require
			positive_room: a_room_id > 0
		do
			room_id := a_room_id
			create statuses.make (2)
			create codec.make
			subscriber_name := "poll"
		ensure
			room_set: room_id = a_room_id
			quiet: not has_news and not is_timed_out and wake_count = 0
			no_statuses: status_count = 0
		end

feature -- Access

	room_id: INTEGER_64
			-- The room being waited on.

	subscriber_name: STRING_8

	wake_count: INTEGER

	news_count: INTEGER
			-- Wakes for `room_id' so far.

	status_count: INTEGER
		do
			Result := statuses.count
		end

	statuses_json: STRING_8
			-- The statuses kept so far, as a JSON array (for the page).
		do
			Result := codec.bytes_of_array (codec.statuses_to_json (statuses))
		ensure
			array: Result.starts_with ("[") and Result.ends_with ("]")
		end

feature -- Status report

	has_news: BOOLEAN
		do
			Result := news_count > 0
		ensure
			definition: Result = (news_count > 0)
		end

	is_timed_out: BOOLEAN

	is_ready: BOOLEAN
			-- The handler may stop waiting.
		do
			Result := has_news or is_timed_out
		ensure
			definition: Result = (has_news or is_timed_out)
		end

feature -- Basic operations

	wake (a_room_id: INTEGER_64)
		do
			wake_count := wake_count + 1
			if a_room_id = room_id then
				news_count := news_count + 1
			end
		ensure then
			mine_counted: a_room_id = room_id implies news_count = old news_count + 1
			others_ignored: a_room_id /= room_id implies news_count = old news_count
		end

	receive_status (a_status: separate CHAT_STATUS)
		do
			if a_status.room_id = room_id then
				statuses.extend (create {CHAT_STATUS}.make_from_separate (a_status))
			end
		ensure then
			kept_when_mine: a_status.room_id = room_id implies status_count = old status_count + 1
			dropped_otherwise: a_status.room_id /= room_id implies status_count = old status_count
		end

	time_out
			-- The alarm went off.
		do
			is_timed_out := True
		ensure
			timed_out: is_timed_out
			news_unchanged: news_count = old news_count
		end

feature {NONE} -- Implementation

	statuses: ARRAYED_LIST [CHAT_STATUS]

	codec: CHAT_JSON

invariant
	positive_room: room_id > 0
	named: not subscriber_name.is_empty
	counts_non_negative: wake_count >= 0 and news_count >= 0
	news_within_wakes: news_count <= wake_count

end
