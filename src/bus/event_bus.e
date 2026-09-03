note
	description: "[
		In-process fan-out on the service's processor (D1): `ring' says a
		room has news; `ring_status' hands an ephemeral notice to every
		subscriber. Subscribers are `separate' objects on their own
		processors, so every call to them is an asynchronous command: a
		slow subscriber never stalls a poster (intent-v2 Q2), and a
		subscriber that answers by posting cannot re-enter itself.

		A subscription is a ticket, not an object identity: the bus never
		compares subscribers, so no contract ever touches another
		processor. `subscribe' and `unsubscribe' are idempotent in effect -
		unsubscribing an unknown ticket changes nothing.
	]"
	author: "Larry Rix"

class
	EVENT_BUS

create
	make

feature {NONE} -- Initialization

	make
		do
			create subscribers.make (8)
			create names.make (8)
		ensure
			none: subscribers_model.is_empty
			nothing_rung: ring_count = 0 and status_count = 0
			no_ticket_yet: last_ticket = 0
		end

feature -- Model Queries (for MML postconditions)

	subscribers_model: MML_MAP [INTEGER, STRING_8]
			-- Ticket -> subscriber name, for every live subscription.
		do
			create Result
			across names as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = names.count
		end

feature -- Access

	ring_count: INTEGER
			-- Rings so far.

	status_count: INTEGER
			-- Statuses so far.

	last_ticket: INTEGER
			-- The ticket the latest `subscribe' issued; 0 before any.

	dispatcher_ticket: INTEGER
			-- The participant dispatcher's own subscription, noted by
			-- `subscribe' from the subscriber's name; 0 while it has none.

	muted_ticket: INTEGER
			-- The one subscription `ring' passes over, or 0 for none.
			--
			-- NOBODY IS RUNG FOR THEIR OWN POST. The participant dispatcher
			-- answers by posting through the API, and that post's ring came
			-- straight back into the dispatcher - not later, on the
			-- dispatcher's own turn, but THERE AND THEN, on the API's
			-- thread, through the lock the post passes it (ISE SCOOP
			-- impersonation), while `dispatch_pending' was still draining.
			-- That re-entrant `wake' queued a room and counted itself under
			-- a frame that promises neither
			-- (`PARTICIPANT_DISPATCHER.handle_page.nothing_queued',
			-- `dispatch_pending.wakes_untouched'); the violation unwound the
			-- drain with `is_dispatching' left True, and the dispatcher
			-- answered nothing again for the rest of the run - first turn
			-- answered, every turn after it silent, the server still
			-- serving. Measured, not reasoned:
			-- .eiffel-workflow/evidence/phase4-second-call-freeze.txt.
			--
			-- Nothing is lost to the silence: a bot's own answer is an event
			-- it would ignore anyway, and news from anyone ELSE rings on its
			-- own poster's turn, where no lock is passed and the wake is a
			-- plain asynchronous call that waits its turn.

	subscriber_count: INTEGER
		do
			Result := subscribers.count
		end

feature -- Status report

	is_subscribed (a_ticket: INTEGER): BOOLEAN
		do
			Result := subscribers.has (a_ticket)
		ensure
			definition: Result = subscribers_model.domain.has (a_ticket)
		end

	is_muted (a_ticket: INTEGER): BOOLEAN
			-- Is `a_ticket' the subscription `ring' passes over?
		do
			Result := a_ticket > 0 and then a_ticket = muted_ticket
		ensure
			definition: Result = (a_ticket > 0 and a_ticket = muted_ticket)
			never_when_none_muted: muted_ticket = 0 implies not Result
		end

