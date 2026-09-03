note
	description: "[
		THE FREEZE (phase4/freeze). The window stopped for twenty seconds
		at a time after a few posts, and nothing in the client's own
		wiring was to blame: every GUI-side call on the inbox came back
		inside 2 ms while it happened. What stopped was the ROOT
		PROCESSOR'S ALLOCATOR.

		ISE's collector stops every thread of the system before it
		collects. A thread inside a plain `external "C inline"' call -
		which is what SIMPLE_WINHTTP.c_send is for the whole of a 25 s
		long poll - is where the runtime cannot see it and cannot stop
		it, so the collection waits for the call to come back and every
		other processor waits with it. The GUI thread therefore freezes
		at its next allocation - a string, an MML sequence in a
		postcondition, a shaped line - for the REST OF THE POLL.

		These two probes separate the two ways a processor can wait.
		EXECUTION_ENVIRONMENT.sleep is marked for the runtime and costs
		the GUI nothing; an UNMARKED C call is not, and costs the GUI the
		whole wait. THE FIX IS THE MARKER, and it landed upstream:
		SIMPLE_WINHTTP.c_send is `external "C blocking inline"' from
		0.1.1, so this client holds its 25 s doorbell open again and the
		root's allocator never notices.

		HOW THE PROBE MUST ALLOCATE, WHICH IS THE HARDER HALF. A burst
		that drops everything it allocates can be answered out of a free
		list the runtime already owns, and an allocator never made to
		collect can only be caught waiting for a collection by luck -
		whatever heap pressure the rest of the run happens to supply.
		Every burst here therefore KEEPS `Burst_kept' of what it makes,
		in a live set that grows for the length of the test, so the
		collector has real work and really does run. Measured, same
		source, same 25 s poll, only the library differing: against
		0.1.0 the live assault's stall went from 21,639 ms unhardened to
		25,144 ms hardened - the WHOLE poll rather than the part of it
		that coincided with a collection - and against 0.1.1 it is 6 ms.

		WHAT HARDENING DOES NOT BUY, and it is worth knowing which is
		which: it is NOT what stands between this suite and a false
		green. That is the RUN LOCATION. WIRING_ASSAULT finds the server
		exe by a path relative to the PROJECT ROOT, and from anywhere
		else - from inside F_code, say - the live assault SKIPs and
		passes on the skip, so the suite reports 188/0 ALL PASS against
		the very library that froze the window. Run it from the project
		root. See `.eiffel-workflow/evidence/phase4-freeze.txt', PART 2.
	]"
	author: "Larry Rix"

class
	FREEZE_ASSAULT

inherit
	TEST_SET_BASE

