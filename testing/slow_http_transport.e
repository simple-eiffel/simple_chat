note
	description: "[
		An HTTP_TRANSPORT that waits the way the real one waits: inside a
		C call marked `blocking', exactly as SIMPLE_WINHTTP.c_send is
		marked since 0.1.1. It reads `seconds' out of the long-poll's own
		URL, waits that long (capped by `cap_seconds' so an assault stays
		short) and answers an empty page - so a poller that asks for a
		25 s wait spends 25 s (capped) in C, and one that asks for none
		spends none. A POST to /login is answered at once with a
		well-formed reply, which is how the host's client gets a session.

		WHY THE MARKER IS ON `c_sleep', AND WHY IT HAD TO GO ON. Until
		2026-09-02 this fixture's Sleep was a plain `external "C inline"',
		because the transport it doubled was one too and the assault's job
		was to reproduce that defect. simple_winhttp 0.1.1 fixed the real
		one. A fixture that kept the old shape would have gone on failing
		the restored 25 s poll (1,481 ms, measured) FOR A REASON THAT IS
		THE FIXTURE'S AND NOT THE PRODUCT'S - a double telling the truth
		about code that no longer exists. It now waits the way a fixed
		transport waits, so what the assault measures is EVENT_POLLER.
		The unmarked shape has not been thrown away: GC_PROBE still holds
		it, beside the marked one, as the law's own evidence.

		Nothing here is a double for the network: it is a double for THE
		SHAPE OF THE WAIT, which is the only thing the freeze ever
		depended on.
	]"
	author: "Larry Rix"

class
	SLOW_HTTP_TRANSPORT

inherit
	HTTP_TRANSPORT

create
	make

feature {NONE} -- Initialization

	make (a_cap_seconds: INTEGER)
			-- A transport that never waits longer than `a_cap_seconds' in one exchange,
			-- however long the caller asked for.
		require
			positive: a_cap_seconds > 0
		do
			cap_seconds := a_cap_seconds
		ensure
			set: cap_seconds = a_cap_seconds
			nothing_sent: exchange_count = 0
			nothing_waited: longest_wait_ms = 0
		end

feature -- Access

	exchange_count: INTEGER

	cap_seconds: INTEGER
			-- The most one exchange may spend inside C.

	longest_wait_ms: INTEGER
			-- The longest single wait spent inside C so far.

feature -- Basic operations

	send (a_method, a_url: READABLE_STRING_8; a_headers: HASH_TABLE [STRING_8, STRING_8]; a_body: detachable READABLE_STRING_8;
			a_timeout_seconds: INTEGER): HTTP_REPLY
			-- A login answered at once; anything else waited out for as long as the URL's
			-- own `seconds' asks (capped), then answered with an empty page.
		local
			l_wait: INTEGER
		do
			exchange_count := exchange_count + 1
			if a_url.has_substring ("/login") then
				create Result.make (200, Login_reply)
			else
				l_wait := seconds_asked (a_url).min (cap_seconds)
				if l_wait > 0 then
					c_sleep (l_wait * 1000)
					if l_wait * 1000 > longest_wait_ms then
						longest_wait_ms := l_wait * 1000
					end
				end
				create Result.make (200, Empty_page)
			end
		end

feature -- Validation (contract support)

	seconds_asked (a_url: READABLE_STRING_8): INTEGER
			-- The value of the URL's `seconds=' query, 0 when it carries none.
		local
			i: INTEGER
			l_digits: STRING_8
		do
			i := a_url.substring_index (Seconds_key, 1)
			if i > 0 then
				create l_digits.make (4)
				from
					i := i + Seconds_key.count
				until
					i > a_url.count or else not a_url [i].is_digit
				loop
					l_digits.append_character (a_url [i])
					i := i + 1
				variant
					a_url.count + 1 - i
				end
				if l_digits.is_integer then
					Result := l_digits.to_integer
				end
			end
		ensure
			non_negative: Result >= 0
		end

feature -- Constants

	Seconds_key: STRING_8 = "seconds="

	Empty_page: STRING_8 = "{%"events%":[],%"statuses%":[]}"

	Login_reply: STRING_8 = "{%"token%":%"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855%",%"member%":{%"id%":5,%"username%":%"larry%",%"display_name%":%"Larry%",%"is_admin%":true,%"is_bot%":false}}"

feature {NONE} -- Externals

	c_sleep (a_milliseconds: INTEGER)
			-- Wait inside C, MARKED `blocking' exactly as SIMPLE_WINHTTP.c_send is
			-- (0.1.1): the runtime is told this thread has left Eiffel, so a collection
			-- may run while it waits and no other processor is stopped behind it.
		external
			"C blocking inline use <windows.h>"
		alias
			"Sleep((DWORD) $a_milliseconds);"
		end

invariant
	positive_cap: cap_seconds > 0
	non_negative_wait: longest_wait_ms >= 0

end
