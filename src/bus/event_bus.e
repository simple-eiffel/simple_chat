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

feature -- Element change

	subscribe (a_subscriber: separate EVENT_SUBSCRIBER)
			-- Issue a fresh ticket (`last_ticket') for `a_subscriber'.
		do
			last_ticket := last_ticket + 1
			subscribers.force (a_subscriber, last_ticket)
			names.force (name_of (a_subscriber), last_ticket)
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
				wake_one (ic, a_room_id)
			end
		ensure
			counted: ring_count = old ring_count + 1
			subscribers_unchanged: subscribers_model |=| old subscribers_model
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
	tickets_in_range: across subscribers as ic all @ic.key > 0 and @ic.key <= last_ticket end
	names_match: names.count = subscribers.count
	model_consistent: subscribers_model.count = subscribers.count

end
