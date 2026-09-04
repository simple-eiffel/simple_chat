note
	description: "[
		POLLER_HOST's shape over a scripted transport: a transport,
		endpoint and CHAT_CLIENT of this processor's own, a session taken
		through a scripted login, an inbox handed in by one short call,
		and then the REAL EVENT_POLLER's REAL `run' loop on this
		processor. Only the wire is a double; every law under assault -
		how long one exchange keeps this processor inside C, and what
		that costs the root - is the shipped one.
	]"
	author: "Larry Rix"

class
	SLOW_POLL_HOST

create
	make

feature {NONE} -- Initialization

	make (a_cap_seconds: INTEGER)
			-- A logged-in client of this processor's own over a transport that waits
			-- for as long as the poller asks, capped at `a_cap_seconds'.
		require
			positive: a_cap_seconds > 0
		local
			l_result: CHAT_RESULT [CHAT_MEMBER]
		do
			create transport.make (a_cap_seconds)
			create endpoint.make (Loopback_url)
			create client.make (transport, endpoint)
			l_result := client.login ("larry", {STRING_32} "correct horse battery staple")
			check logged_in: client.is_logged_in end
		ensure
			logged_in: client.is_logged_in
			no_inbox: inbox = Void
		end

feature -- Access

	client: CHAT_CLIENT

	poller: detachable EVENT_POLLER
			-- The loop's machine once `poll' has started.

	exchanges: INTEGER
			-- Exchanges the scripted transport has made.
		do
			Result := transport.exchange_count
		end

	longest_wait_ms: INTEGER
			-- The longest single wait this processor has spent inside C.
		do
			Result := transport.longest_wait_ms
		end

feature -- Status report

	has_inbox: BOOLEAN
		do
			Result := inbox /= Void
		end

feature -- Basic operations

	set_inbox (a_inbox: separate EVENT_INBOX)
			-- Where pages go and where the stop signal comes from.
		do
			inbox := a_inbox
		ensure
			set: inbox = a_inbox
		end

	set_done_flag (a_flag: separate POLL_DONE_FLAG)
			-- The flag to raise when `poll' returns, so an assault can watch
			-- for the end of the loop without joining this processor.
		do
			done_flag := a_flag
		ensure
			set: done_flag = a_flag
		end

	poll (a_room_id, a_since_id: INTEGER_64)
			-- The REAL loop, on this processor, until the inbox is stopped.
		require
			logged_in: client.is_logged_in
			has_inbox: has_inbox
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
		local
			l_poller: EVENT_POLLER
		do
			if attached inbox as b then
				create l_poller.make (client, a_room_id, a_since_id, b)
				poller := l_poller
				l_poller.run
			end
			if attached done_flag as f then
				raise (f)
			end
		ensure
			ran: attached poller
		end

feature {NONE} -- The flag's processor (one short, separate call)

	raise (a_flag: separate POLL_DONE_FLAG)
			-- Say the loop has returned.
		do
			a_flag.note_done
		end

feature -- Constants

	Loopback_url: STRING_8 = "http://127.0.0.1:8080"

feature {NONE} -- Implementation

	transport: SLOW_HTTP_TRANSPORT
	endpoint: CHAT_ENDPOINT

	inbox: detachable separate EVENT_INBOX

	done_flag: detachable separate POLL_DONE_FLAG
			-- Raised when `poll' returns; Void when nobody is watching.

end