feature -- What a waiting processor costs the GUI

	test_an_eiffel_sleep_on_another_processor_never_stops_the_allocator
			-- A processor asleep through EXECUTION_ENVIRONMENT never holds the
			-- collector: the root allocates all the way through it.
		local
			l_probe: separate GC_PROBE
			l_worst: INTEGER_64
		do
			create l_probe.make
			launch_eiffel_sleeps (l_probe)
			l_worst := worst_allocation_burst (Probe_bursts, Probe_gap_ms)
			print ("    an Eiffel sleep of " + (Probe_waits * Probe_wait_ms).out + " ms on another processor: worst allocation on the root "
				+ l_worst.out + " ms%N")
			assert ("a processor asleep through EXECUTION_ENVIRONMENT leaves the root's allocator alone",
				l_worst <= Allocation_budget_ms)
		end

	test_an_unmarked_c_call_on_another_processor_stops_the_allocator
			-- The same wait, spent inside an UNMARKED external: the root's very next
			-- allocation waits for it. This is the freeze, in eleven lines, and it is
			-- kept because it is the reason the transport's own external must stay
			-- marked. ("Blocking" is now the name of the SAFE shape, so the unsafe one
			-- is named here for what it lacks.)
		local
			l_probe: separate GC_PROBE
			l_worst: INTEGER_64
		do
			create l_probe.make
			launch_c_sleeps (l_probe)
			l_worst := worst_allocation_burst (Probe_bursts, Probe_gap_ms)
			print ("    an unmarked C call of " + Probe_wait_ms.out + " ms on another processor: worst allocation on the root "
				+ l_worst.out + " ms%N")
			assert ("an unmarked C call of " + Probe_wait_ms.out + " ms stops the root's allocator for very nearly that long",
				l_worst >= Probe_wait_ms // 2)
		end

feature -- The GUI's frame, while a poller polls

	test_the_gui_keeps_its_frame_while_the_poller_polls
			-- THE RED-THEN-GREEN. A real EVENT_POLLER on its own SCOOP processor over
			-- a transport that waits the way the real one waits - inside C - while the
			-- root does everything the window's heartbeat does: allocate, pump the
			-- inbox, post a line. Every one of those must come back inside a frame.
			--
			-- `run' asks the server to hold the connection for the whole of
			-- {CHAT_CLIENT}.Max_wait_seconds, and the scripted wire holds it (capped at
			-- `Scripted_cap_seconds' so an assault stays short). That costs the root
			-- NOTHING, because the wait is spent inside an external the runtime has been
			-- told about: a collection runs while the poller waits. Take the marker off
			-- SLOW_HTTP_TRANSPORT.c_sleep, or off SIMPLE_WINHTTP.c_send, and this test
			-- goes red by seconds - which is exactly what it is for.
		local
			l_inbox: separate EVENT_INBOX
			l_host: separate SLOW_POLL_HOST
			l_transport: MEMORY_HTTP_TRANSPORT
			l_client: CHAT_CLIENT
			l_view: MEMORY_CHAT_VIEW
			l_notifier: MEMORY_NOTIFIER
			l_presenter: CHAT_PRESENTER
			l_env: EXECUTION_ENVIRONMENT
			l_endpoint: CHAT_ENDPOINT
			l_login: CHAT_RESULT [CHAT_MEMBER]
			l_live: ARRAYED_LIST [STRING_8]
			i: INTEGER
			t0, l_span, l_worst_alloc, l_worst_pump, l_worst_send, l_worst: INTEGER_64
		do
			create l_live.make (Frames * Burst_kept)
			create l_transport.make
			create l_endpoint.make (Loopback_url)
			create l_client.make (l_transport, l_endpoint)
			l_transport.script (200, Login_reply)
			l_login := l_client.login ("larry", {STRING_32} "correct horse battery staple")
			check logged_in: l_client.is_logged_in end
			create l_view.make
			create l_notifier.make
			create l_presenter.make (l_client, l_view, l_notifier)
			create l_inbox.make
			create l_host.make (Scripted_cap_seconds)
			attach_inbox (l_host, l_inbox)
			l_presenter.open_room (1, 0, l_inbox)
			launch_poll (l_host)
			create l_env
			from
				i := 1
			until
				i > Frames
			loop
				t0 := now_ms
				burn_a_frames_worth_of_memory (l_live)
				l_span := now_ms - t0
				if l_span > l_worst_alloc then
					l_worst_alloc := l_span
				end
				t0 := now_ms
				l_presenter.pump
				l_span := now_ms - t0
				if l_span > l_worst_pump then
					l_worst_pump := l_span
				end
				t0 := now_ms
				l_presenter.send ({STRING_32} "a line typed while the poller polls")
				l_span := now_ms - t0
				if l_span > l_worst_send then
					l_worst_send := l_span
				end
				l_env.sleep (Frame_gap_ms.to_integer_64 * 1_000_000)
				i := i + 1
			variant
				Frames + 1 - i
			end
			stop_inbox (l_inbox)
			check kept_them_alive: l_live.count = Frames * Burst_kept end
			l_worst := l_worst_alloc.max (l_worst_pump.max (l_worst_send))
			print ("    " + Frames.out + " frames beside a live poller: worst allocation " + l_worst_alloc.out
				+ " ms, worst pump " + l_worst_pump.out + " ms, worst send " + l_worst_send.out + " ms%N")
			assert ("no allocation on the GUI's own processor waited on the poller", l_worst_alloc <= Frame_budget_ms)
			assert ("no pump of the inbox waited on the poller", l_worst_pump <= Frame_budget_ms)
			assert ("no post waited on the poller", l_worst_send <= Frame_budget_ms)
			assert ("nothing the GUI thread does costs more than a frame", l_worst <= Frame_budget_ms)
		end

feature {NONE} -- The poller's processor (each a short, separate call)

	attach_inbox (a_host: separate SLOW_POLL_HOST; a_inbox: separate EVENT_INBOX)
			-- Give the host its inbox; one short call, as CLIENT_APP does.
		do
			a_host.set_inbox (a_inbox)
		end

	launch_poll (a_host: separate SLOW_POLL_HOST)
			-- Start the loop; asynchronous, no argument being a reference this processor owns.
		do
			a_host.poll (1, 0)
		end

	stop_inbox (a_inbox: separate EVENT_INBOX)
			-- End the poller's loop, as CHAT_PRESENTER.close_room does.
		do
			a_inbox.stop
		ensure
			stopped: a_inbox.is_stopped
		end

feature {NONE} -- A frame's worth of rubbish

	burn_a_frames_worth_of_memory (a_live: ARRAYED_LIST [STRING_8])
			-- Allocate what a heartbeat allocates - strings, and the MML sequences its
			-- own postconditions build - and nothing else, keeping `Burst_kept' of them
			-- in `a_live' so the heap grows and the collector has something to mark. A
			-- burst that takes a second took it inside the runtime, not in this
			-- project's code.
		local
			l_junk: ARRAYED_LIST [STRING_8]
			k: INTEGER
		do
			create l_junk.make (Burst_strings)
			from
				k := 1
			until
				k > Burst_strings
			loop
				l_junk.extend (create {STRING_8}.make_filled ('x', Burst_string_bytes))
				if k <= Burst_kept then
					a_live.extend (l_junk.last)
				end
				k := k + 1
			variant
				Burst_strings + 1 - k
			end
		ensure
			kept_a_share: a_live.count = old a_live.count + Burst_kept
		end

feature -- Constants

	Frames: INTEGER = 60
			-- 60 x 100 ms = 6 s: three whole scripted polls.

	Frame_gap_ms: INTEGER = 100

	Frame_budget_ms: INTEGER_64 = 50
			-- What the window can afford to spend in one call and still draw.

	Scripted_cap_seconds: INTEGER = 2
			-- However long the poller asks for, the scripted wire waits no longer than
			-- this - so an assault that would otherwise take 25 s takes 2.

	Loopback_url: STRING_8 = "http://127.0.0.1:8080"

	Login_reply: STRING_8 = "{%"token%":%"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855%",%"member%":{%"id%":5,%"username%":%"larry%",%"display_name%":%"Larry%",%"is_admin%":true,%"is_bot%":false}}"

feature {NONE} -- The probe's processor (each a short, separate call)

	launch_eiffel_sleeps (a_probe: separate GC_PROBE)
			-- Start the sleeps; asynchronous, no argument being a reference this processor owns.
		do
			a_probe.run_eiffel_sleeps (Probe_waits, Probe_wait_ms)
		end

	launch_c_sleeps (a_probe: separate GC_PROBE)
			-- Start the C waits; asynchronous, for the same reason.
		do
			a_probe.run_c_sleeps (Probe_waits, Probe_wait_ms)
		end

feature {NONE} -- The root's own allocator

	worst_allocation_burst (a_bursts, a_gap_ms: INTEGER): INTEGER_64
			-- Allocate `a_bursts' times, `a_gap_ms' apart, and answer the longest one
			-- in milliseconds. Nothing here touches another processor: a burst that
			-- takes a second took it inside the runtime, waiting for a collection that
			-- cannot start. `Burst_kept' of every burst is KEPT - see the class note:
			-- without a growing live set the runtime need never collect, and a probe
			-- that never provokes a collection cannot catch one being blocked.
		require
			positive: a_bursts > 0 and a_gap_ms > 0
		local
			l_env: EXECUTION_ENVIRONMENT
			l_live: ARRAYED_LIST [STRING_8]
			l_junk: ARRAYED_LIST [STRING_8]
			i, k: INTEGER
			t0, l_span: INTEGER_64
		do
			create l_env
			create l_live.make (a_bursts * Burst_kept)
			from
				i := 1
			until
				i > a_bursts
			loop
				t0 := now_ms
				create l_junk.make (Burst_strings)
				from
					k := 1
				until
					k > Burst_strings
				loop
					l_junk.extend (create {STRING_8}.make_filled ('x', Burst_string_bytes))
					if k <= Burst_kept then
							-- A live set that keeps growing, so the collector has
							-- something to mark and cannot answer every burst out
							-- of a free list it already owns.
						l_live.extend (l_junk.last)
					end
					k := k + 1
				variant
					Burst_strings + 1 - k
				end
				l_span := now_ms - t0
				if l_span > Result then
					Result := l_span
				end
				l_env.sleep (a_gap_ms.to_integer_64 * 1_000_000)
				i := i + 1
			variant
				a_bursts + 1 - i
			end
			check kept_them_alive: l_live.count = a_bursts * Burst_kept end
		ensure
			non_negative: Result >= 0
		end

	now_ms: INTEGER_64
			-- Milliseconds off the machine's high-resolution counter.
		external
			"C inline use <windows.h>"
		alias
			"LARGE_INTEGER c, f; QueryPerformanceCounter(&c); QueryPerformanceFrequency(&f); return (EIF_INTEGER_64) ((c.QuadPart * 1000) / f.QuadPart);"
		end

feature -- Constants

	Probe_waits: INTEGER = 3
			-- Waits the probe's processor makes.

	Probe_wait_ms: INTEGER = 3000
			-- How long each of them lasts.

	Probe_bursts: INTEGER = 120
			-- Allocation bursts the root makes while that happens.

	Probe_gap_ms: INTEGER = 100
			-- 120 x 100 ms = 12 s, four times the probe's whole wait.

	Burst_strings: INTEGER = 2_000

	Burst_string_bytes: INTEGER = 1_024
			-- 2 MiB a burst: enough that the collector runs many times over.

	Burst_kept: INTEGER = 200
			-- 200 KiB of every burst is kept alive, so the heap grows and the collector
			-- has real work to do. An allocator that is never asked to collect can only
			-- be caught waiting for one by luck: unhardened, this probe caught 21,639 ms
			-- of a 25,144 ms stall, and only because the rest of the run happened to
			-- supply the pressure.

	Allocation_budget_ms: INTEGER_64 = 250
			-- One heartbeat. An allocation that costs more than a frame has stopped the window.

end
