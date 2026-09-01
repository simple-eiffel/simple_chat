note
	description: "[
		NOTIFIER over the Windows notification area (SHELL_TRAY,
		simple_shell): a balloon per notice - the sender head-cut to
		`Title_head_maximum', the snippet to `Body_head_maximum' - and
		the unread count on the tray tooltip: "(n) simple_chat" while
		n > 0, the plain "simple_chat" otherwise. When the shell refused
		the icon (`not tray.is_installed': no shell, a locked-down
		session) every operation degrades to silence, but the counts
		still hold exactly as NOTIFIER's contracts demand, so the
		presenter's unread law is provable with or without a tray.
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
			-- One balloon: who (head-cut to `Title_head_maximum'), and the start
			-- of what (head-cut to `Body_head_maximum'); silence, still counted,
			-- when the shell refused the icon.
		do
			notify_count := notify_count + 1
			if tray.is_installed then
				tray.balloon (head_of (a_sender, Title_head_maximum), head_of (a_snippet, Body_head_maximum))
			end
		ensure then
			unread_kept: unread = old unread
		end

	badge (a_count: INTEGER)
			-- "(n) simple_chat" on the tooltip while `a_count' > 0; the plain name at zero.
		local
			l_tip: STRING_32
		do
			unread := a_count
			if tray.is_installed then
				if a_count > 0 then
					create l_tip.make (Tooltip_base.count + 13)
					l_tip.append_character ('(')
					l_tip.append_string_general (a_count.out)
					l_tip.append_string_general (") ")
					l_tip.append (Tooltip_base)
					tray.set_tooltip (l_tip)
				else
					tray.set_tooltip (Tooltip_base)
				end
			end
		end

	clear
			-- The room came to the front: the plain name on the tooltip.
		do
			unread := 0
			if tray.is_installed then
				tray.set_tooltip (Tooltip_base)
			end
		end

feature -- Constants

	Title_head_maximum: INTEGER = 48
			-- What survives of a sender on a balloon title (SHELL_TRAY allows 63).

	Body_head_maximum: INTEGER = 200
			-- What survives of a snippet on a balloon body (SHELL_TRAY allows 255).

	Tooltip_base: STRING_32 = "simple_chat"
			-- The tooltip when nothing is unread; the suffix when something is.

feature {NONE} -- Head-cutting

	head_of (a_text: READABLE_STRING_GENERAL; a_maximum: INTEGER): STRING_32
			-- The first `a_maximum' characters of `a_text'; all of it when it fits.
		require
			positive: a_maximum > 0
		do
			create Result.make_from_string_general (a_text)
			if Result.count > a_maximum then
				Result.keep_head (a_maximum)
			end
		ensure
			bounded: Result.count <= a_maximum
			head: a_text.starts_with (Result)
			whole_when_short: a_text.count <= a_maximum implies Result.same_string_general (a_text)
		end

feature {NONE} -- Implementation

	tray: SHELL_TRAY

invariant
	unread_non_negative: unread >= 0
	notices_non_negative: notify_count >= 0

end
