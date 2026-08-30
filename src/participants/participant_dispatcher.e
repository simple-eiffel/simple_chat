note
	description: "[
		The room member that turns an addressed message into a participant's
		reply. It lives on its own processor (D1, approach section 8): the
		bus wakes it with an asynchronous `wake', which only notes the room;
		`dispatch_pending' - called by the dispatcher's driver, whose SCOOP
		wait condition is `has_pending' - drains the noted rooms one at a
		time: it pulls the page after that room's cursor from the API as
		bytes, decodes a copy here (CHAT_JSON), and hands each event to
		`handle_event'. Nothing of the API's processor is ever held: `api'
		is touched only inside routines that take it as a separate
		argument, only bytes and scalars cross, and every reply goes back
		through `dispatcher_post'. Phase 4 builds the registry, parser and
		log on this processor.

		`handle_event' is idempotent (`answered_model' remembers every
		request taken), so a page delivered twice, a restart from
		`start_after' (the store's last id, Issue 16) or a hand-fed event
		can never answer twice (Issue 9). A request is asked of its
		participant only when the bot can post in that room
		(`only_member_rooms') and the asker's rate limit allows it
		(`rate_limited_not_asked', `asked_once', `limit_recorded' - Issue
		15); refusals and apologies are posted as answers; a post the
		service refuses is an `answer_failure'. One request at a time per
		participant, in order, behind a bounded FIFO (`Max_queue_depth').
		Bot-authored, system and image events are never requests (no echo
		loops).
	]"
	author: "Larry Rix"

class
	PARTICIPANT_DISPATCHER

inherit
	EVENT_SUBSCRIBER

create
	make

feature {NONE} -- Initialization

	make (a_api: separate CHAT_API; a_parser: ADDRESS_PARSER; a_log: CHAT_LOG; a_start_after: INTEGER_64)
			-- A dispatcher over `a_api' that never looks at events up to `a_start_after'
			-- (the store's last id at start: `dispatcher_start_after').
		require
			start_non_negative: a_start_after >= 0
		do
			api := a_api
			parser := a_parser
			log := a_log
			start_after := a_start_after
			subscriber_name := "dispatcher"
			create pending_rooms.make (4)
			create cursors.make (4)
			create answered.make (64)
			create queue_depths.make (4)
			queue_depths.compare_objects
			create codec.make
			create last_ask_key.make_empty
		ensure
			set: parser = a_parser and log = a_log
			starts_where_told: start_after = a_start_after
			fresh: wake_count = 0 and requests_seen = 0 and answers_posted = 0 and answer_failures = 0 and asks = 0
			nothing_pending: pending_rooms_model.is_empty
			no_cursors: cursors_model.is_empty
			nothing_answered: answered_model.is_empty
		end

