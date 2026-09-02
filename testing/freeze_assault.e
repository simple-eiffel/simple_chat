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
		the GUI nothing; a blocking C call is not, and costs the GUI the
		whole wait. That is why the fix is a SLICE: no exchange this
		client makes may sit in C for longer than the GUI can afford to
		wait for a collection.
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

	test_a_blocking_c_call_on_another_processor_stops_the_allocator
			-- The same wait, spent inside an unmarked external: the root's very next
			-- allocation waits for it. This is the freeze, in eleven lines.
		local
			l_probe: separate GC_PROBE
			l_worst: INTEGER_64
		do
			create l_probe.make
			launch_c_sleeps (l_probe)
			l_worst := worst_allocation_burst (Probe_bursts, Probe_gap_ms)
			print ("    a blocking C call of " + Probe_wait_ms.out + " ms on another processor: worst allocation on the root "
				+ l_worst.out + " ms%N")
			assert ("a blocking C call of " + Probe_wait_ms.out + " ms stops the root's allocator for very nearly that long",
				l_worst >= Probe_wait_ms // 2)
		end

feature -- The GUI's frame, while a poller polls

	test_the_gui_keeps_its_frame_while_the_poller_polls
			-- THE RED-THEN-GREEN. A real EVENT_POLLER on its own SCOOP processor over
			-- a transport that waits the way the real one waits - inside C - while the
			-- root does everything the window's heartbeat does: allocate, pump the
			-- inbox, post a line. Every one of those must come back inside a frame.
			--
			-- Ask the server to hold the connection for 25 s (what `run' did) and the
			-- root's allocator stops for as long as the exchange lasts. Ask for an
			-- answer now and wait between polls where the runtime can see you, and it
			-- never stops at all.
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
			i: INTEGER
			t0, l_span, l_worst_alloc, l_worst_pump, l_worst_send, l_worst: INTEGER_64
		do
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
				burn_a_frames_worth_of_memory
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

	burn_a_frames_worth_of_memory
			-- Allocate what a heartbeat allocates - strings, and the MML sequences its
			-- own postconditions build - and nothing else. A burst that takes a second
			-- took it inside the runtime, not in this project's code.
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
				k := k + 1
			variant
				Burst_strings + 1 - k
			end
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
			-- takes a second took it inside the runtime.
		require
			positive: a_bursts > 0 and a_gap_ms > 0
		local
			l_env: EXECUTION_ENVIRONMENT
			l_junk: ARRAYED_LIST [STRING_8]
			i, k: INTEGER
			t0, l_span: INTEGER_64
		do
			create l_env
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

	Burst_strings: INTEGER = 200

	Burst_string_bytes: INTEGER = 1024
			-- 200 KiB a burst: enough that the collector runs many times over.

	Allocation_budget_ms: INTEGER_64 = 250
			-- One heartbeat. An allocation that costs more than a frame has stopped the window.

end
