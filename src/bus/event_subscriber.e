note
	description: "[
		Something the bus wakes: a long-poll's waiter, or the participant
		dispatcher. The bus never hands over events - it says which room
		has news, and the subscriber pulls what it has not seen from the
		store (the doorbell pattern). Ephemeral statuses are handed over,
		because they exist nowhere else.

		SCOOP (D1): subscribers live on their own processors; the bus holds
		them as `separate' and `wake' / `receive_status' are asynchronous
		commands, so a poster never waits for a subscriber and a subscriber
		never runs two wakes at once. A status arrives as a separate object
		and is copied on the way in.
	]"
	author: "Larry Rix"

deferred class
	EVENT_SUBSCRIBER

feature -- Access

	subscriber_name: STRING_8
			-- For logs.
		deferred
		ensure
			given: not Result.is_empty
		end

	wake_count: INTEGER
			-- How many times `wake' has been called.
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Basic operations

	wake (a_room_id: INTEGER_64)
			-- Room `a_room_id' has new events.
		require
			positive_room: a_room_id > 0
		deferred
		ensure
			counted: wake_count = old wake_count + 1
		end

	receive_status (a_status: separate CHAT_STATUS)
			-- An ephemeral notice for `a_status.room_id' (copied; the argument belongs to the bus's processor).
		deferred
		ensure
			not_a_wake: wake_count = old wake_count
		end

end
