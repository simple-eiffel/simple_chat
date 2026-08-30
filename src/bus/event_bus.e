note
	description: "[
		In-process fan-out, thread-safe: `ring' says a room has news;
		`ring_status' hands an ephemeral notice to every subscriber. The
		subscriber set is snapshotted under the lock and released before
		any subscriber is called (intent-v2 Q2): a slow subscriber never
		stalls a poster. A subscriber that raises is unsubscribed and
		logged, never retried. Outermost lock in the order store < limiter < bus.
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
			create lock.make
		ensure
			none: subscribers_model.is_empty
			nothing_rung: ring_count = 0 and status_count = 0
		end

feature -- Model Queries (for MML postconditions)

	subscribers_model: MML_SET [EVENT_SUBSCRIBER]
		do
			create Result
			across subscribers as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = subscribers.count
		end

feature -- Access

	ring_count: INTEGER
			-- Rings so far.

	status_count: INTEGER
			-- Statuses so far.

	subscriber_count: INTEGER
		do
			Result := subscribers.count
		end

feature -- Element change

	subscribe (a_subscriber: EVENT_SUBSCRIBER)
		require
			not_yet: not subscribers_model.has (a_subscriber)
		do
			-- Implementation in Phase 4 (under `lock')
		ensure
			added: subscribers_model |=| ((old subscribers_model) & a_subscriber)
		end

	unsubscribe (a_subscriber: EVENT_SUBSCRIBER)
		require
			present: subscribers_model.has (a_subscriber)
		do
			-- Implementation in Phase 4 (under `lock')
		ensure
			removed: subscribers_model |=| ((old subscribers_model) / a_subscriber)
		end

feature -- Basic operations

	ring (a_room_id: INTEGER_64)
			-- Room `a_room_id' has new events: wake every subscriber.
		require
			positive_room: a_room_id > 0
		do
			-- Implementation in Phase 4: snapshot under lock, release, wake each
		ensure
			counted: ring_count = old ring_count + 1
			subscribers_unchanged: subscribers_model |=| old subscribers_model
		end

	ring_status (a_status: CHAT_STATUS)
			-- Hand an ephemeral notice to every subscriber; nothing is stored (DR-009).
		do
			-- Implementation in Phase 4
		ensure
			counted: status_count = old status_count + 1
			subscribers_unchanged: subscribers_model |=| old subscribers_model
		end

feature {NONE} -- Implementation

	subscribers: ARRAYED_LIST [EVENT_SUBSCRIBER]
			-- Reference comparison: the same object subscribes once.

	lock: MUTEX

invariant
	counts_non_negative: ring_count >= 0 and status_count >= 0
	reference_semantics: not subscribers.object_comparison
	model_consistent: subscribers_model.count = subscribers.count

end