feature -- Model Queries (for MML postconditions)

	pending_rooms_model: MML_SET [INTEGER_64]
			-- The rooms noted by `wake' and not yet drained.
		do
			create Result
			across pending_rooms as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = pending_rooms.count
		end

	cursors_model: MML_MAP [INTEGER_64, INTEGER_64]
			-- Room id -> the last event id examined there, for every room ever pulled.
		do
			create Result
			across cursors as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = cursors.count
		end

	answered_model: MML_SET [INTEGER_64]
			-- The ids of every request taken so far - each exactly once.
		do
			create Result
			across answered as ic loop
				Result := Result & @ic.key
			end
		ensure
			same_count: Result.count = answered.count
		end

feature -- Access

	subscriber_name: STRING_8

	wake_count: INTEGER

	start_after: INTEGER_64
			-- The event id this dispatcher began after; nothing at or below it is ever taken.

	registry: PARTICIPANT_REGISTRY
			-- The participants, through the parser.
		do
			Result := parser.registry
		end

	requests_seen: INTEGER
			-- Requests taken: human-written messages addressed to a registered participant, each once.

	answers_posted: INTEGER
			-- Replies, refusals and apologies the room accepted.

	answer_failures: INTEGER
			-- Requests whose answer could not be posted: the bot cannot post there, or the service refused.

	asks: INTEGER
			-- Engine calls made: one per request the room could take and the limiter allowed.

	last_ask_granted: BOOLEAN
			-- Did the limiter allow the latest request that reached it? False when the latest request never reached it.

	last_ask_key: STRING_8
			-- The limiter key the latest ask was charged to; empty before any.

	last_can_post: BOOLEAN
			-- Could the latest request's participant post in that room?

	last_post_status: INTEGER
			-- The status of the latest post; 0 before any.

	last_page_count: INTEGER
			-- How many events the latest page decoded to; 0 for an undecodable one.

	cursor_of (a_room_id: INTEGER_64): INTEGER_64
			-- The last event id examined in `a_room_id'; `start_after' before any pull.
		do
			if cursors.has (a_room_id) then
				Result := cursors.item (a_room_id)
			else
				Result := start_after
			end
		ensure
			at_least_start: Result >= start_after
			from_model: cursors_model.domain.has (a_room_id) implies Result = cursors_model [a_room_id]
			start_when_unknown: not cursors_model.domain.has (a_room_id) implies Result = start_after
		end

	pending_count: INTEGER
		do
			Result := pending_rooms.count
		ensure
			definition: Result = pending_rooms_model.count
		end

	queue_depth_of (a_participant: PARTICIPANT): INTEGER
			-- Requests accepted for `a_participant' and not yet answered.
		do
			if queue_depths.has (a_participant.handle) then
				Result := queue_depths.item (a_participant.handle)
			end
		ensure
			non_negative: Result >= 0
			bounded: Result <= Max_queue_depth
		end

	target_of (a_event: CHAT_EVENT): detachable PARTICIPANT
			-- The participant `a_event' asks something of: a human-written message
			-- addressed to a registered handle with a request after it; Void for everything else.
		do
			if a_event.is_message and not a_event.is_bot_authored and then attached parser.parse (a_event.body) as r then
				Result := registry.find (r.handle)
			end
		ensure
			never_bots: a_event.is_bot_authored implies Result = Void
			only_messages: not a_event.is_message implies Result = Void
			only_addressed: not parser.is_addressed (a_event.body) implies Result = Void
			registered: attached Result as p implies registry.has (p.handle)
		end

	target_calls (a_event: CHAT_EVENT): INTEGER
			-- `calls' of `target_of (a_event)', or 0 (contract support).
		do
			if attached target_of (a_event) as p then
				Result := p.calls
			end
		end

	target_queue_depth (a_event: CHAT_EVENT): INTEGER
			-- `queue_depth_of (target_of (a_event))', or 0 (contract support).
		do
			if attached target_of (a_event) as p then
				Result := queue_depth_of (p)
			end
		end

feature -- Status report

	has_pending: BOOLEAN
			-- Is any room waiting to be drained? (The driver's wait condition.)
		do
			Result := not pending_rooms.is_empty
		ensure
			definition: Result = not pending_rooms_model.is_empty
		end

	is_pending (a_room_id: INTEGER_64): BOOLEAN
		do
			Result := pending_rooms.has (a_room_id)
		ensure
			definition: Result = pending_rooms_model.has (a_room_id)
		end

	has_answered (a_event_id: INTEGER_64): BOOLEAN
			-- Has the request `a_event_id' been taken?
		do
			Result := answered.has (a_event_id)
		ensure
			definition: Result = answered_model.has (a_event_id)
		end

