note
	description: "[
		The cross-processor doorbell assault (Phase 4 Task 3): the runtime
		proof of the SCOOP design in approach.md section 8. One separate
		CHAT_API owns the service, the memory store and the EVENT_BUS on
		its own processor; this root plays the request handler. Each test
		reaches the API only through routines that take it as a separate
		argument, and only bytes come back (CHAT_REPLY.make_from_separate,
		decoded here with CHAT_JSON).

		Proved across processors:
		1. setup - the first admin, the room, a post, a page decoded here;
		2. an empty wait times out on its POLL_ALARM in about its seconds;
		3. a post rings the bus and wakes a waiting long-poll early;
		4. news posted before the subscribe is caught by the read step, so
		   an early wake is never lost (arm - check - wait);
		5. one ring fans out to every subscriber, and a waiter counts news
		   only for its own room;
		6. the dispatcher round trip - wake, dispatch_pending, pull - over
		   processors through DISPATCHER_HOST;
		7. the program exits: every helper is one-shot, so each processor
		   goes idle and the run ends by returning from `make'.

		Timing is measured with created-before/after SIMPLE_DATE_TIME
		pairs and asserted generously (scheduler slack).
	]"
	author: "Larry Rix"

class
	DOORBELL_ASSAULT

inherit
	CHAT_SHARED

create
	make

feature {NONE} -- Initialization

	make
		local
			l_started, l_finished: SIMPLE_DATE_TIME
		do
			print ("simple_chat doorbell assault (Phase 4 Task 3: SCOOP across processors)%N%N")
			create l_started.make_now
			passed := 0
			failed := 0
			create token.make_empty
			create codec.make

			run_test (agent test_1_setup_across_processors, "1 setup across processors (bootstrap, login, post, page)")
			run_test (agent test_2_empty_wait_times_out, "2 empty wait times out on the alarm")
			run_test (agent test_3_post_wakes_the_waiter_early, "3 a post wakes the waiter early")
			run_test (agent test_4_no_lost_wake, "4 no lost wake (arm-check catches pre-wait news)")
			run_test (agent test_5_ring_fan_out, "5 ring fan-out is room-scoped")
			run_test (agent test_6_dispatcher_round_trip, "6 dispatcher round trip over processors")

			create l_finished.make_now
			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed (" + l_started.seconds_between (l_finished).out + " s)%N")
			if failed > 0 then
				print ("TESTS FAILED%N")
			else
				print ("ALL TESTS PASSED%N")
			end
			print ("7 the program exits: returning from make; the runtime drains the remaining one-shot processors.%N")
		end

feature {NONE} -- Tests

	test_1_setup_across_processors
			-- Bootstrap the first admin (and the room) through the separate
			-- API, log in, post, and decode the page on this processor.
		local
			l_reply: CHAT_REPLY
		do
			l_reply := api_bootstrap (shared_api)
			assert ("bootstrap answers 201", l_reply.status = 201)
			assert ("bootstrap answers the member", l_reply.body.has_substring ("larry"))
			l_reply := api_login (shared_api)
			assert ("login answers 200", l_reply.status = 200)
			if attached codec.login_from_bytes (l_reply.body) as l_login then
				assert ("token is 64 characters", l_login.token.count = 64)
				assert ("member is larry", l_login.member.username.same_string ("larry") and not l_login.member.is_bot)
				token := l_login.token
			else
				assert ("login reply decodes", False)
			end
			l_reply := api_post (shared_api, {STRING_32} "the first doorbell message")
			assert ("post answers 201", l_reply.status = 201)
			if attached codec.event_from_bytes (l_reply.body) as l_event then
				assert ("event is stored in the main room", l_event.id > 0 and l_event.room_id = Room_main)
				top_id := l_event.id
			else
				assert ("post reply decodes", False)
			end
			l_reply := api_events (shared_api, 0)
			assert ("events answers 200 with one item", l_reply.status = 200 and l_reply.item_count = 1)
			if attached codec.page_from_bytes (l_reply.body) as l_page then
				assert ("page carries the post", l_page.events.count = 1 and l_page.last_id = top_id)
				assert ("body crossed intact", l_page.events.last.body.same_string ({STRING_32} "the first doorbell message"))
			else
				assert ("page decodes on the root", False)
			end
		end

	test_2_empty_wait_times_out
			-- Subscribe, confirm the page is empty, arm a 2 s alarm and wait:
			-- the wait ends by timeout in roughly 2 s with no news.
		local
			l_waiter: separate POLL_WAITER
			l_alarm: separate POLL_ALARM
			l_wait: POLL_WAIT
			l_ticket: INTEGER
			l_before, l_after: SIMPLE_DATE_TIME
			l_elapsed: INTEGER_64
		do
			create l_waiter.make (Room_main)
			l_ticket := api_subscribe (shared_api, l_waiter)
			assert ("subscribed", l_ticket > 0)
			assert ("no news after the cursor", api_events (shared_api, top_id).is_empty_page)
			create l_alarm.make (l_waiter, 2)
			start_alarm (l_alarm)
			create l_wait.make
			create l_before.make_now
			l_wait.wait_for (l_waiter)
			create l_after.make_now
			l_elapsed := l_before.seconds_between (l_after)
			assert ("timed out in roughly 2 s (took " + l_elapsed.out + " s)", l_elapsed >= 1 and l_elapsed <= 8)
			assert ("woke without news", not l_wait.woke_with_news)
			assert ("waiter is timed out", waiter_timed_out (l_waiter))
			assert ("waiter counted no news", waiter_news (l_waiter) = 0)
			assert ("no statuses were kept", l_wait.statuses_json.same_string ("[]"))
			api_unsubscribe (shared_api, l_ticket)
		end

	test_3_post_wakes_the_waiter_early
			-- A separate poster posts after ~1 s while a 10 s alarm is armed:
			-- the wait ends well before the alarm, with the news readable.
		local
			l_waiter: separate POLL_WAITER
			l_alarm: separate POLL_ALARM
			l_poster: separate DOORBELL_POSTER
			l_wait: POLL_WAIT
			l_ticket: INTEGER
			l_before, l_after: SIMPLE_DATE_TIME
			l_elapsed: INTEGER_64
			l_reply: CHAT_REPLY
		do
			create l_waiter.make (Room_main)
			l_ticket := api_subscribe (shared_api, l_waiter)
			assert ("subscribed", l_ticket > 0)
			assert ("no news before the poster", api_events (shared_api, top_id).is_empty_page)
			create l_alarm.make (l_waiter, 10)
			create l_poster.make (shared_api, token, Room_main, {STRING_32} "the doorbell rings", 1_000)
			start_alarm (l_alarm)
			start_poster (l_poster)
			create l_wait.make
			create l_before.make_now
			l_wait.wait_for (l_waiter)
			create l_after.make_now
			l_elapsed := l_before.seconds_between (l_after)
			assert ("woke well before the 10 s alarm (took " + l_elapsed.out + " s)", l_elapsed < 8)
			assert ("woke with news", l_wait.woke_with_news)
			l_reply := api_events (shared_api, top_id)
			assert ("the follow-up read carries the post", l_reply.status = 200 and l_reply.item_count >= 1)
			if attached codec.page_from_bytes (l_reply.body) as l_page then
				assert ("the posted body arrived", across l_page.events as e some e.body.same_string ({STRING_32} "the doorbell rings") end)
				top_id := l_page.last_id
			else
				assert ("wake page decodes on the root", False)
			end
			assert ("the poster's post was accepted", poster_status (l_poster) = 201)
			api_unsubscribe (shared_api, l_ticket)
		end

	test_4_no_lost_wake
			-- Post FIRST, then subscribe and read: the check step of the
			-- arm-check-wait choreography catches news that predates the
			-- wait, so no wake is ever lost to the race.
		local
			l_waiter: separate POLL_WAITER
			l_ticket: INTEGER
			l_since, l_posted: INTEGER_64
			l_reply: CHAT_REPLY
		do
			l_since := top_id
			l_reply := api_post (shared_api, {STRING_32} "early bird")
			assert ("post answers 201", l_reply.status = 201)
			if attached codec.event_from_bytes (l_reply.body) as l_event then
				l_posted := l_event.id
			else
				assert ("post reply decodes", False)
			end
			create l_waiter.make (Room_main)
			l_ticket := api_subscribe (shared_api, l_waiter)
			assert ("armed after the post", l_ticket > 0)
			l_reply := api_events (shared_api, l_since)
			assert ("the check step already carries the news", l_reply.status = 200 and l_reply.item_count >= 1)
			if attached codec.page_from_bytes (l_reply.body) as l_page then
				assert ("the pre-wait post is on the page", l_page.last_id = l_posted)
				top_id := l_page.last_id
			else
				assert ("check page decodes on the root", False)
			end
			api_unsubscribe (shared_api, l_ticket)
		end

	test_5_ring_fan_out
			-- One post rings every subscriber; a waiter counts news only for
			-- its own room, so the room-2 waiter is woken but newsless.
		local
			l_waiter_a, l_waiter_b, l_waiter_c: separate POLL_WAITER
			l_ticket_a, l_ticket_b, l_ticket_c: INTEGER
			l_reply: CHAT_REPLY
			i: INTEGER
			l_news_a, l_news_b, l_wakes_c: INTEGER
		do
			create l_waiter_a.make (Room_main)
			create l_waiter_b.make (Room_main)
			create l_waiter_c.make (Room_other)
			l_ticket_a := api_subscribe (shared_api, l_waiter_a)
			l_ticket_b := api_subscribe (shared_api, l_waiter_b)
			l_ticket_c := api_subscribe (shared_api, l_waiter_c)
			assert ("three subscriptions", l_ticket_a > 0 and l_ticket_b > 0 and l_ticket_c > 0)
			l_reply := api_post (shared_api, {STRING_32} "fan out")
			assert ("post answers 201", l_reply.status = 201)
			if attached codec.event_from_bytes (l_reply.body) as l_event then
				top_id := l_event.id
			end
			from
				i := 1
			until
				(l_news_a > 0 and l_news_b > 0 and l_wakes_c > 0) or i > 50
			loop
				l_news_a := waiter_news (l_waiter_a)
				l_news_b := waiter_news (l_waiter_b)
				l_wakes_c := waiter_wakes (l_waiter_c)
				if not (l_news_a > 0 and l_news_b > 0 and l_wakes_c > 0) then
					nap (100)
				end
				i := i + 1
			end
			assert ("both main-room waiters got news", l_news_a = 1 and l_news_b = 1)
			assert ("the room-2 waiter was woken by the ring", l_wakes_c > 0)
			assert ("but counted no news for its room", waiter_news (l_waiter_c) = 0)
			api_unsubscribe (shared_api, l_ticket_a)
			api_unsubscribe (shared_api, l_ticket_b)
			api_unsubscribe (shared_api, l_ticket_c)
		end

	test_6_dispatcher_round_trip
			-- DISPATCHER_HOST launches the dispatcher on its own processor;
			-- a post wakes it through the bus and it pulls the page from the
			-- API: its wake count grows and its cursor reaches the post.
		local
			l_host: DISPATCHER_HOST
			l_reply: CHAT_REPLY
			i: INTEGER
			l_wakes: INTEGER
			l_cursor: INTEGER_64
		do
			create l_host.make
			l_host.launch (shared_api)
			assert ("dispatcher launched", l_host.is_launched)
			if attached l_host.dispatcher as l_dispatcher then
				assert ("no wakes yet", dispatcher_wakes (l_dispatcher) = 0)
				l_reply := api_post (shared_api, {STRING_32} "dispatch me")
				assert ("post answers 201", l_reply.status = 201)
				if attached codec.event_from_bytes (l_reply.body) as l_event then
					top_id := l_event.id
				else
					assert ("post reply decodes", False)
				end
				from
					i := 1
				until
					(l_wakes > 0 and l_cursor >= top_id) or i > 100
				loop
					l_wakes := dispatcher_wakes (l_dispatcher)
					l_cursor := dispatcher_cursor (l_dispatcher, Room_main)
					if not (l_wakes > 0 and l_cursor >= top_id) then
						nap (100)
					end
					i := i + 1
				end
				assert ("the dispatcher was woken across processors", l_wakes > 0)
				assert ("its cursor advanced to the posted id", l_cursor = top_id)
			else
				assert ("dispatcher reference kept", False)
			end
		end

feature {NONE} -- The API across processors (each routine holds the API only for its call)

	api_bootstrap (a_api: separate CHAT_API): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.bootstrap_first_admin (Admin_username, Admin_display, Admin_password))
		end

	api_login (a_api: separate CHAT_API): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.login (Admin_login_name, Admin_password, Loopback))
		end

	api_events (a_api: separate CHAT_API; a_since_id: INTEGER_64): CHAT_REPLY
			-- The main room's page after `a_since_id', copied to this processor.
		require
			since_non_negative: a_since_id >= 0
		do
			create Result.make_from_separate (a_api.events (token, Room_main, a_since_id, Page_limit, Empty_array))
		end

	api_post (a_api: separate CHAT_API; a_body: STRING_32): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.post_message (token, Room_main, a_body))
		end

	api_subscribe (a_api: separate CHAT_API; a_waiter: separate POLL_WAITER): INTEGER
			-- The ticket, or 0 when refused.
		do
			a_api.subscribe (token, Room_main, a_waiter)
			Result := a_api.last_subscription
		ensure
			non_negative: Result >= 0
		end

	api_unsubscribe (a_api: separate CHAT_API; a_ticket: INTEGER)
		do
			a_api.unsubscribe (a_ticket)
		end

