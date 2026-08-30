note
	description: "[
		The room member that turns an addressed message into a participant's
		reply: on each wake it pulls the events it has not seen (its own
		cursor into the store - the doorbell pattern), parses each for an
		address, applies that participant's rate limit for the asker,
		publishes an ephemeral status, asks, and posts the answer as the
		participant's bot user - or a refusal, or an apology. Bot-authored
		events are never dispatched (no echo loops). One request at a time
		per participant, queued in order (intent-v2 Q8).
	]"
	author: "Larry Rix"

class
	PARTICIPANT_DISPATCHER

inherit
	EVENT_SUBSCRIBER

create
	make

feature {NONE} -- Initialization

	make (a_service: CHAT_SERVICE; a_registry: PARTICIPANT_REGISTRY; a_limits: RATE_LIMITER; a_parser: ADDRESS_PARSER; a_log: CHAT_LOG)
		do
			service := a_service
			registry := a_registry
			limits := a_limits
			parser := a_parser
			log := a_log
			subscriber_name := "dispatcher"
		ensure
			set: service = a_service and registry = a_registry and limits = a_limits and parser = a_parser
			fresh: cursor = 0 and requests_seen = 0 and answers_posted = 0
		end

feature -- Access

	subscriber_name: STRING_8
	wake_count: INTEGER

	cursor: INTEGER_64
			-- The last event id examined.

	requests_seen: INTEGER
			-- Addressed, non-bot events examined so far.

	answers_posted: INTEGER
			-- Replies, refusals and apologies posted so far.

feature -- Basic operations

	wake (a_room_id: INTEGER_64)
		do
			wake_count := wake_count + 1
			-- Implementation in Phase 4: for each event after `cursor' in the room: handle_event
		ensure then
			cursor_never_backwards: cursor >= old cursor
		end

	receive_status (a_status: separate CHAT_STATUS)
			-- Statuses are not requests.
		do
		end

	handle_event (a_event: CHAT_EVENT)
			-- Dispatch one event if it addresses a registered participant.
		require
			unseen: a_event.id > cursor
		do
			cursor := a_event.id
			-- Implementation in Phase 4
		ensure
			advanced: cursor = a_event.id
			ignores_bots: a_event.is_bot_authored implies requests_seen = old requests_seen
			ignores_unaddressed: not parser.is_addressed (a_event.body) implies requests_seen = old requests_seen
			counts_requests: (parser.is_addressed (a_event.body) and not a_event.is_bot_authored) implies requests_seen = old requests_seen + 1
			always_answers: (parser.is_addressed (a_event.body) and not a_event.is_bot_authored) implies answers_posted = old answers_posted + 1
		end

feature {NONE} -- Implementation

	service: CHAT_SERVICE
	registry: PARTICIPANT_REGISTRY
	limits: RATE_LIMITER
	parser: ADDRESS_PARSER
	log: CHAT_LOG

invariant
	cursor_non_negative: cursor >= 0
	counts_non_negative: requests_seen >= 0 and answers_posted >= 0
	answers_cover_requests: answers_posted <= requests_seen

end
