note
	description: "NOTIFIER that remembers: the test double for CHAT_PRESENTER's unread law."
	author: "Larry Rix"

class
	MEMORY_NOTIFIER

inherit
	NOTIFIER

create
	make

feature {NONE} -- Initialization

	make
		do
			create notices.make (8)
		ensure
			quiet: notify_count = 0 and unread = 0
		end

feature -- Access

	unread: INTEGER

	notify_count: INTEGER
		do
			Result := notices.count
		end

	notices: ARRAYED_LIST [STRING_32]
			-- "<sender>: <snippet>" per notice, in order.

feature -- Basic operations

	notify (a_sender, a_snippet: READABLE_STRING_GENERAL)
		local
			l_line: STRING_32
		do
			create l_line.make_from_string_general (a_sender)
			l_line.append_string_general (": ")
			l_line.append_string_general (a_snippet)
			notices.extend (l_line)
		end

	badge (a_count: INTEGER)
		do
			unread := a_count
		end

	clear
		do
			unread := 0
		end

invariant
	unread_non_negative: unread >= 0

end