feature -- Basic operations

	wake (a_room_id: INTEGER_64)
			-- Note that `a_room_id' has news; the work waits for `dispatch_pending'.
		do
			wake_count := wake_count + 1
			if not pending_rooms.has (a_room_id) then
				pending_rooms.extend (a_room_id)
			end
		ensure then
			queued: pending_rooms_model.has (a_room_id)
			only_queued: pending_rooms_model |=| ((old pending_rooms_model) & a_room_id)
			no_work: cursors_model |=| old cursors_model and answered_model |=| old answered_model and requests_seen = old requests_seen
		end

	receive_status (a_status: separate CHAT_STATUS)
			-- Statuses are not requests.
		do
		ensure then
			nothing_queued: pending_rooms_model |=| old pending_rooms_model
		end

	dispatch_pending
			-- Drain the noted rooms in order: for each, pull the pages after its
			-- cursor from the API and handle every event. A wake queued behind
			-- this call (SCOOP runs them one at a time) waits for the next call.
		local
			l_room, l_before: INTEGER_64
			l_more: BOOLEAN
		do
			from
			until
				pending_rooms.is_empty
			loop
				l_room := pending_rooms.first
				pending_rooms.start
				pending_rooms.remove
				from
					l_more := True
				until
					not l_more
				loop
					l_before := cursor_of (l_room)
					handle_page (l_room, pull_page (api, l_room, l_before, Pull_limit))
					l_more := last_page_count >= Pull_limit and cursor_of (l_room) > l_before
				end
			end
		ensure
			drained: pending_rooms_model.is_empty
			monotone: across cursors as ic all
				((old cursors_model).domain.has (@ic.key) implies ic >= (old cursors_model) [@ic.key])
				and (not (old cursors_model).domain.has (@ic.key) implies ic >= start_after) end
			answered_only_grows: (old answered_model) <= answered_model
			wakes_untouched: wake_count = old wake_count
		end

	handle_page (a_room_id: INTEGER_64; a_bytes: READABLE_STRING_8)
			-- Decode one page of `a_room_id' - the API's bytes, or a hand-fed one -
			-- and handle its events in order; the room's cursor moves to the last
			-- id handled. Events at or below the cursor, and events of other rooms,
			-- are skipped; undecodable bytes change nothing.
		require
			positive_room: a_room_id > 0
		do
			if attached codec.page_from_bytes (a_bytes) as p then
				across p.events as e loop
					if e.room_id = a_room_id and e.id > cursor_of (a_room_id) then
						handle_event (e)
						cursors.force (e.id, a_room_id)
					end
				end
				last_page_count := p.events.count
			else
				last_page_count := 0
				-- Phase 4: log.warn ("dispatcher: undecodable page for room " + a_room_id.out)
			end
		ensure
			cursor_never_backwards: cursor_of (a_room_id) >= old cursor_of (a_room_id)
			advanced_to_page: attached codec.page_from_bytes (a_bytes) as p implies across p.events as e all e.room_id = a_room_id implies cursor_of (a_room_id) >= e.id end
			no_jump: attached codec.page_from_bytes (a_bytes) as p implies cursor_of (a_room_id) <= (old cursor_of (a_room_id)).max (p.last_id)
			other_cursors_untouched: cursors_model.removed (a_room_id) |=| (old cursors_model).removed (a_room_id)
			counted_when_decoded: attached codec.page_from_bytes (a_bytes) as p implies last_page_count = p.events.count
			zero_when_undecodable: codec.page_from_bytes (a_bytes) = Void implies last_page_count = 0
			nothing_queued: pending_rooms_model |=| old pending_rooms_model
		end

	handle_event (a_event: CHAT_EVENT)
			-- Take `a_event' as a request if it is one and has not been taken:
			-- ask the participant - when the bot can post there, the queue has
			-- room and the asker's limit allows - and post the reply, a refusal
			-- or an apology.
		local
			l_answer: PARTICIPANT_ANSWER
		do
			if not answered.has (a_event.id) and then attached target_of (a_event) as l_target then
				answered.put (a_event.id, a_event.id)
				requests_seen := requests_seen + 1
				last_ask_granted := False
				last_can_post := can_post (api, l_target.bot_user.id, a_event.room_id)
				if not last_can_post then
					answer_failures := answer_failures + 1
				elseif queue_depth_of (l_target) >= Max_queue_depth then
					post_answer (l_target, a_event.room_id, Busy_text)
				else
					last_ask_key := l_target.limit_key (a_event.sender_id)
					last_ask_granted := try_ask (api, last_ask_key)
					if not last_ask_granted then
						post_answer (l_target, a_event.room_id, Limited_text)
					else
						enqueue (l_target)
						l_answer := l_target.answer (request_of (a_event, l_target))
						dequeue (l_target)
						asks := asks + 1
						if l_answer.is_success then
							post_answer (l_target, a_event.room_id, l_answer.text)
						elseif attached l_answer.error as e then
							post_answer (l_target, a_event.room_id, apology_for (e))
						end
					end
				end
			end
		ensure
			skipped_when_seen: (old answered_model).has (a_event.id) implies (requests_seen = old requests_seen and asks = old asks
				and answers_posted = old answers_posted and answer_failures = old answer_failures and target_calls (a_event) = old target_calls (a_event))
			seen_once: (not (old answered_model).has (a_event.id) and target_of (a_event) /= Void) implies answered_model |=| ((old answered_model) & a_event.id)
			others_unmarked: not (not (old answered_model).has (a_event.id) and target_of (a_event) /= Void) implies answered_model |=| old answered_model
			counts_requests: (not (old answered_model).has (a_event.id) and target_of (a_event) /= Void) implies requests_seen = old requests_seen + 1
			ignores_bots: a_event.is_bot_authored implies requests_seen = old requests_seen
			ignores_unaddressed: not parser.is_addressed (a_event.body) implies requests_seen = old requests_seen
			ignores_non_messages: not a_event.is_message implies requests_seen = old requests_seen
			accounted: (not (old answered_model).has (a_event.id) and target_of (a_event) /= Void) implies answers_posted + answer_failures = old answers_posted + old answer_failures + 1
			nothing_for_non_requests: target_of (a_event) = Void implies (answers_posted = old answers_posted and answer_failures = old answer_failures and asks = old asks)
			only_member_rooms: (not (old answered_model).has (a_event.id) and target_of (a_event) /= Void and not last_can_post) implies
				(target_calls (a_event) = old target_calls (a_event) and answers_posted = old answers_posted and answer_failures = old answer_failures + 1)
			rate_limited_not_asked: not last_ask_granted implies target_calls (a_event) = old target_calls (a_event)
			asked_once: (not (old answered_model).has (a_event.id) and target_of (a_event) /= Void and last_ask_granted) implies
				(target_calls (a_event) = old target_calls (a_event) + 1 and asks = old asks + 1)
			limit_recorded: (not (old answered_model).has (a_event.id) and last_ask_granted and attached target_of (a_event) as p) implies
				last_ask_key.same_string (p.limit_key (a_event.sender_id))
			refused_when_full: (old target_queue_depth (a_event)) >= Max_queue_depth implies target_calls (a_event) = old target_calls (a_event)
			queue_settled: target_queue_depth (a_event) = old target_queue_depth (a_event)
			cursors_unchanged: cursors_model |=| old cursors_model
			nothing_queued: pending_rooms_model |=| old pending_rooms_model
		end

