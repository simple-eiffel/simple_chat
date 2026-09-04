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
			p: PARTICIPANTS_ASSAULT
		do
			print ("simple_chat assault (Phase 1: contracts + skeletal tests)%N%N")
			passed := 0
			failed := 0
			create t
			create s
			create p

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
			run_test (agent t.test_web_stream_sink_over_mock_response, "web_stream_sink_over_mock_response")
			run_test (agent t.test_sse_stream_over_web_sink, "sse_stream_over_web_sink")
			run_test (agent t.test_client_address_door_rule, "client_address_door_rule")
			run_test (agent t.test_event_json_round_trip, "event_json_round_trip")

			print ("=== CLIENT (Phase 1b) ===%N")
			run_test (agent (create {CLIENT_ASSAULT}).test_client_login_sends_bearer_never_in_url, "client_login_sends_bearer_never_in_url")
			run_test (agent (create {CLIENT_ASSAULT}).test_token_never_in_url_or_body_across_all_requests, "token_never_in_url_or_body_across_all_requests")
			run_test (agent (create {CLIENT_ASSAULT}).test_wait_zero_seconds_uses_five_second_timeout, "wait_zero_seconds_uses_five_second_timeout")
			run_test (agent (create {CLIENT_ASSAULT}).test_login_never_raises_on_hostile_replies, "login_never_raises_on_hostile_replies")
			run_test (agent (create {CLIENT_ASSAULT}).test_post_message_echo_for_another_room_is_refused, "post_message_echo_for_another_room_is_refused")
			run_test (agent (create {CLIENT_ASSAULT}).test_post_image_puts_the_bytes_on_the_wire_and_the_rest_in_headers, "post_image_puts_the_bytes_on_the_wire_and_the_rest_in_headers")
			run_test (agent (create {CLIENT_ASSAULT}).test_post_image_refuses_an_echo_that_is_not_this_rooms_image, "post_image_refuses_an_echo_that_is_not_this_rooms_image")
			run_test (agent (create {CLIENT_ASSAULT}).test_post_image_carries_hebrew_and_an_emoji_through_ascii_headers, "post_image_carries_hebrew_and_an_emoji_through_ascii_headers")
			run_test (agent (create {CLIENT_ASSAULT}).test_header_text_round_trips_and_tolerates_a_hand_made_value, "header_text_round_trips_and_tolerates_a_hand_made_value")
			run_test (agent (create {CLIENT_ASSAULT}).test_session_handed_to_the_pollers_client, "session_handed_to_the_pollers_client")
			run_test (agent (create {CLIENT_ASSAULT}).test_logout_on_transport_failure_logs_out, "logout_on_transport_failure_logs_out")
			run_test (agent (create {CLIENT_ASSAULT}).test_page_result_refuses_foreign_room_non_ascending_and_hostile_fields, "page_result_refuses_foreign_room_non_ascending_and_hostile_fields")
			run_test (agent (create {CLIENT_ASSAULT}).test_members_roster_success_and_hostile, "members_roster_success_and_hostile")
			run_test (agent (create {CLIENT_ASSAULT}).test_hostile_urls_refused_loopbacks_accepted, "hostile_urls_refused_loopbacks_accepted")
			run_test (agent (create {CLIENT_ASSAULT}).test_endpoint_secure_by_construction_and_config_server_list, "endpoint_secure_by_construction_and_config_server_list")
			run_test (agent (create {CLIENT_ASSAULT}).test_locator_prefers_live_local_then_standby, "locator_prefers_live_local_then_standby")
			run_test (agent (create {CLIENT_ASSAULT}).test_locator_with_no_server_configured, "locator_with_no_server_configured")
			run_test (agent (create {CLIENT_ASSAULT}).test_inbox_put_take_stop_laws, "inbox_put_take_stop_laws")
			run_test (agent (create {CLIENT_ASSAULT}).test_inbox_refuses_when_full, "inbox_refuses_when_full")
			run_test (agent (create {CLIENT_ASSAULT}).test_poller_delivers_page_bytes_and_advances_cursor, "poller_delivers_page_bytes_and_advances_cursor")
			run_test (agent (create {CLIENT_ASSAULT}).test_poller_refuses_foreign_room_page_cursor_unchanged, "poller_refuses_foreign_room_page_cursor_unchanged")
			run_test (agent (create {CLIENT_ASSAULT}).test_poller_401_loses_the_session_and_refuses_the_next_poll, "poller_401_loses_the_session_and_refuses_the_next_poll")
			run_test (agent (create {CLIENT_ASSAULT}).test_poller_backoff_doubles_and_caps, "poller_backoff_doubles_and_caps")
			run_test (agent (create {CLIENT_ASSAULT}).test_presenter_unread_and_foreground_law, "presenter_unread_and_foreground_law")
			run_test (agent (create {CLIENT_ASSAULT}).test_presenter_pumps_two_pages_from_inbox, "presenter_pumps_two_pages_from_inbox")
			run_test (agent (create {CLIENT_ASSAULT}).test_presenter_foreground_toggled_mid_pump, "presenter_foreground_toggled_mid_pump")
			run_test (agent (create {CLIENT_ASSAULT}).test_presenter_foreground_pump_receives_others_message_quietly, "presenter_foreground_pump_receives_others_message_quietly")
			run_test (agent (create {CLIENT_ASSAULT}).test_presenter_system_events_and_name_collisions, "presenter_system_events_and_name_collisions")
			run_test (agent (create {CLIENT_ASSAULT}).test_presenter_outage_reported_once, "presenter_outage_reported_once")
			run_test (agent (create {CLIENT_ASSAULT}).test_presenter_load_roster_success_and_error, "presenter_load_roster_success_and_error")
			run_test (agent (create {CLIENT_ASSAULT}).test_unknown_error_code_never_raises, "unknown_error_code_never_raises")
			run_test (agent (create {CLIENT_ASSAULT}).test_poller_moves_nothing_once_the_inbox_is_stopped, "poller_moves_nothing_once_the_inbox_is_stopped")
			run_test (agent (create {CLIENT_ASSAULT}).test_poller_quiet_floor_and_pause, "poller_quiet_floor_and_pause")
			run_test (agent (create {CLIENT_ASSAULT}).test_session_lost_closes_the_room_and_logs_out, "session_lost_closes_the_room_and_logs_out")
			run_test (agent (create {CLIENT_ASSAULT}).test_https_authority_is_validated, "https_authority_is_validated")
			run_test (agent (create {CLIENT_ASSAULT}).test_presenter_system_alike_names_are_disambiguated, "presenter_system_alike_names_are_disambiguated")
			run_test (agent (create {CLIENT_ASSAULT}).test_presenter_connection_state_follows_outages, "presenter_connection_state_follows_outages")
			run_test (agent (create {CLIENT_ASSAULT}).test_locator_checks_the_health_shape, "locator_checks_the_health_shape")

			print ("=== STORE AND DOMAIN (Phase 1b) ===%N")
			run_test (agent (create {STORE_ASSAULT}).test_events_are_gapless_and_pages_are_newest, "events_are_gapless_and_pages_are_newest")
			run_test (agent (create {STORE_ASSAULT}).test_oracle_returns_copies, "oracle_returns_copies")
			run_test (agent (create {STORE_ASSAULT}).test_marker_authenticates, "marker_authenticates")
			run_test (agent (create {STORE_ASSAULT}).test_membership_and_default_room, "membership_and_default_room")
			run_test (agent (create {STORE_ASSAULT}).test_sessions_and_revocation, "sessions_and_revocation")
			run_test (agent (create {STORE_ASSAULT}).test_attachment_path_is_pinned_to_its_hash, "attachment_path_is_pinned_to_its_hash")
			run_test (agent (create {STORE_ASSAULT}).test_user_rules, "user_rules")
			run_test (agent (create {STORE_ASSAULT}).test_decoder_refuses_hostile_fields, "decoder_refuses_hostile_fields")
			run_test (agent (create {STORE_ASSAULT}).test_oracle_copies_strings, "oracle_copies_strings")

			print ("=== OPS (Phase 1b) ===%N")
			run_test (agent (create {OPS_ASSAULT}).test_caddyfile_is_one_loopback_site_with_admin_off, "caddyfile_is_one_loopback_site_with_admin_off")
			run_test (agent (create {OPS_ASSAULT}).test_hostnames_are_validated, "hostnames_are_validated")
			run_test (agent (create {OPS_ASSAULT}).test_null_door_stays_stopped, "null_door_stays_stopped")
			run_test (agent (create {OPS_ASSAULT}).test_duckdns_url_masks_the_token, "duckdns_url_masks_the_token")
			run_test (agent (create {OPS_ASSAULT}).test_config_lists_are_copies, "config_lists_are_copies")
			run_test (agent (create {OPS_ASSAULT}).test_caddy_door_supervises_a_stand_in_child, "caddy_door_supervises_a_stand_in_child")
			run_test (agent (create {OPS_ASSAULT}).test_caddy_door_refuses_a_missing_executable, "caddy_door_refuses_a_missing_executable")
			run_test (agent (create {OPS_ASSAULT}).test_caddy_door_reports_a_child_killed_behind_its_back, "caddy_door_reports_a_child_killed_behind_its_back")
			run_test (agent (create {OPS_ASSAULT}).test_duckdns_update_fails_closed_and_never_leaks_the_token, "duckdns_update_fails_closed_and_never_leaks_the_token")

			print ("=== SERVICE (Phase 1c) ===%N")
			run_test (agent (create {CHAT_ASSAULT}).test_log_never_contains_secrets, "log_never_contains_secrets")
			run_test (agent (create {CHAT_ASSAULT}).test_limiter_prefixes_windows_and_totals, "limiter_prefixes_windows_and_totals")
			run_test (agent (create {CHAT_ASSAULT}).test_json_refuses_empty_deep_and_impossible_dates, "json_refuses_empty_deep_and_impossible_dates")

			print ("=== CONFIG (Phase 1c) ===%N")
			run_test (agent (create {CONFIG_ASSAULT}).test_config_addresses_and_bot_usernames_are_tracked, "config_addresses_and_bot_usernames_are_tracked")
			run_test (agent (create {CONFIG_ASSAULT}).test_config_refuses_colliding_participants, "config_refuses_colliding_participants")

			print ("=== SERVICE BEHAVIOR (Phase 4) ===%N")
			run_test (agent (create {SERVICE_ASSAULT}).test_first_admin_created_once, "first_admin_created_once")
			run_test (agent (create {SERVICE_ASSAULT}).test_ordinary_member_created_by_the_host, "ordinary_member_created_by_the_host")
			run_test (agent (create {SERVICE_ASSAULT}).test_login_lockout_and_recovery, "login_lockout_and_recovery")
			run_test (agent (create {SERVICE_ASSAULT}).test_unknown_names_never_fill_the_user_limiter, "unknown_names_never_fill_the_user_limiter")
			run_test (agent (create {SERVICE_ASSAULT}).test_session_round_trip, "session_round_trip")
			run_test (agent (create {SERVICE_ASSAULT}).test_bot_token_round_trip_and_bot_login_refused, "bot_token_round_trip_and_bot_login_refused")
			run_test (agent (create {SERVICE_ASSAULT}).test_bot_marker_is_the_bots_alone, "bot_marker_is_the_bots_alone")
			run_test (agent (create {SERVICE_ASSAULT}).test_post_rate_limit_hits_and_recovers, "post_rate_limit_hits_and_recovers")
			run_test (agent (create {SERVICE_ASSAULT}).test_image_system_and_status_posts, "image_system_and_status_posts")
			run_test (agent (create {SERVICE_ASSAULT}).test_events_since_pages_gapless, "events_since_pages_gapless")
			run_test (agent (create {SERVICE_ASSAULT}).test_upload_signature_size_and_pinning, "upload_signature_size_and_pinning")
			run_test (agent (create {SERVICE_ASSAULT}).test_reset_password_revokes_sessions, "reset_password_revokes_sessions")
			run_test (agent (create {SERVICE_ASSAULT}).test_password_reset_by_the_host, "password_reset_by_the_host")
			run_test (agent (create {SERVICE_ASSAULT}).test_change_password_needs_the_old_one, "change_password_needs_the_old_one")
			run_test (agent (create {SERVICE_ASSAULT}).test_backup_writes_a_copy_that_opens_as_a_database, "backup_writes_a_copy_that_opens_as_a_database")
			run_test (agent (create {SERVICE_ASSAULT}).test_two_backups_in_the_same_second_are_two_files, "two_backups_in_the_same_second_are_two_files")
			run_test (agent (create {SERVICE_ASSAULT}).test_backup_over_the_memory_store_is_an_error_never_a_raise, "backup_over_the_memory_store_is_an_error_never_a_raise")

			print ("=== API (Phase 4) ===%N")
			run_test (agent (create {API_ASSAULT}).test_api_login_carries_token_once, "api_login_carries_token_once")
			run_test (agent (create {API_ASSAULT}).test_api_login_failure_and_lockout, "api_login_failure_and_lockout")
			run_test (agent (create {API_ASSAULT}).test_api_bot_login_refused_and_bot_token_posts, "api_bot_login_refused_and_bot_token_posts")
			run_test (agent (create {API_ASSAULT}).test_api_me_rooms_members_guards, "api_me_rooms_members_guards")
			run_test (agent (create {API_ASSAULT}).test_api_events_paging_and_merged_statuses, "api_events_paging_and_merged_statuses")
			run_test (agent (create {API_ASSAULT}).test_api_post_message_echo_and_rate_limit, "api_post_message_echo_and_rate_limit")
			run_test (agent (create {API_ASSAULT}).test_api_post_image_upload_rules_and_attachment, "api_post_image_upload_rules_and_attachment")
			run_test (agent (create {API_ASSAULT}).test_api_change_password_flow, "api_change_password_flow")
			run_test (agent (create {API_ASSAULT}).test_api_admin_gate_and_create_user, "api_admin_gate_and_create_user")
			run_test (agent (create {API_ASSAULT}).test_api_admin_reset_password_kills_sessions, "api_admin_reset_password_kills_sessions")
			run_test (agent (create {API_ASSAULT}).test_host_console_reset_kills_a_live_token, "host_console_reset_kills_a_live_token")
			run_test (agent (create {API_ASSAULT}).test_api_admin_bot_token_once_and_revoke, "api_admin_bot_token_once_and_revoke")
			run_test (agent (create {API_ASSAULT}).test_api_participants_and_backup_answers, "api_participants_and_backup_answers")

			print ("=== STORE EQUIVALENCE (Phase 4) ===%N")
			run_test (agent (create {EQUIVALENCE_ASSAULT}).test_store_equivalence_drive, "store_equivalence_drive")
			run_test (agent (create {EQUIVALENCE_ASSAULT}).test_sqlite_survives_close_and_reopen, "sqlite_survives_close_and_reopen")
			run_test (agent (create {EQUIVALENCE_ASSAULT}).test_sqlite_refuses_ahead_schema, "sqlite_refuses_ahead_schema")
			run_test (agent (create {EQUIVALENCE_ASSAULT}).test_sqlite_backs_up_a_behind_file, "sqlite_backs_up_a_behind_file")
			run_test (agent (create {EQUIVALENCE_ASSAULT}).test_backup_to_is_where_the_two_stores_lawfully_differ, "backup_to_is_where_the_two_stores_lawfully_differ")

			print ("=== CONFIG LOADING (Phase 4) ===%N")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_config_missing_file_is_one_named_error, "config_missing_file_is_one_named_error")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_config_junk_file_is_one_named_error, "config_junk_file_is_one_named_error")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_config_minimal_file_loads, "config_minimal_file_loads")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_config_full_file_loads_two_participants, "config_full_file_loads_two_participants")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_config_hostile_numbers_keep_defaults, "config_hostile_numbers_keep_defaults")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_config_hostile_door_and_ddns, "config_hostile_door_and_ddns")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_config_hostile_participants, "config_hostile_participants")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_config_bind_address_refused, "config_bind_address_refused")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_server_app_gates_and_door_match, "server_app_gates_and_door_match")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_server_app_display_name_gate, "server_app_display_name_gate")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_server_app_reset_password_gate, "server_app_reset_password_gate")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_server_app_decodes_utf8_console_bytes, "server_app_decodes_utf8_console_bytes")
			run_test (agent (create {CONFIG_LOAD_ASSAULT}).test_server_app_prompts_over_redirected_stdin, "server_app_prompts_over_redirected_stdin")

			print ("=== CLIENT WIRING (Phase 4) ===%N")
			run_test (agent (create {WIRING_ASSAULT}).test_winhttp_transport_refuses_what_cannot_go_on_the_wire, "winhttp_transport_refuses_what_cannot_go_on_the_wire")
			run_test (agent (create {WIRING_ASSAULT}).test_winhttp_transport_reports_a_dead_port_as_unexchanged, "winhttp_transport_reports_a_dead_port_as_unexchanged")
			run_test (agent (create {WIRING_ASSAULT}).test_client_config_round_trip, "client_config_round_trip")
			run_test (agent (create {WIRING_ASSAULT}).test_client_config_hostile_file_yields_defaults, "client_config_hostile_file_yields_defaults")
			run_test (agent (create {WIRING_ASSAULT}).test_client_config_session_sealed_never_in_clear, "client_config_session_sealed_never_in_clear")
			run_test (agent (create {WIRING_ASSAULT}).test_tray_notifier_counts_with_or_without_a_shell, "tray_notifier_counts_with_or_without_a_shell")
			run_test (agent (create {WIRING_ASSAULT}).test_live_client_stack_round_trip, "live_client_stack_round_trip")
			run_test (agent (create {WIRING_ASSAULT}).test_live_client_app_shows_an_event_in_the_real_pane, "live_client_app_shows_an_event_in_the_real_pane")
			run_test (agent (create {WIRING_ASSAULT}).test_live_gui_latency_through_a_quiet_poll, "live_gui_latency_through_a_quiet_poll")

			print ("=== THE PER-MESSAGE MENU (phase4/message-menu) ===%N")
			run_test (agent (create {CLIENT_ASSAULT}).test_a_fold_event_changes_a_bubble_and_never_draws_one, "a_fold_event_changes_a_bubble_and_never_draws_one")
			run_test (agent (create {CLIENT_ASSAULT}).test_a_delete_is_final_even_against_a_later_edit, "a_delete_is_final_even_against_a_later_edit")
			run_test (agent (create {CLIENT_ASSAULT}).test_reactions_dedupe_per_person_and_the_readers_own_is_marked, "reactions_dedupe_per_person_and_the_readers_own_is_marked")
			run_test (agent (create {CLIENT_ASSAULT}).test_a_reply_draws_and_carries_the_quote_of_what_it_answers, "a_reply_draws_and_carries_the_quote_of_what_it_answers")
			run_test (agent (create {CLIENT_ASSAULT}).test_a_fold_event_naming_nothing_is_dropped_in_silence, "a_fold_event_naming_nothing_is_dropped_in_silence")
			run_test (agent (create {CLIENT_ASSAULT}).test_the_fold_is_forgotten_when_the_room_changes, "the_fold_is_forgotten_when_the_room_changes")
			run_test (agent (create {CLIENT_ASSAULT}).test_the_menu_asks_the_presenter_who_said_it_and_what_it_says_now, "the_menu_asks_the_presenter_who_said_it_and_what_it_says_now")
			run_test (agent (create {WINDOW_ASSAULT}).test_the_per_message_menu_greys_by_the_servers_own_rule, "the_per_message_menu_greys_by_the_servers_own_rule")
			run_test (agent (create {WINDOW_ASSAULT}).test_a_plain_member_may_do_nothing_to_anyone_elses_message, "a_plain_member_may_do_nothing_to_anyone_elses_message")
			run_test (agent (create {WINDOW_ASSAULT}).test_nothing_is_offered_on_a_tombstone, "nothing_is_offered_on_a_tombstone")
			run_test (agent (create {WINDOW_ASSAULT}).test_a_click_on_a_reaction_chip_toggles_that_one_emoji, "a_click_on_a_reaction_chip_toggles_that_one_emoji")
			run_test (agent (create {WINDOW_ASSAULT}).test_the_compose_strip_says_what_return_will_do_and_escape_backs_out, "the_compose_strip_says_what_return_will_do_and_escape_backs_out")
			run_test (agent (create {WINDOW_ASSAULT}).test_return_sends_an_edit_or_a_reply_and_then_goes_back_to_plain, "return_sends_an_edit_or_a_reply_and_then_goes_back_to_plain")
			run_test (agent (create {WINDOW_ASSAULT}).test_the_fold_reaches_the_real_pane, "the_fold_reaches_the_real_pane")

			print ("=== THE FREEZE (phase4/freeze) ===%N")
			run_test (agent (create {FREEZE_ASSAULT}).test_an_eiffel_sleep_on_another_processor_never_stops_the_allocator, "an_eiffel_sleep_on_another_processor_never_stops_the_allocator")
			run_test (agent (create {FREEZE_ASSAULT}).test_an_unmarked_c_call_on_another_processor_stops_the_allocator, "an_unmarked_c_call_on_another_processor_stops_the_allocator")
			run_test (agent (create {FREEZE_ASSAULT}).test_the_gui_keeps_its_frame_while_the_poller_polls, "the_gui_keeps_its_frame_while_the_poller_polls")

			print ("=== THE VISIBLE CLIENT (Phase 4 Task 10) ===%N")
			run_test (agent (create {WINDOW_ASSAULT}).test_view_shows_events_in_order_and_never_twice, "view_shows_events_in_order_and_never_twice")
			run_test (agent (create {WINDOW_ASSAULT}).test_view_shows_an_image_as_an_attachment_line, "view_shows_an_image_as_an_attachment_line")
			run_test (agent (create {WINDOW_ASSAULT}).test_view_badge_status_error_and_connection, "view_badge_status_error_and_connection")
			run_test (agent (create {WINDOW_ASSAULT}).test_view_is_never_in_front_without_a_window, "view_is_never_in_front_without_a_window")
			run_test (agent (create {WINDOW_ASSAULT}).test_view_shaped_text_is_on_and_lays_out_the_acceptance_line, "view_shaped_text_is_on_and_lays_out_the_acceptance_line")
			run_test (agent (create {WINDOW_ASSAULT}).test_input_box_submits_on_return_and_never_sends_an_empty_line, "input_box_submits_on_return_and_never_sends_an_empty_line")
			run_test (agent (create {WINDOW_ASSAULT}).test_composer_grows_with_content_then_caps_at_five_lines, "composer_grows_with_content_then_caps_at_five_lines")
			run_test (agent (create {WINDOW_ASSAULT}).test_composer_draw_restores_its_own_geometry_after_scrolling, "composer_draw_restores_its_own_geometry_after_scrolling")
			run_test (agent (create {WINDOW_ASSAULT}).test_composer_return_sends_but_shift_return_inserts_a_newline, "composer_return_sends_but_shift_return_inserts_a_newline")
			run_test (agent (create {WINDOW_ASSAULT}).test_composer_grows_on_the_frame_the_wrap_happens, "composer_grows_on_the_frame_the_wrap_happens")
			run_test (agent (create {WINDOW_ASSAULT}).test_empty_status_rows_cost_nothing_and_a_spoken_one_costs_its_row, "empty_status_rows_cost_nothing_and_a_spoken_one_costs_its_row")
			run_test (agent (create {WINDOW_ASSAULT}).test_the_gap_holds_while_the_composer_grows, "the_gap_holds_while_the_composer_grows")
			run_test (agent (create {WINDOW_ASSAULT}).test_the_pane_hands_the_thread_its_line_breaks, "the_pane_hands_the_thread_its_line_breaks")
			run_test (agent (create {WINDOW_ASSAULT}).test_the_menu_bar_declares_its_mnemonics_and_owns_the_alt_key, "the_menu_bar_declares_its_mnemonics_and_owns_the_alt_key")
			run_test (agent (create {WINDOW_ASSAULT}).test_the_room_menu_states_the_keys_it_now_answers_to, "the_room_menu_states_the_keys_it_now_answers_to")
			run_test (agent (create {WINDOW_ASSAULT}).test_the_ctrl_keys_are_claimed_window_wide_and_undo_is_not, "the_ctrl_keys_are_claimed_window_wide_and_undo_is_not")
			run_test (agent (create {WINDOW_ASSAULT}).test_alt_and_a_letter_opens_that_pad_end_to_end, "alt_and_a_letter_opens_that_pad_end_to_end")
			run_test (agent (create {WINDOW_ASSAULT}).test_copy_goes_to_whichever_widget_has_the_focus, "copy_goes_to_whichever_widget_has_the_focus")
			run_test (agent (create {WINDOW_ASSAULT}).test_cut_paste_and_select_all_route_the_same_way, "cut_paste_and_select_all_route_the_same_way")
			run_test (agent (create {WINDOW_ASSAULT}).test_the_edit_menu_greys_for_both_focus_cases, "the_edit_menu_greys_for_both_focus_cases")
			run_test (agent (create {WINDOW_ASSAULT}).test_a_press_on_a_bubble_is_what_gives_the_pane_the_keys, "a_press_on_a_bubble_is_what_gives_the_pane_the_keys")
			run_test (agent (create {WINDOW_ASSAULT}).test_presenter_pumps_pages_into_the_real_pane, "presenter_pumps_pages_into_the_real_pane")
			run_test (agent (create {WINDOW_ASSAULT}).test_login_window_validates_its_fields, "login_window_validates_its_fields")
			run_test (agent (create {WINDOW_ASSAULT}).test_login_window_shows_a_refusal_and_accepts_a_success, "login_window_shows_a_refusal_and_accepts_a_success")
			run_test (agent (create {WINDOW_ASSAULT}).test_client_app_prefers_the_remembered_session, "client_app_prefers_the_remembered_session")
			run_test (agent (create {WINDOW_ASSAULT}).test_client_app_falls_back_to_the_door_and_logs_in, "client_app_falls_back_to_the_door_and_logs_in")
			run_test (agent (create {WINDOW_ASSAULT}).test_client_app_refuses_to_send_a_password_to_a_plain_http_stranger, "client_app_refuses_to_send_a_password_to_a_plain_http_stranger")
			run_test (agent (create {WINDOW_ASSAULT}).test_client_app_opens_the_first_room_and_ticks, "client_app_opens_the_first_room_and_ticks")
			run_test (agent (create {WINDOW_ASSAULT}).test_client_app_hints_the_room_when_a_bot_is_in_the_roster, "client_app_hints_the_room_when_a_bot_is_in_the_roster")
			run_test (agent (create {WINDOW_ASSAULT}).test_client_app_shows_no_hint_when_the_roster_has_no_bot, "client_app_shows_no_hint_when_the_roster_has_no_bot")
			run_test (agent (create {WINDOW_ASSAULT}).test_client_app_reports_a_server_that_lists_no_room, "client_app_reports_a_server_that_lists_no_room")

			print ("=== NOTHING ANSWERED AT ALL (phase4/no-server-message) ===%N")
			run_test (agent (create {WINDOW_ASSAULT}).test_no_server_on_this_pc_is_told_how_to_start_one, "no_server_on_this_pc_is_told_how_to_start_one")
			run_test (agent (create {WINDOW_ASSAULT}).test_an_unreachable_friend_is_named_with_his_address_and_the_settings_file, "an_unreachable_friend_is_named_with_his_address_and_the_settings_file")
			run_test (agent (create {WINDOW_ASSAULT}).test_a_refused_password_still_gets_the_servers_own_words, "a_refused_password_still_gets_the_servers_own_words")
			run_test (agent (create {WINDOW_ASSAULT}).test_connection_advice_reads_the_address_and_nothing_else, "connection_advice_reads_the_address_and_nothing_else")

			print ("=== SCOOP CONSUMER ===%N")
			run_test (agent s.test_scoop_compatibility, "scoop_compatibility")

			print ("=== PARTICIPANTS (Phase 1b) ===%N")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_handle_rules, "handle_rules")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_prefix_spoof_and_boundary, "prefix_spoof_and_boundary")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_handle_only_body_is_not_a_request, "handle_only_body_is_not_a_request")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_via_parsing, "via_parsing")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_registry_alias_resolution, "registry_alias_resolution")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_participant_config_completeness, "participant_config_completeness")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_tool_gates_raw_and_shaped, "tool_gates_raw_and_shaped")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_via_plain_disclosure_law, "via_plain_disclosure_law")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_tool_reply_limits, "tool_reply_limits")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_bible_and_shape_allowlists, "bible_and_shape_allowlists")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_image_path_rules, "image_path_rules")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_image_path_outside_sandbox_refused, "image_path_outside_sandbox_refused")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_claude_sandbox_rule, "claude_sandbox_rule")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_claude_vault_directory_refused, "claude_vault_directory_refused")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_engine_timing_contracts, "engine_timing_contracts")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_ignores_bots_and_answers_once, "dispatcher_ignores_bots_and_answers_once")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_restart_cursor_honoured, "dispatcher_restart_cursor_honoured")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_per_room_cursors, "dispatcher_per_room_cursors")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_metacharacter_law, "metacharacter_law")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_claude_sandbox_memory_files, "claude_sandbox_memory_files")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_grants_and_charges_via, "dispatcher_grants_and_charges_via")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_survives_raising_engine, "dispatcher_survives_raising_engine")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_prunes_answered, "dispatcher_prunes_answered")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_the_fold_lets_the_last_edit_win_and_a_delete_bury_it, "the_fold_lets_the_last_edit_win_and_a_delete_bury_it")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_reactions_dedupe_per_person_and_the_last_word_wins, "reactions_dedupe_per_person_and_the_last_word_wins")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_the_fold_ignores_what_it_cannot_understand, "the_fold_ignores_what_it_cannot_understand")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_a_reply_is_a_message_that_names_its_parent, "a_reply_is_a_message_that_names_its_parent")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_only_the_author_edits_but_an_admin_may_delete, "only_the_author_edits_but_an_admin_may_delete")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_summary_is_never_a_room_event, "summary_is_never_a_room_event")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_summary_spends_its_own_budget, "summary_spends_its_own_budget")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_summary_says_when_there_is_nothing_to_say, "summary_says_when_there_is_nothing_to_say")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_summary_gate_refuses_a_stranger, "summary_gate_refuses_a_stranger")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_a_reply_carrying_tool_markup_never_reaches_the_room, "a_reply_carrying_tool_markup_never_reaches_the_room")
			run_test (agent (create {CLIENT_ASSAULT}).test_the_window_keeps_its_heartbeat_while_a_summary_runs, "the_window_keeps_its_heartbeat_while_a_summary_runs")
			run_test (agent (create {CLIENT_ASSAULT}).test_about_names_the_version_the_build_and_the_fleet, "about_names_the_version_the_build_and_the_fleet")
			run_test (agent (create {CLIENT_ASSAULT}).test_a_bubble_keeps_the_line_breaks_it_was_given, "a_bubble_keeps_the_line_breaks_it_was_given")
			run_test (agent (create {CLIENT_ASSAULT}).test_summary_ask_needs_a_verb_at_the_front, "summary_ask_needs_a_verb_at_the_front")
			run_test (agent (create {CLIENT_ASSAULT}).test_summary_ask_reads_the_window_it_names, "summary_ask_reads_the_window_it_names")
			run_test (agent (create {WIRING_ASSAULT}).test_client_config_keeps_the_catch_up_thresholds, "client_config_keeps_the_catch_up_thresholds")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_post_does_not_ring_the_dispatcher_back, "dispatcher_post_does_not_ring_the_dispatcher_back")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_answers_the_second_and_third_request_of_a_run, "dispatcher_answers_the_second_and_third_request_of_a_run")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_answers_two_requests_that_arrive_together, "dispatcher_answers_two_requests_that_arrive_together")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_two_bots_answer_the_same_room, "dispatcher_two_bots_answer_the_same_room")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_bus_mutes_one_ticket_and_only_for_that_post, "bus_mutes_one_ticket_and_only_for_that_post")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_bible_tool_runs_a_real_child, "bible_tool_runs_a_real_child")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_tool_child_killed_at_timeout, "tool_child_killed_at_timeout")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_shape_tool_answers_from_a_scratch_database, "shape_tool_answers_from_a_scratch_database")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_population_from_configuration, "dispatcher_population_from_configuration")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_mention_boundary_rule_anywhere_in_the_text, "mention_boundary_rule_anywhere_in_the_text")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_mention_rewritten_into_the_leading_address, "mention_rewritten_into_the_leading_address")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_dispatcher_answers_a_mention_in_the_middle, "dispatcher_answers_a_mention_in_the_middle")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_a_bots_own_mention_never_triggers_it, "a_bots_own_mention_never_triggers_it")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_two_bots_in_one_message_each_reply_once, "two_bots_in_one_message_each_reply_once")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_mention_keeps_the_rate_limit, "mention_keeps_the_rate_limit")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_context_window_carries_the_conversation, "context_window_carries_the_conversation")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_context_window_is_capped_and_optional, "context_window_is_capped_and_optional")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_claude_session_is_kept_per_room_and_dropped_on_failure, "claude_session_is_kept_per_room_and_dropped_on_failure")
			run_test (agent (create {PARTICIPANTS_ASSAULT}).test_participant_config_carries_the_context_setting, "participant_config_carries_the_context_setting")

			print ("=== TODO: PHASE 5 (skeletal) ===%N")
			run_test (agent t.test_post_message_appends_and_rings, "post_message_appends_and_rings (skeletal)")
			run_test (agent t.test_doorbell_no_loss_under_concurrency, "doorbell_no_loss_under_concurrency (skeletal)")
			run_test (agent t.test_dispatcher_ignores_bots_and_answers_once, "dispatcher_ignores_bots_and_answers_once (skeletal)")
			run_test (agent t.test_tool_refuses_unsafe_argument, "tool_refuses_unsafe_argument (skeletal)")
			run_test (agent t.test_sse_replays_since_then_live, "sse_replays_since_then_live (skeletal)")
			run_test (agent t.test_long_poll_returns_within_deadline, "long_poll_returns_within_deadline (skeletal)")
			run_test (agent t.test_sw_view_renders_hebrew_and_marker, "sw_view_renders_hebrew_and_marker (skeletal)")

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")
			if failed > 0 then
				print ("TESTS FAILED%N")
				name_the_missing_build
			else
				print ("ALL TESTS PASSED%N")
			end
		end

	name_the_missing_build
			-- When the finalized server executable is not built, say so and name
			-- the one command that builds it.
			--
			-- The live rounds in WIRING_ASSAULT used to SKIP without it and count
			-- the skip as a pass; they now FAIL, which is honest but says only
			-- that three tests failed. This says WHY, once, where the reader is
			-- already looking - at `Results:'.
		local
			l_exe: SERVER_EXE
		do
			create l_exe
			if not l_exe.is_built then
				print ("%N" + l_exe.Relative_path + " is NOT BUILT, so every live%N")
				print ("assault above failed for that one reason. Build it FIRST, from the%N")
				print ("project root:%N")
				print ("    " + l_exe.Build_command + "%N")
				print ("then run this runner again.%N")
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
				io.output.flush
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