feature {NONE} -- Other processors (asynchronous commands and brief queries)

	start_alarm (a_alarm: separate POLL_ALARM)
			-- Asynchronous: the alarm sleeps on its own processor.
		do
			a_alarm.start
		end

	start_poster (a_poster: separate DOORBELL_POSTER)
			-- Asynchronous: the poster sleeps and posts on its own processor.
		do
			a_poster.run
		end

	waiter_news (a_waiter: separate POLL_WAITER): INTEGER
		do
			Result := a_waiter.news_count
		end

	waiter_wakes (a_waiter: separate POLL_WAITER): INTEGER
		do
			Result := a_waiter.wake_count
		end

	waiter_timed_out (a_waiter: separate POLL_WAITER): BOOLEAN
		do
			Result := a_waiter.is_timed_out
		end

	poster_status (a_poster: separate DOORBELL_POSTER): INTEGER
			-- Synchronous: queued behind `run', so it answers the post's status.
		do
			Result := a_poster.last_status
		end

	dispatcher_wakes (a_dispatcher: separate PARTICIPANT_DISPATCHER): INTEGER
		do
			Result := a_dispatcher.wake_count
		end

	dispatcher_cursor (a_dispatcher: separate PARTICIPANT_DISPATCHER; a_room_id: INTEGER_64): INTEGER_64
		do
			Result := a_dispatcher.cursor_of (a_room_id)
		end

feature {NONE} -- Harness

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run one test; any exception (contract or otherwise) fails it.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				print ("  PASS: " + a_name + "%N")
				passed := passed + 1
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			if attached (create {EXCEPTION_MANAGER}).last_exception as ex then
				if attached ex.description as d then
					print ("        " + d.to_string_8 + "%N")
				end
				if attached ex.recipient_name as r then
					print ("        in: " + r + " (" + ex.generator + ")%N")
				end
				if attached ex.trace as tr then
					print (tr.head (1500) + "%N")
				end
			end
			failed := failed + 1
			l_retried := True
			retry
		end

	assert (a_tag: STRING_8; a_condition: BOOLEAN)
			-- Raise unless `a_condition', so `run_test' records the failure.
		do
			if not a_condition then
				print ("        FAILED: " + a_tag + "%N")
				(create {EXCEPTIONS}).raise ("doorbell assault: " + a_tag)
			end
		end

	nap (a_milliseconds: INTEGER)
			-- Sleep here on the root, holding nothing.
		require
			positive: a_milliseconds > 0
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			l_env.sleep (a_milliseconds.to_integer_64 * 1_000_000)
		end

	passed, failed: INTEGER

	token: STRING_8
			-- The admin's session token, from the login answer alone.

	top_id: INTEGER_64
			-- The highest event id this assault has seen (its read cursor).

	codec: CHAT_JSON
			-- Decodes every reply on this processor.

feature {NONE} -- Constants

	Room_main: INTEGER_64 = 1
			-- The default room the bootstrap brings to exist.

	Room_other: INTEGER_64 = 2
			-- A room id no event carries: proves news counting is room-scoped.

	Page_limit: INTEGER = 50

	Empty_array: STRING_8 = "[]"

	Loopback: STRING_8 = "127.0.0.1"

	Admin_username: STRING_8 = "larry"

	Admin_login_name: STRING_32 = "larry"

	Admin_display: STRING_32 = "Larry"

	Admin_password: STRING_32 = "open sesame 42"

invariant
	counts_non_negative: passed >= 0 and failed >= 0
	cursor_non_negative: top_id >= 0

end