feature {NONE} -- The API, only as a separate argument

	api: separate CHAT_API
			-- The service's processor; held, never called directly.

	pull_page (a_api: separate CHAT_API; a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): STRING_8
			-- The page of `a_room_id' after `a_since_id', copied here as bytes.
		require
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
			limit_in_range: a_limit > 0 and a_limit <= {CHAT_SERVICE}.Page_maximum
		do
			create Result.make_from_separate (a_api.dispatcher_page (a_room_id, a_since_id, a_limit))
		end

	can_post (a_api: separate CHAT_API; a_bot_user_id, a_room_id: INTEGER_64): BOOLEAN
			-- May bot `a_bot_user_id' post in `a_room_id'?
		do
			Result := a_api.dispatcher_can_post (a_bot_user_id, a_room_id)
		end

	try_ask (a_api: separate CHAT_API; a_key: READABLE_STRING_8): BOOLEAN
			-- One more ask under `a_key', decided and counted on the API's processor.
		require
			key_given: not a_key.is_empty
		do
			Result := a_api.dispatcher_try_ask (a_key)
		end

	post_reply (a_api: separate CHAT_API; a_bot_user_id, a_room_id: INTEGER_64; a_text: READABLE_STRING_32): INTEGER
			-- Post `a_text' as the bot; the status.
		require
			text_given: not a_text.is_empty
		do
			Result := a_api.dispatcher_post (a_bot_user_id, a_room_id, a_text)
		ensure
			http_status: Result >= 200 and Result <= 599
		end

	display_name_of (a_api: separate CHAT_API; a_user_id: INTEGER_64): STRING_32
			-- The member's display name, copied here.
		do
			create Result.make_from_separate (a_api.dispatcher_display_name (a_user_id))
		ensure
			given: not Result.is_empty
		end

	room_name_of (a_api: separate CHAT_API; a_room_id: INTEGER_64): STRING_32
			-- The room's name, copied here.
		do
			create Result.make_from_separate (a_api.dispatcher_room_name (a_room_id))
		ensure
			given: not Result.is_empty
		end

