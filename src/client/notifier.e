note
	description: "[
		How the client gets the member's attention when the room is not in
		front: a notice per message and a running unread count. TRAY_NOTIFIER
		(apps/client) does it with SHELL_TRAY; MEMORY_NOTIFIER records it.
	]"
	author: "Larry Rix"

deferred class
	NOTIFIER

feature -- Access

	unread: INTEGER
			-- Messages not yet seen.
		deferred
		ensure
			non_negative: Result >= 0
		end

	notify_count: INTEGER
			-- Notices raised so far.
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Basic operations

	notify (a_sender, a_snippet: READABLE_STRING_GENERAL)
			-- One notice: who, and the start of what.
		require
			named: not a_sender.is_empty
		deferred
		ensure
			counted: notify_count = old notify_count + 1
		end

	badge (a_count: INTEGER)
			-- The unread count as shown.
		require
			non_negative: a_count >= 0
		deferred
		ensure
			set: unread = a_count
			notices_unchanged: notify_count = old notify_count
		end

	clear
			-- The room came to the front.
		deferred
		ensure
			cleared: unread = 0
			notices_unchanged: notify_count = old notify_count
		end

end
