note
	description: "[
		Something the bus wakes: a live stream, or the participant
		dispatcher. The bus never hands over events - it says which room
		has news, and the subscriber pulls what it has not seen from the
		store (the doorbell pattern). Ephemeral statuses are handed over,
		because they exist nowhere else.
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

	receive_status (a_status: CHAT_STATUS)
			-- An ephemeral notice for `a_status.room_id'.
		deferred
		end

end
