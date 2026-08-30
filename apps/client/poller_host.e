note
	description: "[
		The poller's processor: creates, on itself, the WINHTTP_TRANSPORT,
		CHAT_ENDPOINT and CHAT_CLIENT the EVENT_POLLER will use, so that
		nothing the poller blocks on is shared with the GUI (approach
		section 8). Receives the session from the root's client through
		CHAT_CLIENT.hand_session_to (the token is copied, never read
		back), the inbox through `set_inbox' (one short call), and then
		`poll' runs the loop here until the inbox is stopped or the
		session is lost.
	]"
	author: "Larry Rix"

class
	POLLER_HOST

create
	make

feature {NONE} -- Initialization

	make (a_base_url: separate READABLE_STRING_8)
			-- A transport, endpoint and client of this processor's own, for `a_base_url'
			-- (the base URL of an existing CHAT_ENDPOINT, so it is acceptable).
		local
			l_url: STRING_8
		do
			create l_url.make_from_separate (a_base_url)
			check acceptable: (create {CHAT_URL_RULES}).is_acceptable_url (l_url) end
			create transport.make
			create endpoint.make (l_url)
			create client.make (transport, endpoint)
		ensure
			logged_out: not client.is_logged_in
			no_inbox: inbox = Void
		end

feature -- Access

	client: CHAT_CLIENT
			-- This processor's client; the root copies its session in with CHAT_CLIENT.hand_session_to.

	poller: detachable EVENT_POLLER
			-- The loop's machine once `poll' has started.

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

	poll (a_room_id, a_since_id: INTEGER_64)
			-- The loop, on this processor, until the inbox is stopped or the session is lost.
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
		ensure
			ran: attached poller
		end

feature {NONE} -- Implementation

	transport: WINHTTP_TRANSPORT
	endpoint: CHAT_ENDPOINT

	inbox: detachable separate EVENT_INBOX

end
