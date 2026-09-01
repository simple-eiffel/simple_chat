note
	description: "[
		The room member that turns an addressed message into a participant's
		reply. It lives on its own processor (D1, approach section 8) and
		drives itself (NEW-1): the bus's asynchronous `wake' notes the room
		and immediately drains everything pending (`dispatch_pending') -
		SCOOP runs the wakes one at a time on this processor, so a wake
		arriving while one drains simply waits its turn and the poster
		never blocks. Draining pulls the page after each room's cursor from
		the API as bytes, decodes a copy here (CHAT_JSON), and hands each
		event to `handle_event'. Nothing of the API's processor is ever
		held: `api' is touched only inside routines that take it as a
		separate argument, only bytes and scalars cross, and every reply
		goes back through `dispatcher_post'. `make' builds its own
		registry, parser and log on this processor, so a separate creator
		(DISPATCHER_HOST) can bring the dispatcher up with just the API and
		the store's last id.

		`handle_event' is idempotent (`answered_model' remembers every
		request taken; ids at or below `pruned_floor' can never recur, so
		`answered' stays bounded - NEW-6), so a page delivered twice, a
		restart from `start_after' (the store's last id, Issue 16) or a
		hand-fed event can never answer twice (Issue 9). A request is asked
		of its participant only when the bot can post in that room
		(`only_member_rooms') and the asker's rate limit allows it
		(`rate_limited_not_asked', `asked_once', `limit_recorded' - Issue
		15); a request whose `via' names a participant is charged under
		BOTH keys for the same asker (`via_charged'); a `via' the target
		does not permit is an explicit refusal, never silently dropped
		(NEW-10); refusals and apologies are posted as answers; a post the
		service refuses is an `answer_failure'; an engine that raises is
		one `answer_failure' with its queue slot released, and the
		dispatcher lives on (NEW-7). One request at a time per participant,
		in order, behind a bounded FIFO (`Max_queue_depth'). Bot-authored,
		system and image events are never requests (no echo loops).
	]"
	author: "Larry Rix"

class
	PARTICIPANT_DISPATCHER

inherit
	EVENT_SUBSCRIBER

	CHAT_SHARED

create
	make

feature {NONE} -- Initialization

	make (a_api: separate CHAT_API; a_start_after: INTEGER_64)
			-- A dispatcher over `a_api' that never looks at events up to
			-- `a_start_after' (the store's last id at start:
			-- `dispatcher_start_after'). Builds its own registry, parser and
			-- log HERE, so a creator on another processor needs to pass only
			-- what crosses processors cleanly (NEW-1); participants are then
			-- registered through `registry'.
		require
			start_non_negative: a_start_after >= 0
		local
			l_registry: PARTICIPANT_REGISTRY
			l_logger: SIMPLE_LOGGER
		do
			api := a_api
			create l_registry.make
			create parser.make (l_registry)
			create l_logger
			create log.make (l_logger)
			start_after := a_start_after
			pruned_floor := a_start_after
			subscriber_name := "dispatcher"
			create pending_rooms.make (4)
			create cursors.make (4)
			create answered.make (64)
			create queue_depths.make (4)
			queue_depths.compare_objects
			create codec.make
			create last_ask_key.make_empty
			create last_via_key.make_empty
		ensure
			starts_where_told: start_after = a_start_after
			floor_at_start: pruned_floor = a_start_after
			own_registry: registry.count = participants_registered
			fresh: wake_count = 0 and requests_seen = 0 and answers_posted = 0 and answer_failures = 0 and asks = 0
			nothing_pending: pending_rooms_model.is_empty
			no_cursors: cursors_model.is_empty
			nothing_answered: answered_model.is_empty
		end

feature -- Population

	populate
			-- Register the configured participants. DISPATCHER_HOST commands
			-- this as the dispatcher's first OWN turn, never during creation:
			-- a creation-time call rides the creator's passed locks, and under
			-- ISE SCOOP such a call can execute on the CREATOR's thread
			-- (impersonation) - which the thread-affine SQLite connection
			-- refuses (SQLITE_DATABASE.is_accessible: owner thread only).
			-- On this dispatcher's own turn the API is reserved fresh, so the
			-- store's queries run on the store's own thread.
		do
			populate_from_shared_configuration (api)
		ensure
			accounted: registry.count = participants_registered
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

	participants_registered: INTEGER
			-- Participants the shared configuration brought to life at creation (Task 7 item 5).

	participants_skipped: INTEGER
			-- Configuration entries refused at creation, one log line each (D6).

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

	last_via_key: STRING_8
			-- The via participant's limiter key the latest granted ask was
			-- also charged to (Issue 15, `via_charged'); empty when the
			-- latest request named no via participant.

	last_answer_raised: BOOLEAN
			-- Did the latest request's engine raise (NEW-7)? Such a request
			-- is accounted as one `answer_failure' with its queue slot
			-- released; the dispatcher lives on.

	pruned_floor: INTEGER_64
			-- Ids at or below it can never be handled again and are pruned
			-- from `answered' (NEW-6): every handled event's room is in
			-- `cursors' with a cursor at or above its id, and a page only
			-- hands over ids above its room's cursor.

	minimum_cursor: INTEGER_64
			-- The lowest room cursor; `start_after' when no room was pulled yet.
		do
			Result := start_after
			if not cursors.is_empty then
				across cursors as ic loop
					if @ic.is_first or ic < Result then
						Result := ic
					end
				end
			end
		ensure
			at_least_start: Result >= start_after
		end

	request_via_of (a_event: CHAT_EVENT): detachable STRING_32
			-- The `via' choice `a_event''s request makes, or Void (contract support).
		do
			if attached parser.parse (a_event.body) as r and then attached r.via as v then
				Result := v.twin
			end
		end

	via_target_of (a_event: CHAT_EVENT): detachable PARTICIPANT
			-- The registered participant a request's `via' names, or Void -
			-- "via plain", and via choices that name no participant, give
			-- Void. Such a request is charged under BOTH keys (Issue 15).
		do
			if attached request_via_of (a_event) as v then
				Result := registry.find (v)
			end
		ensure
			only_with_via: Result /= Void implies request_via_of (a_event) /= Void
			registered: attached Result as p implies registry.has (p.handle)
		end

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
			-- Note that `a_room_id' has news, then drain everything pending
			-- (NEW-1: the dispatcher drives itself). SCOOP runs wakes one at
			-- a time on this processor: the bus's `wake_one' is an
			-- asynchronous command, so the poster never waits, and a wake
			-- arriving while this one drains is queued behind it - the
			-- drain it triggers sees anything this one left.
		do
			wake_count := wake_count + 1
			if not pending_rooms.has (a_room_id) then
				pending_rooms.extend (a_room_id)
			end
			dispatch_pending
		ensure then
			drained: pending_rooms_model.is_empty
			monotone: across cursors as ic all
				((old cursors_model).domain.has (@ic.key) implies ic >= (old cursors_model) [@ic.key])
				and (not (old cursors_model).domain.has (@ic.key) implies ic >= start_after) end
			floor_current: pruned_floor = minimum_cursor
		end

	receive_status (a_status: separate CHAT_STATUS)
			-- Statuses are not requests.
		do
		ensure then
			nothing_queued: pending_rooms_model |=| old pending_rooms_model
		end

	dispatch_pending
			-- Drain the noted rooms in order: for each, pull the pages after
			-- its cursor from the API and handle every event; then prune the
			-- taken ids nothing can deliver again (NEW-6). A wake queued
			-- behind this call (SCOOP runs them one at a time) waits for the
			-- next call.
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
			prune_answered
		ensure
			drained: pending_rooms_model.is_empty
			monotone: across cursors as ic all
				((old cursors_model).domain.has (@ic.key) implies ic >= (old cursors_model) [@ic.key])
				and (not (old cursors_model).domain.has (@ic.key) implies ic >= start_after) end
			floor_current: pruned_floor = minimum_cursor
			kept_above_floor: across answered as ic all @ic.key > pruned_floor end
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
				log.warn ("dispatcher: undecodable page for room " + a_room_id.out)
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
			-- Take `a_event' as a request if it is one and has not been taken
			-- (ids at or below `pruned_floor' count as taken - NEW-6): ask
			-- the participant - when the bot can post there, the request's
			-- `via' (if any) is one the target permits (else an explicit
			-- refusal, NEW-10), the queue has room and the asker's limit
			-- allows, under the via participant's key too when the `via'
			-- names one (Issue 15) - and post the reply, a refusal or an
			-- apology. An engine that raises is retried into the accounting
			-- branch once: one `answer_failure', the queue slot released,
			-- the dispatcher alive (NEW-7).
		local
			l_answer: PARTICIPANT_ANSWER
			l_failed, l_taken, l_queued: BOOLEAN
		do
			if not l_failed then
				last_answer_raised := False
			end
			if l_failed then
				-- The engine (or the posting path after it) raised: the
				-- request was taken on the first attempt; release the slot
				-- and account the failure.
				if l_queued and then attached target_of (a_event) as l_crashed and then queue_depth_of (l_crashed) > 0 then
					dequeue (l_crashed)
					l_queued := False
				end
				answer_failures := answer_failures + 1
				last_answer_raised := True
				log.error ({STRING_32} "dispatcher: participant raised answering event " + a_event.id.out
					+ (if attached last_raise_reason as r then {STRING_32} " - " + r else {STRING_32} "" end))
			elseif a_event.id > pruned_floor and then not answered.has (a_event.id) and then attached target_of (a_event) as l_target then
				answered.put (a_event.id, a_event.id)
				requests_seen := requests_seen + 1
				l_taken := True
				last_ask_granted := False
				create last_via_key.make_empty
				last_can_post := can_post (api, l_target.bot_user.id, a_event.room_id)
				if not last_can_post then
					answer_failures := answer_failures + 1
				elseif attached request_via_of (a_event) as l_choice and then not l_target.permits_via (l_choice) then
					post_answer (l_target, a_event.room_id, Via_refused_text + l_choice)
				elseif queue_depth_of (l_target) >= Max_queue_depth then
					post_answer (l_target, a_event.room_id, Busy_text)
				else
					last_ask_key := l_target.limit_key (a_event.sender_id)
					if attached via_target_of (a_event) as l_via_target and then l_via_target /= l_target then
						last_via_key := l_via_target.limit_key (a_event.sender_id)
						last_ask_granted := try_ask (api, last_ask_key) and then try_ask (api, last_via_key)
					else
						last_ask_granted := try_ask (api, last_ask_key)
					end
					if not last_ask_granted then
						post_answer (l_target, a_event.room_id, Limited_text)
					else
						enqueue (l_target)
						l_queued := True
						l_answer := l_target.answer (request_of (a_event, l_target))
						dequeue (l_target)
						l_queued := False
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
			ancient_skipped: a_event.id <= (old pruned_floor) implies (requests_seen = old requests_seen and answered_model |=| old answered_model)
			skipped_when_seen: ((old answered_model).has (a_event.id) or a_event.id <= (old pruned_floor)) implies (requests_seen = old requests_seen and asks = old asks
				and answers_posted = old answers_posted and answer_failures = old answer_failures and target_calls (a_event) = old target_calls (a_event))
			seen_once: (a_event.id > (old pruned_floor) and not (old answered_model).has (a_event.id) and target_of (a_event) /= Void) implies answered_model |=| ((old answered_model) & a_event.id)
			others_unmarked: not (a_event.id > (old pruned_floor) and not (old answered_model).has (a_event.id) and target_of (a_event) /= Void) implies answered_model |=| old answered_model
			counts_requests: (a_event.id > (old pruned_floor) and not (old answered_model).has (a_event.id) and target_of (a_event) /= Void) implies requests_seen = old requests_seen + 1
			ignores_bots: a_event.is_bot_authored implies requests_seen = old requests_seen
			ignores_unaddressed: not parser.is_addressed (a_event.body) implies requests_seen = old requests_seen
			ignores_non_messages: not a_event.is_message implies requests_seen = old requests_seen
			accounted: (a_event.id > (old pruned_floor) and not (old answered_model).has (a_event.id) and target_of (a_event) /= Void) implies answers_posted + answer_failures = old answers_posted + old answer_failures + 1
			nothing_for_non_requests: target_of (a_event) = Void implies (answers_posted = old answers_posted and answer_failures = old answer_failures and asks = old asks)
			only_member_rooms: (a_event.id > (old pruned_floor) and not (old answered_model).has (a_event.id) and target_of (a_event) /= Void and not last_can_post) implies
				(target_calls (a_event) = old target_calls (a_event) and answers_posted = old answers_posted and answer_failures = old answer_failures + 1)
			rate_limited_not_asked: not last_ask_granted implies target_calls (a_event) = old target_calls (a_event)
			via_refused_is_told: (a_event.id > (old pruned_floor) and not (old answered_model).has (a_event.id) and attached target_of (a_event) as t
				and then (last_can_post and then attached request_via_of (a_event) as v and then not t.permits_via (v))) implies
				(asks = old asks and target_calls (a_event) = old target_calls (a_event))
			asked_once: (a_event.id > (old pruned_floor) and not (old answered_model).has (a_event.id) and target_of (a_event) /= Void and last_ask_granted and not last_answer_raised) implies
				(target_calls (a_event) = old target_calls (a_event) + 1 and asks = old asks + 1)
			engine_failure_accounted: last_answer_raised implies (answer_failures = old answer_failures + 1 and answers_posted = old answers_posted)
			limit_recorded: (a_event.id > (old pruned_floor) and not (old answered_model).has (a_event.id) and last_ask_granted and attached target_of (a_event) as p) implies
				last_ask_key.same_string (p.limit_key (a_event.sender_id))
			via_charged: (a_event.id > (old pruned_floor) and not (old answered_model).has (a_event.id) and last_ask_granted
				and attached via_target_of (a_event) as vt and then vt /= target_of (a_event)) implies
				last_via_key.same_string (vt.limit_key (a_event.sender_id))
				-- Both keys were asked, target's first, then the via participant's, for the same asker; both granted, or the
				-- request was refused (Limited_text). A via-key refusal after the target grant leaves the target's charge
				-- spent and the request refused: refusal is accounted, never refunded.
			refused_when_full: (old target_queue_depth (a_event)) >= Max_queue_depth implies target_calls (a_event) = old target_calls (a_event)
			queue_settled: target_queue_depth (a_event) = old target_queue_depth (a_event)
			cursors_unchanged: cursors_model |=| old cursors_model
			nothing_queued: pending_rooms_model |=| old pending_rooms_model
		rescue
			if l_taken and not l_failed then
				l_failed := True
				last_raise_reason := current_raise_reason
				retry
			end
		end

feature {NONE} -- The API, only as a separate argument

	api: separate CHAT_API
			-- The service's processor; held, never called directly.

	last_raise_reason: detachable STRING_32
			-- What the last caught raise reported (diagnostic for the log).

	current_raise_reason: detachable STRING_32
			-- The pending exception's type and description, or Void.
		local
			l_r: STRING_32
		do
			if attached (create {EXCEPTION_MANAGER}).last_exception as l_x then
				create l_r.make_empty
				l_r.append (l_x.generating_type.name_32)
				if attached l_x.description as l_d then
					l_r.append ({STRING_32} ": ")
					l_r.append (l_d.to_string_32)
				end
				Result := l_r
			end
		end

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

	prune_answered
			-- Drop every taken id at or below `minimum_cursor' (NEW-6): its
			-- room's cursor is already past it, so no page can deliver it
			-- again; `pruned_floor' remembers the line and `handle_event'
			-- treats ids at or below it as already taken.
		local
			l_floor: INTEGER_64
			l_dead: ARRAYED_LIST [INTEGER_64]
		do
			l_floor := minimum_cursor
			create l_dead.make (8)
			across answered as ic loop
				if @ic.key <= l_floor then
					l_dead.extend (@ic.key)
				end
			end
			across l_dead as d loop
				answered.remove (d)
			end
			pruned_floor := l_floor
		ensure
			floor_set: pruned_floor = minimum_cursor
			kept_above: across answered as ic all @ic.key > pruned_floor end
			nothing_added: answered_model <= old answered_model
			floor_monotone: pruned_floor >= old pruned_floor
		end

	apology_for (a_error: CHAT_ERROR): STRING_32
			-- What the room sees when a participant could not answer.
		do
			Result := {STRING_32} "Sorry - no answer: " + a_error.message
		ensure
			given: not Result.is_empty
		end

feature {NONE} -- Population (Task 7 item 5)

	populate_from_shared_configuration (a_api: separate CHAT_API)
			-- Bring the [[participants]] of the shared configuration to
			-- life: when the per-process settings name a configuration path
			-- under `Config_path_key' (the same key the facade fills and
			-- CHAT_API.make_from_shared reads) and that file is valid, each
			-- entry becomes a registered participant with a stored bot user
			-- - resolved through `a_api', created on first sight: the
			-- [[participants]] table drives the store the way
			-- --create-admin drives the first admin - plus its aliases and
			-- `via' choices. An entry that cannot be built (a username a
			-- person holds, a missing engine, a bad sandbox) is skipped
			-- with one log line and the dispatcher comes up with the rest
			-- (D6). With no path shared, or a refused file, nothing is
			-- registered.
		local
			l_config: SERVER_CONFIG
			l_data_dir: STRING_32
			l_entries: ARRAYED_LIST [PARTICIPANT_CONFIG]
		do
			if attached shared_item ({CHAT_SHARED}.Config_path_key) as l_path and then not l_path.is_empty then
				create l_config.make_from_file (l_path)
				if l_config.is_valid and l_config.is_loaded then
					l_data_dir := absolute_directory (l_config.data_dir)
					l_entries := l_config.participants
					across 1 |..| l_entries.count as i loop
						build_participant (a_api, l_entries [i], i, l_config, l_data_dir)
					end
				else
					log.warn ("dispatcher: the configuration at " + l_path + " is refused; no participant is registered")
				end
			end
		ensure
			counted: registry.count = participants_registered
		end

	build_participant (a_api: separate CHAT_API; a_config: PARTICIPANT_CONFIG; a_index: INTEGER; a_whole: SERVER_CONFIG; a_data_dir: STRING_32)
			-- Register `a_config''s participant with its aliases and
			-- shapers, or skip the entry with one log line - a raising
			-- construction (a violated sandbox precondition, a broken
			-- engine) is caught here, so one bad entry never takes the
			-- dispatcher down (D6).
		local
			l_participant: detachable PARTICIPANT
			l_bot: detachable CHAT_USER
			l_failed: BOOLEAN
			l_reason: detachable STRING_32
		do
			if not l_failed then
				if engine_present (a_config) then
						-- The bot is resolved (and so possibly created) only
						-- for an entry whose engine is there: a skipped entry
						-- must not drive a user into the store.
					log.info ({STRING_32} "dispatcher: resolving bot user for " + a_config.handle)
					l_bot := bot_user_at (a_api, a_index, a_config)
					if attached l_bot as b and then not registry.has (a_config.handle) and then not registry.has_alias (a_config.handle) then
						log.info ({STRING_32} "dispatcher: building " + a_config.handle + {STRING_32} " (bot id " + b.id.out + {STRING_32} ")")
						l_participant := new_participant (a_config, a_whole, a_data_dir, b)
					end
				else
					log.warn ({STRING_32} "dispatcher: participant " + a_config.handle + {STRING_32} " names a missing engine; entry skipped")
				end
			end
			if attached l_participant as p then
				registry.register (p)
				participants_registered := participants_registered + 1
				register_aliases (a_config)
			else
				participants_skipped := participants_skipped + 1
				if l_failed then
					log.error ({STRING_32} "dispatcher: participant " + a_config.handle + {STRING_32} " raised during construction; entry skipped"
						+ (if attached l_reason as r then {STRING_32} " - " + r else {STRING_32} "" end))
				elseif l_bot /= Void then
					log.warn ({STRING_32} "dispatcher: participant " + a_config.handle + {STRING_32} " cannot be built (missing engine or bad sandbox); entry skipped")
				end
			end
		ensure
			one_way: (registry.count = old registry.count + 1 and participants_registered = old participants_registered + 1)
				xor (participants_skipped = old participants_skipped + 1)
		rescue
				-- One retry only: the retried body skips construction and
				-- accounts the skip; a second exception propagates instead
				-- of looping the rescue. The cause is kept for the log line.
			if not l_failed then
				l_failed := True
				l_participant := Void
				if attached (create {EXCEPTION_MANAGER}).last_exception as l_x then
					create l_reason.make_empty
					l_reason.append (l_x.generating_type.name_32)
					if attached l_x.description as l_d then
						l_reason.append ({STRING_32} ": ")
						l_reason.append (l_d.to_string_32)
					end
					if attached l_x.trace as l_t then
						l_reason.append ({STRING_32} " | ")
						l_reason.append (l_t.substring (1, l_t.count.min (600)).to_string_32)
					end
				end
				retry
			end
		end

	engine_present (a_config: PARTICIPANT_CONFIG): BOOLEAN
			-- Is the one engine file `a_config''s kind needs actually there?
			-- The tool kinds name a file to check; the AI kinds and "none"
			-- carry nothing checkable here (a dead engine answers errors
			-- at ask time), so they pass.
		local
			l_file: RAW_FILE
		do
			if a_config.kind.same_string ({PARTICIPANT_CONFIG}.Kind_bible_tool) then
				create l_file.make_with_name (a_config.executable)
				Result := l_file.exists
			elseif a_config.kind.same_string ({PARTICIPANT_CONFIG}.Kind_shape_tool) then
				create l_file.make_with_name (a_config.database)
				Result := l_file.exists
			else
				Result := True
			end
		end

	bot_user_at (a_api: separate CHAT_API; a_index: INTEGER; a_config: PARTICIPANT_CONFIG): detachable CHAT_USER
			-- The stored, active bot that entry `a_index' posts as - resolved
			-- and created on first sight WHOLLY on the API's side, from the
			-- API's own copy of the same configuration file
			-- (`dispatcher_bot_id_of'). Only the expanded index crosses this
			-- synchronous query: shipping our strings made the API reach back
			-- to this processor while it was blocked on the very same query -
			-- a SCOOP deadlock that froze the whole server. Void, with one
			-- log line, when the username belongs to a person or cannot be
			-- created; `a_config' (our copy of the same file) supplies the
			-- username and display for the local mirror.
		local
			l_id: INTEGER_64
			l_now: SIMPLE_DATE_TIME
		do
			io.error.put_string ("bot_user_at: reserving the API for entry " + a_index.out + "%N")
			l_id := a_api.dispatcher_bot_id_of (a_index)
			io.error.put_string ("bot_user_at: the API answered id " + l_id.out + "%N")
			if l_id > 0 then
				create l_now.make_now
				create Result.make (l_id, a_config.bot_username, a_config.marked_display_name, "", False, True, l_now)
			else
				log.warn ({STRING_32} "dispatcher: no bot user for " + a_config.handle + {STRING_32} " (the username is a person's, or creation failed); entry skipped")
			end
		ensure
			stored_bot: attached Result as b implies (b.is_stored and b.is_bot and b.is_active)
		end

	new_participant (a_config: PARTICIPANT_CONFIG; a_whole: SERVER_CONFIG; a_data_dir: STRING_32; a_bot: CHAT_USER): detachable PARTICIPANT
			-- `a_config''s participant by kind, or Void for one whose
			-- engine is missing. The claude sandbox directory
			-- (<data_dir>\participants\<name>) is derived from the
			-- configuration's data directory - the entry's own `engine'
			-- value documents it but the derivation is the law - and is
			-- created when absent (the sandbox predicate demands a real,
			-- cleanly-ancestored directory).
		require
			bot: a_bot.is_bot and a_bot.is_stored and a_bot.is_active
		local
			l_file: RAW_FILE
			l_sandbox: STRING_32
			l_claude_client: CLAUDE_CODE_CLIENT
			l_ollama_client: OLLAMA_CLIENT
			l_tool: detachable TOOL_PARTICIPANT
		do
			if a_config.kind.same_string ({PARTICIPANT_CONFIG}.Kind_none) then
				create {NULL_PARTICIPANT} Result.make (a_config.handle, a_bot)
			elseif a_config.kind.same_string ({PARTICIPANT_CONFIG}.Kind_bible_tool) then
				create l_file.make_with_name (a_config.executable)
				if l_file.exists then
					create {BIBLE_TOOL_PARTICIPANT} l_tool.make (a_config.handle, a_bot, a_config.executable, a_config.max_characters, a_config.timeout_seconds)
				end
			elseif a_config.kind.same_string ({PARTICIPANT_CONFIG}.Kind_shape_tool) then
				create l_file.make_with_name (a_config.database)
				if l_file.exists then
					create {SHAPE_TOOL_PARTICIPANT} l_tool.make (a_config.handle, a_bot, a_config.database, a_config.max_characters, a_config.timeout_seconds)
				end
			elseif a_config.kind.same_string ({PARTICIPANT_CONFIG}.Kind_ollama) then
				create l_ollama_client.make
				create {OLLAMA_PARTICIPANT} Result.make (a_config.handle, a_bot, l_ollama_client, a_config.model, a_config.max_characters, a_config.timeout_seconds)
			elseif a_config.kind.same_string ({PARTICIPANT_CONFIG}.Kind_claude_code) then
				l_sandbox := sandbox_directory_of (a_data_dir, a_config.handle)
				log.info ({STRING_32} "dispatcher: claude sandbox = " + l_sandbox)
				ensure_directory (l_sandbox)
				log.info ({STRING_32} "dispatcher: sandbox ensured; creating the client")
				create l_claude_client.make
				create {CLAUDE_CODE_PARTICIPANT} Result.make (a_config.handle, a_bot, l_claude_client, a_data_dir, l_sandbox, a_config.max_characters, a_config.timeout_seconds)
			end
			if attached l_tool as t then
				wire_shapers (t, a_config, a_whole, a_data_dir)
				Result := t
			end
		end

	wire_shapers (a_tool: TOOL_PARTICIPANT; a_config: PARTICIPANT_CONFIG; a_whole: SERVER_CONFIG; a_data_dir: STRING_32)
			-- The tool's `via' choices and configured default shapers, each
			-- resolved against the same configuration's AI entries ("plain"
			-- is built in; "none" keeps the mechanical default; a name no
			-- entry carries is skipped with one log line).
		local
			l_choice: STRING_32
		do
			across a_config.allow_via_list as ic loop
				add_choice (a_tool, ic, a_whole, a_data_dir)
			end
			l_choice := a_config.query_shaper
			if not l_choice.is_empty and then l_choice.code (1) = 64 then
				add_choice (a_tool, l_choice, a_whole, a_data_dir)
				if a_tool.allows_via (l_choice) then
					a_tool.set_query_shaper (a_tool.shaper_for (l_choice))
				end
			end
			l_choice := a_config.response_shaper
			if not l_choice.is_empty and then l_choice.code (1) = 64 then
				add_choice (a_tool, l_choice, a_whole, a_data_dir)
				if a_tool.allows_via (l_choice) then
					a_tool.set_response_shaper (a_tool.shaper_for (l_choice))
				end
			end
		end

	add_choice (a_tool: TOOL_PARTICIPANT; a_name: STRING_32; a_whole: SERVER_CONFIG; a_data_dir: STRING_32)
			-- Make `a_name' selectable on `a_tool' when an AI entry backs it.
		do
			if not a_tool.allows_via (a_name) then
				if attached shaper_named (a_name, a_whole, a_data_dir) as l_shaper then
					a_tool.add_shaper (l_shaper)
				else
					log.warn ({STRING_32} "dispatcher: via choice " + a_name + {STRING_32} " of " + a_tool.handle + {STRING_32} " names no AI entry; choice skipped")
				end
			end
		end

	shaper_named (a_name: READABLE_STRING_32; a_whole: SERVER_CONFIG; a_data_dir: STRING_32): detachable SHAPER
			-- A shaper for the via choice `a_name': the configured AI entry
			-- of that handle - an Ollama entry gives an OLLAMA_SHAPER on
			-- its model, a Claude entry a CLAUDE_SHAPER whose client is
			-- pinned exactly as the participant's own (sandbox directory,
			-- tools off, no settings sources, strict MCP, its timeout).
			-- Void for a name no entry carries ("plain" is already
			-- everywhere).
		local
			l_claude_client: CLAUDE_CODE_CLIENT
			l_ollama_client: OLLAMA_CLIENT
			l_sandbox: STRING_32
		do
			across a_whole.participants as ic loop
				if Result = Void and then ic.handle.same_string (a_name) then
					if ic.kind.same_string ({PARTICIPANT_CONFIG}.Kind_ollama) then
						create l_ollama_client.make
						create {OLLAMA_SHAPER} Result.make (ic.handle, l_ollama_client, ic.model, ic.timeout_seconds)
					elseif ic.kind.same_string ({PARTICIPANT_CONFIG}.Kind_claude_code) then
						l_sandbox := sandbox_directory_of (a_data_dir, ic.handle)
						ensure_directory (l_sandbox)
						create l_claude_client.make
						l_claude_client.set_working_directory (l_sandbox)
						l_claude_client.set_tools_disabled
						l_claude_client.set_setting_sources ("")
						l_claude_client.set_strict_mcp_config
						l_claude_client.set_timeout_seconds (ic.timeout_seconds)
						create {CLAUDE_SHAPER} Result.make (ic.handle, l_claude_client, ic.timeout_seconds)
					end
				end
			end
		end

	register_aliases (a_config: PARTICIPANT_CONFIG)
			-- `a_config''s aliases into the registry (its handle is registered).
		require
			registered: registry.has (a_config.handle)
		do
			across a_config.alias_list as ic loop
				if not registry.has_alias (ic) and then not registry.has (ic.as_lower) then
					registry.register_alias (ic, a_config.handle)
				end
			end
		end

	sandbox_directory_of (a_data_dir, a_handle: READABLE_STRING_32): STRING_32
			-- <a_data_dir>\participants\<a_handle without its "@">.
		require
			data_given: not a_data_dir.is_empty
			handle_shaped: a_handle.count >= 2
		do
			create Result.make_from_string_general (a_data_dir)
			Result.append ({STRING_32} "\participants\")
			Result.append_string_general (a_handle.substring (2, a_handle.count))
		ensure
			anchored: Result.starts_with_general (a_data_dir)
		end

	absolute_directory (a_path: READABLE_STRING_32): STRING_32
			-- `a_path' as an absolute canonical directory: itself when
			-- absolute, else anchored at the server's current working
			-- directory (the sandbox predicate compares absolute paths).
		require
			given: not a_path.is_empty
		local
			l_p: PATH
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_p.make_from_string (a_path)
			if not l_p.is_absolute then
				create l_env
				l_p := l_env.current_working_path.extended_path (l_p)
			end
			create Result.make_from_string (l_p.canonical_path.name)
		ensure
			absolute: (create {PATH}.make_from_string (Result)).is_absolute
		end

	ensure_directory (a_path: READABLE_STRING_32)
			-- Bring the directory at `a_path' to exist; a failure is left
			-- for the sandbox predicate to refuse.
		require
			given: not a_path.is_empty
		local
			l_dir: DIRECTORY
			l_failed: BOOLEAN
		do
			if not l_failed then
				create l_dir.make (a_path)
				if not l_dir.exists then
					l_dir.recursive_create_dir
				end
			end
		rescue
			if not l_failed then
				l_failed := True
				retry
			end
		end

feature -- Constants

	Max_queue_depth: INTEGER = 8
			-- Requests waiting for one participant beyond which the next is refused.

	Pull_limit: INTEGER = 200
			-- Events per page pulled from the API.

	Busy_text: STRING_32 = "I am busy right now - please ask again in a moment."

	Limited_text: STRING_32 = "You have reached your limit with me for now - please try again later."

	Via_refused_text: STRING_32 = "I do not take that via choice - ask without via, or with one I allow: "
			-- Posted when a request's `via' names something its target does
			-- not permit: an explicit refusal, never a silent drop (NEW-10).

invariant
	named: not subscriber_name.is_empty
	start_non_negative: start_after >= 0
	counts_non_negative: wake_count >= 0 and requests_seen >= 0 and answers_posted >= 0 and answer_failures >= 0 and asks >= 0
	population_non_negative: participants_registered >= 0 and participants_skipped >= 0
	answers_cover_requests: answers_posted + answer_failures <= requests_seen
	asks_within_requests: asks <= requests_seen
	requests_cover_answered_ids: requests_seen >= answered.count
	answered_bounded: across answered as ic all @ic.key > pruned_floor end
	floor_at_least_start: pruned_floor >= start_after
	cursors_after_start: across cursors as ic all ic >= start_after end
	queues_bounded: across queue_depths as ic all ic >= 0 and ic <= Max_queue_depth end
	pending_distinct: pending_rooms_model.count = pending_rooms.count
	models_consistent: cursors_model.count = cursors.count and answered_model.count = answered.count

end
