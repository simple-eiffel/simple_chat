note
	description: "[
		The summary's processor. Builds its own WINHTTP_TRANSPORT,
		CHAT_ENDPOINT and CHAT_CLIENT, exactly as POLLER_HOST does, so
		that nothing the summary waits on is shared with the GUI: the
		engine call behind `POST /rooms/{id}/summary' is a `claude -p'
		run and takes seconds.

		The window never waits for it. `fetch' is launched as an
		asynchronous command with nothing but scalars in it, so the call
		returns to the GUI at once; the answer is left in a SUMMARY_SLOT,
		which never blocks, and the 250 ms tick collects it. That is the
		same choreography the poller already uses, and for the same
		reason: a GUI thread that stops pumping for five seconds is
		ghosted by Windows and its keystrokes are thrown away.
	]"
	author: "Larry Rix"

class
	SUMMARY_HOST

create
	make

feature {NONE} -- Initialization

	make (a_base_url: separate READABLE_STRING_8)
			-- A transport, endpoint and client of this processor's own.
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
			no_slot: slot = Void
		end

feature -- Access

	client: CHAT_CLIENT
			-- This processor's client; the root copies its session in with CHAT_CLIENT.hand_session_to.

feature -- Status report

	has_slot: BOOLEAN
		do
			Result := slot /= Void
		end

feature -- Basic operations

	set_slot (a_slot: separate SUMMARY_SLOT)
			-- Where the answer goes (one short call).
		do
			slot := a_slot
		ensure
			set: slot = a_slot
		end

	fetch (a_room_id, a_since_id, a_until_id: INTEGER_64; a_minutes: INTEGER)
			-- Ask the server for the summary, here, and leave the outcome in
			-- the slot. Every argument is a scalar, so the GUI's call to this
			-- is asynchronous and returns before the engine has begun.
		require
			logged_in: client.is_logged_in
			has_slot: has_slot
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
			until_non_negative: a_until_id >= 0
			minutes_non_negative: a_minutes >= 0
		local
			l_result: CHAT_RESULT [STRING_32]
			l_failed: BOOLEAN
		do
			if attached slot as s then
				if l_failed then
					put_failure (s, Message_unreachable)
				else
					l_result := client.summarise (a_room_id, a_since_id, a_until_id, a_minutes)
					if l_result.is_success and then attached l_result.value as t and then not t.is_empty then
						put_text (s, t)
					elseif attached l_result.error as e and then not e.message.is_empty then
						put_failure (s, e.message)
					else
						put_failure (s, Message_unreachable)
					end
				end
			end
		rescue
				-- One retry only: a summary that breaks must leave the window a
				-- sentence, never a slot that waits for ever.
			if not l_failed then
				l_failed := True
				retry
			end
		end

feature {NONE} -- Implementation

	transport: WINHTTP_TRANSPORT
	endpoint: CHAT_ENDPOINT

	slot: detachable separate SUMMARY_SLOT

	put_text (a_slot: separate SUMMARY_SLOT; a_text: READABLE_STRING_32)
		require
			given: not a_text.is_empty
		do
			a_slot.put_text (a_text)
		end

	put_failure (a_slot: separate SUMMARY_SLOT; a_message: READABLE_STRING_32)
		require
			given: not a_message.is_empty
		do
			a_slot.put_failure (a_message)
		end

feature -- Constants

	Message_unreachable: STRING_32 = "No summary just now - the assistant could not be reached."

end
