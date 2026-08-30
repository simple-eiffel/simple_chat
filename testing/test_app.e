note
	description: "Assault runner for simple_chat."
	author: "Larry Rix"

class
	TEST_APP

create
	make

feature {NONE} -- Initialization

	make
		local
			t: CHAT_ASSAULT
			s: TEST_SCOOP_CONSUMER
		do
			print ("simple_chat assault (Phase 1: contracts + skeletal tests)%N%N")
			passed := 0
			failed := 0
			create t
			create s

			print ("=== DOMAIN DATA ===%N")
			run_test (agent t.test_user_creation_and_storage_id, "user_creation_and_storage_id")
			run_test (agent t.test_username_rules, "username_rules")
			run_test (agent t.test_display_name_rejects_bidi_controls_and_blank, "display_name_rejects_bidi_controls_and_blank")
			run_test (agent t.test_result_success_xor_error, "result_success_xor_error")
			run_test (agent t.test_bot_event_carries_marker, "bot_event_carries_marker")
			run_test (agent t.test_session_fields, "session_fields")

			print ("=== CONTRACT-SUPPORT ENGINES ===%N")
			run_test (agent t.test_password_hasher_round_trip, "password_hasher_round_trip")
			run_test (agent t.test_session_issuer_token_shape, "session_issuer_token_shape")
			run_test (agent t.test_registry_register_and_find, "registry_register_and_find")
			run_test (agent t.test_null_shaper_honours_limit, "null_shaper_honours_limit")
			run_test (agent t.test_null_and_mock_participants, "null_and_mock_participants")
			run_test (agent t.test_config_defaults_and_public_flag, "config_defaults_and_public_flag")
			run_test (agent t.test_memory_store_models_start_empty, "memory_store_models_start_empty")
			run_test (agent t.test_memory_sink_counts_bytes, "memory_sink_counts_bytes")
			run_test (agent t.test_caddyfile_targets_localhost, "caddyfile_targets_localhost")

			print ("=== THICK CLIENT STACK (intent-v3) ===%N")
			run_test (agent t.test_poll_waiter_counts_only_its_room, "poll_waiter_counts_only_its_room")
			run_test (agent t.test_event_bus_tickets, "event_bus_tickets")
			run_test (agent t.test_sse_stream_delivers_in_order, "sse_stream_delivers_in_order")
			run_test (agent t.test_event_json_round_trip, "event_json_round_trip")
			run_test (agent t.test_client_login_sends_bearer_never_in_url, "client_login_sends_bearer_never_in_url")
			run_test (agent t.test_poller_cursor_and_drain_laws, "poller_cursor_and_drain_laws")
			run_test (agent t.test_presenter_unread_and_foreground_law, "presenter_unread_and_foreground_law")
			run_test (agent t.test_locator_prefers_live_local_then_standby, "locator_prefers_live_local_then_standby")

			print ("=== SCOOP CONSUMER ===%N")
			run_test (agent s.test_scoop_compatibility, "scoop_compatibility")

			print ("=== TODO: PHASE 5 (skeletal) ===%N")
			run_test (agent t.test_post_message_appends_and_rings, "post_message_appends_and_rings (skeletal)")
			run_test (agent t.test_doorbell_no_loss_under_concurrency, "doorbell_no_loss_under_concurrency (skeletal)")
			run_test (agent t.test_dispatcher_ignores_bots_and_answers_once, "dispatcher_ignores_bots_and_answers_once (skeletal)")
			run_test (agent t.test_tool_refuses_unsafe_argument, "tool_refuses_unsafe_argument (skeletal)")
			run_test (agent t.test_sse_replays_since_then_live, "sse_replays_since_then_live (skeletal)")
			run_test (agent t.test_long_poll_returns_within_deadline, "long_poll_returns_within_deadline (skeletal)")
			run_test (agent t.test_sw_view_renders_hebrew_and_marker, "sw_view_renders_hebrew_and_marker (skeletal)")
			run_test (agent t.test_log_never_contains_secrets, "log_never_contains_secrets (skeletal)")

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")
			if failed > 0 then
				print ("TESTS FAILED%N")
			else
				print ("ALL TESTS PASSED%N")
			end
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

	passed: INTEGER
	failed: INTEGER

end
