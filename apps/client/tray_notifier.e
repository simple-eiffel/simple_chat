note
	description: "[
		NOTIFIER over the Windows notification area: a balloon per notice
		unless the window is in front, the unread count on the tray
		tooltip. Needs SHELL_TRAY in simple_shell (dependency task); the
		client target compiles once it lands.
	]"
	author: "Larry Rix"

class
	TRAY_NOTIFIER

inherit
	NOTIFIER

create
	make

feature {NONE} -- Initialization

	make (a_tray: SHELL_TRAY)
		do
			tray := a_tray
		ensure
			set: tray = a_tray
			quiet: notify_count = 0 and unread = 0
		end

feature -- Access

	unread: INTEGER

	notify_count: INTEGER

feature -- Basic operations

	notify (a_sender, a_snippet: READABLE_STRING_GENERAL)
		do
			notify_count := notify_count + 1
			-- Implementation in Phase 4: tray.balloon (title <= 48 chars, body <= 200 chars)
		end

	badge (a_count: INTEGER)
		do
			unread := a_count
			-- Implementation in Phase 4: tray.set_tooltip ("(" + a_count.out + ") simple_chat")
		end

	clear
		do
			unread := 0
			-- Implementation in Phase 4: tray.set_tooltip ("simple_chat")
		end

feature {NONE} -- Implementation

	tray: SHELL_TRAY

invariant
	unread_non_negative: unread >= 0
	notices_non_negative: notify_count >= 0

end