feature -- Element change

	subscribe (a_subscriber: separate EVENT_SUBSCRIBER)
			-- Issue a fresh ticket (`last_ticket') for `a_subscriber'.
		do
			last_ticket := last_ticket + 1
			subscribers.force (a_subscriber, last_ticket)
			names.force (name_of (a_subscriber), last_ticket)
			if name_of (a_subscriber).same_string (Dispatcher_subscriber_name) then
				dispatcher_ticket := last_ticket
			end
		ensure
			fresh: not (old subscribers_model).domain.has (last_ticket)
			issued: last_ticket = old last_ticket + 1
			added: subscribers_model |=| (old subscribers_model).updated (last_ticket, name_of (a_subscriber))
			counts_unchanged: ring_count = old ring_count and status_count = old status_count
		end

	unsubscribe (a_ticket: INTEGER)
			-- Forget `a_ticket'; nothing happens for an unknown one.
		do
			subscribers.remove (a_ticket)
			names.remove (a_ticket)
		ensure
			removed: subscribers_model |=| (old subscribers_model).removed (a_ticket)
			counts_unchanged: ring_count = old ring_count and status_count = old status_count
		end

feature -- Basic operations

	ring (a_room_id: INTEGER_64)
			-- Room `a_room_id' has new events: wake every subscriber (asynchronously).
		require
			positive_room: a_room_id > 0
		do
			ring_count := ring_count + 1
			across subscribers as ic loop
				if not is_muted (@ic.key) then
					wake_one (ic, a_room_id)
				end
			end
		ensure
			counted: ring_count = old ring_count + 1
			subscribers_unchanged: subscribers_model |=| old subscribers_model
		end

	mute_dispatcher
			-- Pass the participant dispatcher's own subscription over in
			-- every `ring' until `unmute'. For the length of ONE post - the
			-- dispatcher's own answer - and no longer. Nothing happens when
			-- no dispatcher is subscribed.
		do
			muted_ticket := dispatcher_ticket
		ensure
			muted: muted_ticket = dispatcher_ticket
			subscribers_unchanged: subscribers_model |=| old subscribers_model
			counts_unchanged: ring_count = old ring_count and status_count = old status_count
		end

	unmute
			-- Ring everybody again.
		do
			muted_ticket := 0
		ensure
			none_muted: muted_ticket = 0
			subscribers_unchanged: subscribers_model |=| old subscribers_model
			counts_unchanged: ring_count = old ring_count and status_count = old status_count
		end

	ring_status (a_status: CHAT_STATUS)
			-- Hand an ephemeral notice to every subscriber; nothing is stored (DR-009).
		do
			status_count := status_count + 1
			across subscribers as ic loop
				notify_one (ic, a_status)
			end
		ensure
			counted: status_count = old status_count + 1
			subscribers_unchanged: subscribers_model |=| old subscribers_model
		end

feature -- Access (contract support)

	name_of (a_subscriber: separate EVENT_SUBSCRIBER): STRING_8
			-- `a_subscriber.subscriber_name' copied to this processor.
		do
			create Result.make_from_separate (a_subscriber.subscriber_name)
		ensure
			given: not Result.is_empty
		end

feature -- Constants

	Dispatcher_subscriber_name: STRING_8 = "dispatcher"
			-- `PARTICIPANT_DISPATCHER.subscriber_name'. The bus never holds a
			-- subscriber's type - a subscription is a ticket, not an object
			-- identity, and no contract here may touch another processor - so
			-- the one subscriber that answers by POSTING is known by the name
			-- it gives, copied on the way in. PARTICIPANTS_ASSAULT pins the
			-- two together.

feature {NONE} -- Implementation

	subscribers: HASH_TABLE [separate EVENT_SUBSCRIBER, INTEGER]

	names: HASH_TABLE [STRING_8, INTEGER]
			-- The same tickets, with the names the contracts speak of.

	wake_one (a_subscriber: separate EVENT_SUBSCRIBER; a_room_id: INTEGER_64)
			-- Asynchronous: returns as soon as the call is queued.
		require
			positive_room: a_room_id > 0
		do
			a_subscriber.wake (a_room_id)
		end

	notify_one (a_subscriber: separate EVENT_SUBSCRIBER; a_status: CHAT_STATUS)
		do
			a_subscriber.receive_status (a_status)
		end

invariant
	counts_non_negative: ring_count >= 0 and status_count >= 0 and last_ticket >= 0
	dispatcher_ticket_issued: dispatcher_ticket >= 0 and dispatcher_ticket <= last_ticket
	mute_is_the_dispatcher_or_none: muted_ticket = 0 or muted_ticket = dispatcher_ticket
	tickets_in_range: across subscribers as ic all @ic.key > 0 and @ic.key <= last_ticket end
	names_match: names.count = subscribers.count
	model_consistent: subscribers_model.count = subscribers.count

end
