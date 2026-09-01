note
	description: "[
		A one-shot delayed poster on its own processor, for the doorbell
		assault: it sleeps `delay_milliseconds', posts one message through
		its OWN reference to the separate CHAT_API, and goes idle - the
		same shape as POLL_ALARM (a separate object created with what it
		needs, given one asynchronous command). The API is an attribute
		here and is touched only inside `post_through', which takes it as
		a separate argument; the token and the body are copied onto this
		processor at creation, so nothing of the creator's processor is
		ever held while sleeping.
	]"
	author: "Larry Rix"

class
	DOORBELL_POSTER

create
	make

feature {NONE} -- Initialization

	make (a_api: separate CHAT_API; a_token: separate READABLE_STRING_8; a_room_id: INTEGER_64; a_body: separate READABLE_STRING_32; a_delay_milliseconds: INTEGER)
			-- A poster over `a_api' that will post `a_body' as `a_token' in
			-- `a_room_id' after `a_delay_milliseconds'.
		require
			positive_room: a_room_id > 0
			non_negative_delay: a_delay_milliseconds >= 0
		do
			api := a_api
			create token.make_from_separate (a_token)
			room_id := a_room_id
			create body.make_from_separate (a_body)
			delay_milliseconds := a_delay_milliseconds
		ensure
			kept: api = a_api and room_id = a_room_id and delay_milliseconds = a_delay_milliseconds
			copied: token.count = a_token.count and body.count = a_body.count
			not_run: not has_run and last_status = 0
		end

feature -- Access

	last_status: INTEGER
			-- The HTTP status the one post answered; 0 before `run'.

feature -- Status report

	has_run: BOOLEAN
			-- Has the one shot been fired?

feature -- Basic operations

	run
			-- One-shot: sleep `delay_milliseconds', post, and stop.
		require
			once_only: not has_run
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			if delay_milliseconds > 0 then
				create l_env
				l_env.sleep (delay_milliseconds.to_integer_64 * 1_000_000)
			end
			last_status := post_through (api)
			has_run := True
		ensure
			ran: has_run
			answered: last_status >= 200 and last_status <= 599
		end

feature {NONE} -- Implementation

	api: separate CHAT_API
			-- This poster's own reference to the API's processor.

	token: STRING_8

	room_id: INTEGER_64

	body: STRING_32

	delay_milliseconds: INTEGER

	post_through (a_api: separate CHAT_API): INTEGER
			-- Post `body' as `token' in `room_id'; the reply's status.
		do
			Result := status_of (a_api.post_message (token, room_id, body))
		end

	status_of (a_reply: separate CHAT_REPLY): INTEGER
		do
			Result := a_reply.status
		end

invariant
	positive_room: room_id > 0
	non_negative_delay: delay_milliseconds >= 0
	status_zero_until_run: (not has_run) implies last_status = 0

end