feature {NONE} -- Implementation

	parser: ADDRESS_PARSER

	log: CHAT_LOG

	codec: CHAT_JSON

	pending_rooms: ARRAYED_LIST [INTEGER_64]
			-- Distinct rooms, in the order first noted.

	cursors: HASH_TABLE [INTEGER_64, INTEGER_64]
			-- Room id -> last event id examined.

	answered: HASH_TABLE [INTEGER_64, INTEGER_64]
			-- The ids of the requests taken.

	queue_depths: HASH_TABLE [INTEGER, STRING_32]
			-- Handle -> requests accepted and not yet answered.

	post_answer (a_participant: PARTICIPANT; a_room_id: INTEGER_64; a_text: READABLE_STRING_32)
			-- Post `a_text' as `a_participant' and account for the outcome.
		require
			text_given: not a_text.is_empty
		do
			last_post_status := post_reply (api, a_participant.bot_user.id, a_room_id, a_text)
			if last_post_status = 201 then
				answers_posted := answers_posted + 1
			else
				answer_failures := answer_failures + 1
			end
		ensure
			accounted: answers_posted + answer_failures = old answers_posted + old answer_failures + 1
			posted_when_created: (answers_posted = old answers_posted + 1) = (last_post_status = 201)
		end

	request_of (a_event: CHAT_EVENT; a_target: PARTICIPANT): PARTICIPANT_REQUEST
			-- What `a_target' is asked by `a_event'.
		require
			is_request: target_of (a_event) = a_target
		do
			check parsed_by_target_of: attached parser.parse (a_event.body) as r then
				create Result.make_addressed (a_event.sender_id, display_name_of (api, a_event.sender_id), r.text,
					a_event.room_id, room_name_of (api, a_event.room_id), a_target.max_characters, r.via)
			end
		ensure
			same_room: Result.room_id = a_event.room_id
			same_asker: Result.asker_id = a_event.sender_id
		end

	enqueue (a_participant: PARTICIPANT)
		require
			has_room: queue_depth_of (a_participant) < Max_queue_depth
		do
			queue_depths.force (queue_depth_of (a_participant) + 1, a_participant.handle.twin)
		ensure
			one_more: queue_depth_of (a_participant) = old queue_depth_of (a_participant) + 1
		end

	dequeue (a_participant: PARTICIPANT)
		require
			queued: queue_depth_of (a_participant) > 0
		do
			queue_depths.force (queue_depth_of (a_participant) - 1, a_participant.handle.twin)
		ensure
			one_less: queue_depth_of (a_participant) = old queue_depth_of (a_participant) - 1
		end

	apology_for (a_error: CHAT_ERROR): STRING_32
			-- What the room sees when a participant could not answer.
		do
			Result := {STRING_32} "Sorry - no answer: " + a_error.message
		ensure
			given: not Result.is_empty
		end

feature -- Constants

	Max_queue_depth: INTEGER = 8
			-- Requests waiting for one participant beyond which the next is refused.

	Pull_limit: INTEGER = 200
			-- Events per page pulled from the API.

	Busy_text: STRING_32 = "I am busy right now - please ask again in a moment."

	Limited_text: STRING_32 = "You have reached your limit with me for now - please try again later."

invariant
	named: not subscriber_name.is_empty
	start_non_negative: start_after >= 0
	counts_non_negative: wake_count >= 0 and requests_seen >= 0 and answers_posted >= 0 and answer_failures >= 0 and asks >= 0
	answers_cover_requests: answers_posted + answer_failures <= requests_seen
	asks_within_requests: asks <= requests_seen
	requests_are_answered_ids: requests_seen = answered.count
	cursors_after_start: across cursors as ic all ic >= start_after end
	queues_bounded: across queue_depths as ic all ic >= 0 and ic <= Max_queue_depth end
	pending_distinct: pending_rooms_model.count = pending_rooms.count
	models_consistent: cursors_model.count = cursors.count and answered_model.count = answered.count

end
