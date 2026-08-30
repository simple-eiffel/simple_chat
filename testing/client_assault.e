note
	description: "[
		The client stack under assault (Phase 1b): CHAT_CLIENT against
		the scripted transport, the URL rules against the hostile forms,
		the locator, and the SCOOP-shaped trio - EVENT_INBOX, EVENT_POLLER,
		CHAT_PRESENTER - driven on one processor: ordinary inbox objects
		are passed where `separate' formals are expected, which is legal,
		and no test creates a separate object.
	]"
	author: "Larry Rix"

class
	CLIENT_ASSAULT

inherit
	TEST_SET_BASE

feature -- CHAT_CLIENT: the token and the wire

	test_client_login_sends_bearer_never_in_url
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			r: CHAT_RESULT [CHAT_MEMBER]
			l_page: CHAT_RESULT [CHAT_PAGE]
		do
			create t.make
			create c.make (t, loopback)
			t.script (401, "{%"code%":%"bad_credentials%",%"message%":%"no%"}")
			r := c.login ("larry", {STRING_32} "wrong password")
			assert ("refused", not r.is_success and attached r.error as e and then e.code.same_string ({CHAT_ERROR}.Code_bad_credentials))
			assert ("password went in the body, not the url", t.last_request.body.has_substring ("wrong password") and not t.last_request.url.has_substring ("wrong"))
			assert ("login carries no bearer", not t.last_request.has_header ("Authorization"))
			t.script (200, login_reply (hex64))
			r := c.login ("larry", {STRING_32} "correct horse battery staple")
			assert ("logged in", r.is_success and c.is_logged_in and attached c.me as m and then (m.id = 5 and m.is_admin))
			t.script (200, wire_page ("", ""))
			l_page := c.events_since (1, 0, 100)
			assert ("empty page ok, with its bytes", l_page.is_success and attached l_page.value as p and then (p.events.is_empty and p.has_bytes))
			assert ("bearer header", t.last_request.has_header ("Authorization") and t.last_request.header ("Authorization").same_string ("Bearer " + hex64))
			assert ("token never in url", not t.last_request.url.has_substring (hex64))
			assert ("url shape", t.last_request.url.same_string ("http://127.0.0.1:8080/rooms/1/events?since=0&limit=100"))
			t.script_failure ({STRING_32} "connection refused")
			l_page := c.wait_for_events (1, 0, 100, 25)
			assert ("transport failure is a result", not l_page.is_success and is_error_status (l_page.error, 503))
			assert ("wait timeout covers the poll", t.last_request.timeout_seconds = 30)
			t.script (200, "")
			c.logout
			assert ("logged out", not c.is_logged_in and c.me = Void)
		end

	test_token_never_in_url_or_body_across_all_requests
			-- Login, both reads, the roster, a post and the logout: the token is in no URL and no
			-- body, every request but the login carries exactly the bearer, the login carries none.
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			l_page: CHAT_RESULT [CHAT_PAGE]
			l_members: CHAT_RESULT [ARRAYED_LIST [CHAT_MEMBER]]
			l_event: CHAT_RESULT [CHAT_EVENT]
		do
			create t.make
			c := logged_in_client (t)
			t.script (200, wire_page ("", ""))
			l_page := c.events_since (1, 0, 50)
			t.script (200, wire_page ("", ""))
			l_page := c.wait_for_events (1, 0, 50, 1)
			t.script (200, "{%"members%":[" + member_json (9, "nick", "Nick") + "]}")
			l_members := c.members (1)
			t.script (201, wire_message (1, 5, "hi"))
			l_event := c.post_message (1, {STRING_32} "hi")
			t.script_failure ({STRING_32} "gone")
			c.logout
			assert ("six requests", t.exchange_count = 6 and l_page.is_success and l_members.is_success and l_event.is_success)
			assert ("token never in a url or a body", across t.requests as q all (not q.url.has_substring (hex64) and not q.body.has_substring (hex64)) end)
			assert ("login alone carries no bearer", not t.requests.first.has_header ("Authorization"))
			assert ("every other request carries exactly the bearer", across t.requests as q all (q = t.requests.first or else (q.has_header ("Authorization") and then q.header ("Authorization").same_string ("Bearer " + hex64))) end)
			assert ("logout carried it too, then forgot it", t.last_request.has_header ("Authorization") and not c.is_logged_in and c.me = Void)
		end

	test_wait_zero_seconds_uses_five_second_timeout
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			l_page: CHAT_RESULT [CHAT_PAGE]
		do
			create t.make
			c := logged_in_client (t)
			t.script (200, wire_page ("", ""))
			l_page := c.wait_for_events (1, 0, 10, 0)
			assert ("a result", l_page.is_success)
			assert ("wait 0 -> timeout 5", t.last_request.timeout_seconds = 5 and t.last_request.url.ends_with ("&seconds=0"))
			t.script (200, wire_page ("", ""))
			l_page := c.wait_for_events (1, 0, 10, 25)
			assert ("wait 25 -> timeout 30", t.last_request.timeout_seconds = 30 and t.last_request.url.ends_with ("&seconds=25"))
		end

	test_login_never_raises_on_hostile_replies
			-- A captive-portal 200, a 302, an error body under 200, a token of the wrong shape,
			-- a non-Latin-1 token, an empty error message, a 500 of HTML: results, never exceptions.
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			r: CHAT_RESULT [CHAT_MEMBER]
		do
			create t.make
			create c.make (t, loopback)
			t.script (200, "not json")
			r := c.login ("larry", {STRING_32} "pw")
			assert ("captive portal 200 is a 502 result", not r.is_success and not c.is_logged_in and attached r.error as e1 and then (e1.http_status = 502 and not e1.message.is_empty))
			t.script (302, "")
			r := c.login ("larry", {STRING_32} "pw")
			assert ("302 is a 502 result", not r.is_success and is_error_status (r.error, 502))
			t.script (200, "{%"code%":%"x%",%"message%":%"y%"}")
			r := c.login ("larry", {STRING_32} "pw")
			assert ("an error body under 200 is a 502 result", not r.is_success and is_error_status (r.error, 502))
			t.script (200, login_reply ("0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef"))
			r := c.login ("larry", {STRING_32} "pw")
			assert ("a token that is not lowercase hex-64 is refused", not r.is_success and not c.is_logged_in and is_error_status (r.error, 502))
			t.script (200, login_reply (hex64.substring (1, 62) + "%R%N"))
			r := c.login ("larry", {STRING_32} "pw")
			assert ("CRLF inside a 64-character token is refused", not r.is_success and not c.is_logged_in)
			t.script (200, login_reply (hex64.substring (1, 63) + "%/215/%/144/"))
			r := c.login ("larry", {STRING_32} "pw")
			assert ("a non-latin-1 token is a 502 result, not an exception", not r.is_success and not c.is_logged_in and is_error_status (r.error, 502))
			t.script (401, "{%"code%":%"bad_credentials%",%"message%":%"%"}")
			r := c.login ("larry", {STRING_32} "pw")
			assert ("an empty message keeps the status and the code with a stock message", not r.is_success and attached r.error as e5 and then (e5.http_status = 401 and e5.code.same_string ("bad_credentials") and not e5.message.is_empty))
			t.script (401, "{%"code%":%"%",%"message%":%"%"}")
			r := c.login ("larry", {STRING_32} "pw")
			assert ("an empty code becomes unavailable", not r.is_success and attached r.error as e6 and then (e6.http_status = 401 and e6.code.same_string ({CHAT_ERROR}.Code_unavailable)))
			t.script (500, "<html>down</html>")
			r := c.login ("larry", {STRING_32} "pw")
			assert ("500 html is a 500 result", not r.is_success and attached r.error as e7 and then (e7.http_status = 500 and e7.code.same_string ({CHAT_ERROR}.Code_unavailable)))
			t.script (200, "{%"token%":%"" + hex64 + "%",%"member%":{%"id%":0,%"username%":%"larry%",%"display_name%":%"Larry%"}}")
			r := c.login ("larry", {STRING_32} "pw")
			assert ("a member the domain refuses is a 502 result", not r.is_success and is_error_status (r.error, 502))
			assert ("still logged out after every attempt", not c.is_logged_in and c.me = Void and t.exchange_count = 10)
			t.script (200, login_reply (hex64))
			r := c.login ("larry", {STRING_32} "pw")
			assert ("and a lawful reply still logs in", r.is_success and c.is_logged_in)
		end

	test_post_message_echo_for_another_room_is_refused
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			l_event: CHAT_RESULT [CHAT_EVENT]
		do
			create t.make
			c := logged_in_client (t)
			t.script (201, wire_event (7, 2, 5, "message", "hi"))
			l_event := c.post_message (1, {STRING_32} "hi")
			assert ("an echo for room 2 is a 502 result", not l_event.is_success and is_error_status (l_event.error, 502))
			t.script (201, wire_event (7, 1, 0, "system", "hi"))
			l_event := c.post_message (1, {STRING_32} "hi")
			assert ("an echo of another kind is a 502 result", not l_event.is_success and is_error_status (l_event.error, 502))
			t.script (201, "{%"id%":7}")
			l_event := c.post_message (1, {STRING_32} "hi")
			assert ("a 201 that is not an event is a 502 result", not l_event.is_success and is_error_status (l_event.error, 502))
			t.script (429, "{%"code%":%"rate_limited%",%"message%":%"slow down%"}")
			l_event := c.post_message (1, {STRING_32} "hi")
			assert ("the server's own error is carried", not l_event.is_success and is_error_status (l_event.error, 429) and attached l_event.error as e and then e.code.same_string ({CHAT_ERROR}.Code_rate_limited))
			t.script (201, wire_message (7, 5, "hi"))
			l_event := c.post_message (1, {STRING_32} "hi")
			assert ("the true echo is accepted", l_event.is_success and attached l_event.value as ev and then (ev.id = 7 and ev.room_id = 1 and ev.is_message))
			assert ("body went as json, token as header only", t.last_request.body.has_substring ("%"body%":%"hi%"") and not t.last_request.body.has_substring (hex64))
			assert ("still logged in", c.is_logged_in)
		end

	test_session_handed_to_the_pollers_client
			-- The GUI's client copies its session into a second client (the poller's, on its own
			-- processor in the app; here on this one): that client polls with the same bearer, the
			-- token still never appears in a URL or a body, and the first client keeps its session.
		local
			t, t2: MEMORY_HTTP_TRANSPORT
			c, c2: CHAT_CLIENT
			l_page: CHAT_RESULT [CHAT_PAGE]
		do
			create t.make
			c := logged_in_client (t)
			create t2.make
			create c2.make (t2, loopback)
			assert ("fresh client is logged out", not c2.is_logged_in and c2.me = Void)
			c.hand_session_to (c2)
			assert ("session copied", c2.is_logged_in and attached c2.me as m and then (m.id = 5 and m.username.same_string ("larry") and m.display_name.same_string ({STRING_32} "Larry") and m.is_admin))
			assert ("the first client keeps its session", c.is_logged_in and attached c.me as m0 and then m0.id = 5)
			t2.script (200, wire_page ("", ""))
			l_page := c2.wait_for_events (1, 0, 10, 0)
			assert ("the second client polls with the same bearer", l_page.is_success and t2.last_request.header ("Authorization").same_string ("Bearer " + hex64))
			assert ("and never with the token in a url or a body", across t2.requests as q all (not q.url.has_substring (hex64) and not q.body.has_substring (hex64)) end)
			assert ("the first transport saw nothing of it", t.exchange_count = 1)
			t2.script_failure ({STRING_32} "gone")
			c2.logout
			assert ("each session ends on its own", not c2.is_logged_in and c.is_logged_in)
		end

	test_logout_on_transport_failure_logs_out
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
		do
			create t.make
			c := logged_in_client (t)
			t.script_failure ({STRING_32} "connection reset")
			c.logout
			assert ("logged out although the server never heard", not c.is_logged_in and c.me = Void)
			assert ("the request still carried the bearer", t.last_request.url.ends_with ("/logout") and t.last_request.header ("Authorization").same_string ("Bearer " + hex64))
			assert ("two requests in all", t.exchange_count = 2)
		end

	test_page_result_refuses_foreign_room_non_ascending_and_hostile_fields
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			l_page: CHAT_RESULT [CHAT_PAGE]
		do
			create t.make
			c := logged_in_client (t)
			t.script (200, wire_page (wire_message (1, 9, "one") + "," + wire_event (2, 2, 9, "message", "elsewhere"), ""))
			l_page := c.events_since (1, 0, 50)
			assert ("a foreign-room event refuses the page", not l_page.is_success and is_error_status (l_page.error, 502))
			t.script (200, wire_page (wire_message (1, 9, "one"), wire_status (2, "Claude", "thinking")))
			l_page := c.events_since (1, 0, 50)
			assert ("a foreign-room status refuses the page", not l_page.is_success and is_error_status (l_page.error, 502))
			t.script (200, wire_page (wire_message (2, 9, "two") + "," + wire_message (1, 9, "one"), ""))
			l_page := c.events_since (1, 0, 50)
			assert ("a non-ascending page is a 502 result, never an exception", not l_page.is_success and is_error_status (l_page.error, 502))
			t.script (200, wire_page (wire_message (3, 9, "stale") + "," + wire_message (4, 9, "four"), ""))
			l_page := c.events_since (1, 3, 50)
			assert ("a page not after since is refused", not l_page.is_success and is_error_status (l_page.error, 502))
			t.script (200, wire_page (wire_message (1, 9, "one") + "," + wire_message (2, 9, "two") + "," + wire_message (3, 9, "three"), ""))
			l_page := c.events_since (1, 0, 2)
			assert ("a page over the limit is refused", not l_page.is_success and is_error_status (l_page.error, 502))
			t.script (200, wire_page (wire_event (1, 1, 9, "%/215/%/144/", "x"), ""))
			l_page := c.events_since (1, 0, 50)
			assert ("a non-latin-1 kind is a 502 result, not an exception", not l_page.is_success and is_error_status (l_page.error, 502))
			t.script (200, "{%"events%":[{%"id%":1,%"room_id%":1,%"sender_id%":9,%"kind%":%"message%",%"created_at%":%"garbage%",%"body%":%"x%"}],%"statuses%":[]}")
			l_page := c.events_since (1, 0, 50)
			-- CHAT_JSON.is_iso8601 refuses "garbage", and one malformed event refuses the whole page (Issue 30): a 502, never a page with a made-up time.
			assert ("an unparseable created_at is a 502 result, never an exception", c.is_logged_in and not l_page.is_success and is_error_status (l_page.error, 502))
			t.script (200, wire_page (wire_message (1, 9, "one") + "," + wire_message (2, 9, "two"), wire_status (1, "Claude", "thinking")))
			l_page := c.events_since (1, 0, 50)
			assert ("a lawful page is accepted with its bytes", l_page.is_success and attached l_page.value as p and then (p.events.count = 2 and p.statuses.count = 1 and p.last_id = 2 and p.has_bytes and p.bytes.has_substring ("thinking")))
			assert ("still logged in throughout", c.is_logged_in and t.exchange_count = 9)
		end

	test_members_roster_success_and_hostile
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			l_members: CHAT_RESULT [ARRAYED_LIST [CHAT_MEMBER]]
		do
			create t.make
			c := logged_in_client (t)
			t.script (200, "{%"members%":[" + member_json (5, "larry", "Larry") + "," + member_json (9, "nick", "Nick") + "]}")
			l_members := c.members (1)
			assert ("two members", l_members.is_success and attached l_members.value as l and then (l.count = 2 and l [2].id = 9))
			assert ("roster url", t.last_request.url.same_string ("http://127.0.0.1:8080/rooms/1/members"))
			t.script (200, "{%"members%":[" + member_json (9, "nick", "Nick") + "," + member_json (9, "nick2", "Nick") + "]}")
			l_members := c.members (1)
			assert ("a roster naming an id twice is a 502 result", not l_members.is_success and is_error_status (l_members.error, 502))
			t.script (200, "[]")
			l_members := c.members (1)
			assert ("a 200 that is not a roster is a 502 result", not l_members.is_success and is_error_status (l_members.error, 502))
			t.script (403, "{%"code%":%"not_member%",%"message%":%"not in this room%"}")
			l_members := c.members (1)
			assert ("403 carried through", not l_members.is_success and is_error_status (l_members.error, 403) and attached l_members.error as e and then e.code.same_string ({CHAT_ERROR}.Code_not_member))
		end

feature -- Where the token may go

	test_hostile_urls_refused_loopbacks_accepted
		local
			rules: CHAT_URL_RULES
			cfg: CLIENT_CONFIG
		do
			create rules
			assert ("userinfo before a loopback host", not rules.is_acceptable_url ("http://localhost@evil.example"))
			assert ("loopback as a subdomain", not rules.is_acceptable_url ("http://127.0.0.1.evil.example"))
			assert ("localhost as a subdomain", not rules.is_acceptable_url ("http://localhost.evil.example"))
			assert ("port then userinfo", not rules.is_acceptable_url ("http://localhost:8080@evil.example"))
			assert ("credentials in an https url", not rules.is_acceptable_url ("https://user:pw@host"))
			assert ("a query in the base", not rules.is_acceptable_url ("https://host/base?x=y"))
			assert ("loopback with port", rules.is_acceptable_url ("http://127.0.0.1:8080") and rules.is_loopback_url ("http://127.0.0.1:8080"))
			assert ("localhost bare", rules.is_acceptable_url ("http://localhost") and rules.is_loopback_url ("http://localhost"))
			assert ("ipv6 loopback with port", rules.is_acceptable_url ("http://[::1]:8080") and rules.is_loopback_url ("http://[::1]:8080"))
			assert ("https to a host", rules.is_acceptable_url ("https://rixchat.duckdns.org") and not rules.is_loopback_url ("https://rixchat.duckdns.org"))
			assert ("plain http to a host", not rules.is_acceptable_url ("http://rixchat.duckdns.org"))
			assert ("trailing slash", not rules.is_acceptable_url ("https://rixchat.duckdns.org/") and not rules.is_acceptable_url ("http://localhost/"))
			assert ("fragment", not rules.is_acceptable_url ("https://host#x"))
			assert ("blank or empty", not rules.is_acceptable_url ("https://ho st") and not rules.is_acceptable_url (""))
			assert ("empty authority", not rules.is_acceptable_url ("https://") and not rules.is_acceptable_url ("https:///path"))
			assert ("bad ports", not rules.is_loopback_url ("http://127.0.0.1:0") and not rules.is_loopback_url ("http://127.0.0.1:65536") and not rules.is_loopback_url ("http://127.0.0.1:") and not rules.is_loopback_url ("http://127.0.0.1:80a"))
			assert ("unclosed bracket", not rules.is_loopback_url ("http://[::1:8080"))
			assert ("LOCALHOST in any case", rules.is_loopback_url ("http://LOCALHOST:8080"))
			assert ("authority parsed", rules.authority_of ("https://host:443/base").same_string ("host:443") and rules.authority_of ("ftp://x").is_empty)
			assert ("same_url ignores case in scheme and host only", rules.same_url ("HTTPS://RixChat.duckdns.org/Base", "https://rixchat.duckdns.org/Base") and not rules.same_url ("https://rixchat.duckdns.org/Base", "https://rixchat.duckdns.org/base"))
			create cfg.make_defaults
			assert ("config refuses the same", not cfg.is_acceptable_url ("http://localhost@evil.example") and cfg.is_acceptable_url (cfg.local_url))
		end

	test_endpoint_secure_by_construction_and_config_server_list
		local
			e: CHAT_ENDPOINT
			cfg: CLIENT_CONFIG
		do
			create e.make ("http://127.0.0.1:8080")
			assert ("loopback endpoint is local and secure", e.is_local and e.is_secure and e.url_for ("/health").same_string ("http://127.0.0.1:8080/health"))
			create e.make ("https://rixchat.duckdns.org")
			assert ("https endpoint is remote and secure", not e.is_local and e.is_secure)
			create e.make ("http://localhost:9090")
			assert ("a loopback reached any other way is still local", e.is_local and e.is_secure)
			create cfg.make_defaults
			cfg.set_only_server_url ("https://rixchat.duckdns.org")
			cfg.add_server_url ("https://sue-chat.duckdns.org")
			cfg.set_primary_url ("https://new-primary.duckdns.org")
			assert ("primary in front, standbys kept", cfg.server_urls.count = 3 and cfg.server_url.same_string ("https://new-primary.duckdns.org") and cfg.server_urls [2].same_string ("https://rixchat.duckdns.org") and cfg.server_urls [3].same_string ("https://sue-chat.duckdns.org"))
			cfg.set_primary_url ("https://SUE-CHAT.duckdns.org")
			assert ("a known server moves to the front, once", cfg.server_urls.count = 3 and cfg.server_url.same_string ("https://SUE-CHAT.duckdns.org") and cfg.server_urls [2].same_string ("https://new-primary.duckdns.org") and cfg.server_urls [3].same_string ("https://rixchat.duckdns.org"))
			assert ("has_url ignores scheme and host case", cfg.has_url ("HTTPS://RIXCHAT.duckdns.org") and not cfg.has_url ("https://nobody.duckdns.org"))
			cfg.set_only_server_url ("https://only.duckdns.org")
			assert ("set_only forgets the standbys", cfg.server_urls.count = 1 and cfg.server_url.same_string ("https://only.duckdns.org"))
			cfg.set_window (10, 20, 300, 200)
			assert ("window set, servers kept", cfg.window_x = 10 and cfg.window_y = 20 and cfg.window_width = 300 and cfg.window_height = 200 and cfg.server_urls.count = 1)
		end

feature -- SERVICE_LOCATOR

	test_locator_prefers_live_local_then_standby
		local
			t: MEMORY_HTTP_TRANSPORT
			l: SERVICE_LOCATOR
			cfg: CLIENT_CONFIG
			e: CHAT_ENDPOINT
		do
			create t.make
			create l.make (t)
			create cfg.make_defaults
			cfg.set_only_server_url ("https://rixchat.duckdns.org")
			cfg.add_server_url ("https://sue-chat.duckdns.org")
			t.script (200, "{%"store%":true}")
			e := l.locate (cfg)
			assert ("local wins when alive", e.is_local and l.probe_count = 1 and l.last_probe_alive and e.base_url.same_string ("http://127.0.0.1:8080"))
			assert ("health probed through url_for", t.last_request.url.same_string ("http://127.0.0.1:8080/health") and t.last_request.timeout_seconds = 2)
			t.script_failure ({STRING_32} "refused")
			t.script (200, "{%"store%":true}")
			e := l.locate (cfg)
			assert ("primary when local is dead", not e.is_local and e.base_url.same_string ("https://rixchat.duckdns.org") and l.probe_count = 2)
			t.script_failure ({STRING_32} "refused")
			t.script_failure ({STRING_32} "no route to host")
			t.script (200, "{%"store%":true}")
			e := l.locate (cfg)
			assert ("standby when primary is dark", e.base_url.same_string ("https://sue-chat.duckdns.org") and l.found_alive and l.probe_count = 3)
			t.script_failure ({STRING_32} "a")
			t.script_failure ({STRING_32} "b")
			t.script_failure ({STRING_32} "c")
			e := l.locate (cfg)
			assert ("primary reported when everything is dark", not l.found_alive and not l.last_probe_alive and e.base_url.same_string ("https://rixchat.duckdns.org"))
			cfg.set_prefers_local (False)
			t.script (200, "ok")
			e := l.locate (cfg)
			assert ("no local probe when not preferred", l.probe_count = 1 and not e.is_local and l.last_probe_status = 200)
		end

	test_locator_with_no_server_configured
		local
			t: MEMORY_HTTP_TRANSPORT
			l: SERVICE_LOCATOR
			cfg: CLIENT_CONFIG
			e: CHAT_ENDPOINT
		do
			create t.make
			create l.make (t)
			create cfg.make_defaults
			t.script_failure ({STRING_32} "refused")
			e := l.locate (cfg)
			assert ("local endpoint although dead", e.is_local and e.base_url.same_string (cfg.local_url) and not l.found_alive and l.probe_count = 1 and not l.last_probe_alive and l.last_probe_status = 0)
			cfg.set_prefers_local (False)
			e := l.locate (cfg)
			assert ("nothing to probe, never remote", l.probe_count = 0 and e.is_local and not l.found_alive and t.exchange_count = 1)
			cfg.set_prefers_local (True)
			cfg.set_local_port (9090)
			t.script (503, "down")
			e := l.locate (cfg)
			assert ("a 503 is not alive", not l.last_probe_alive and l.last_probe_status = 503 and e.is_local and e.base_url.same_string ("http://127.0.0.1:9090"))
		end

feature -- EVENT_INBOX

	test_inbox_put_take_stop_laws
		local
			b: EVENT_INBOX
		do
			create b.make
			assert ("empty", b.count = 0 and b.take = Void and not b.is_stopped and not b.has_outage)
			b.put ("page one")
			b.put ("page two")
			assert ("two pages", b.count = 2 and b.pages_model.count = 2 and not b.is_full)
			assert ("oldest first", attached b.take as p1 and then p1.same_string ("page one"))
			assert ("then the next", attached b.take as p2 and then (p2.same_string ("page two") and b.count = 0))
			assert ("then nothing", b.take = Void and b.dropped = 0)
			b.report_outage ({STRING_32} "timed out")
			assert ("outage kept", b.has_outage and attached b.outage as o and then o.same_string ({STRING_32} "timed out"))
			b.report_outage ({STRING_32} "")
			assert ("an empty report is still an outage", b.has_outage and attached b.outage as o2 and then not o2.is_empty)
			b.report_recovery
			assert ("recovered", not b.has_outage)
			b.stop
			b.put ("late page")
			assert ("stopped: dropped and counted", b.is_stopped and b.count = 0 and b.dropped = 1)
		end

	test_inbox_refuses_when_full
		local
			b: EVENT_INBOX
			i: INTEGER
		do
			create b.make
			from i := 1 until i > {EVENT_INBOX}.Capacity loop
				b.put ("page " + i.out)
				i := i + 1
			end
			assert ("full", b.is_full and b.count = {EVENT_INBOX}.Capacity and b.dropped = 0)
			b.put ("one too many")
			assert ("dropped and counted", b.count = {EVENT_INBOX}.Capacity and b.dropped = 1)
			assert ("first out is the first in", attached b.take as p and then (p.same_string ("page 1") and not b.is_full))
			b.put ("room again")
			assert ("accepted once there is room", b.count = {EVENT_INBOX}.Capacity and b.dropped = 1)
		end

feature -- EVENT_POLLER

	test_poller_delivers_page_bytes_and_advances_cursor
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			b: EVENT_INBOX
			p: EVENT_POLLER
			l_bytes: STRING_8
		do
			create t.make
			c := logged_in_client (t)
			create b.make
			create p.make (c, 1, 0, b)
			l_bytes := wire_page (wire_message (1, 5, "one") + "," + wire_message (2, 5, "two") + "," + wire_message (3, 5, "three"), "")
			t.script (200, l_bytes)
			p.poll_once (0)
			assert ("cursor advanced, page delivered", p.cursor = 3 and p.delivered = 1 and b.count = 1 and p.polls = 1 and p.consecutive_failures = 0)
			assert ("the bytes, as they came", attached b.take as taken and then taken.same_string (l_bytes))
			assert ("asked from the cursor", t.last_request.url.same_string ("http://127.0.0.1:8080/rooms/1/wait?since=0&limit=200&seconds=0"))
			t.script (200, wire_page (wire_message (3, 5, "stale") + "," + wire_message (4, 5, "four"), ""))
			p.poll_once (25)
			assert ("a page violating the server's since-contract is refused whole", p.cursor = 3 and p.delivered = 1 and b.count = 0 and p.consecutive_failures = 1 and b.has_outage)
			assert ("and was asked after the cursor", t.last_request.url.has_substring ("since=3"))
			t.script (200, wire_page (wire_message (4, 5, "four"), wire_status (1, "Claude", "thinking")))
			p.poll_once (25)
			assert ("next page delivered", p.cursor = 4 and p.delivered = 2 and b.count = 1 and p.consecutive_failures = 0 and not b.has_outage)
			t.script (200, wire_page ("", wire_status (1, "Claude", "queued")))
			p.poll_once (25)
			assert ("statuses alone are news", p.cursor = 4 and p.delivered = 3 and b.count = 2)
			t.script (200, wire_page ("", ""))
			p.poll_once (25)
			assert ("an empty page delivers nothing", p.cursor = 4 and p.delivered = 3 and b.count = 2 and p.last_error = Void)
			t.script_failure ({STRING_32} "timed out")
			p.poll_once (25)
			assert ("failure counted, cursor kept, outage reported", p.consecutive_failures = 1 and p.cursor = 4 and p.last_error /= Void and b.has_outage and attached b.outage as o and then o.same_string ({STRING_32} "timed out"))
			t.script (200, wire_page ("", ""))
			p.poll_once (25)
			assert ("recovered", p.consecutive_failures = 0 and p.last_error = Void and p.polls = 7 and not b.has_outage and not p.session_lost)
		end

	test_poller_refuses_foreign_room_page_cursor_unchanged
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			b: EVENT_INBOX
			p: EVENT_POLLER
		do
			create t.make
			c := logged_in_client (t)
			create b.make
			create p.make (c, 1, 10, b)
			t.script (200, wire_page (wire_message (11, 5, "mine") + "," + wire_event (12, 2, 5, "message", "elsewhere"), ""))
			p.poll_once (0)
			assert ("cursor unchanged, nothing delivered, failure explained", p.cursor = 10 and p.delivered = 0 and b.count = 0 and p.consecutive_failures = 1 and is_error_status (p.last_error, 502))
			assert ("backing off", p.backoff_seconds = 1 and b.has_outage)
		end

	test_poller_401_loses_the_session_and_refuses_the_next_poll
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			b: EVENT_INBOX
			p: EVENT_POLLER
		do
			create t.make
			c := logged_in_client (t)
			create b.make
			create p.make (c, 1, 0, b)
			t.script (401, "{%"code%":%"bad_credentials%",%"message%":%"session expired%"}")
			p.poll_once (0)
			assert ("session lost", p.session_lost and p.consecutive_failures = 1 and is_error_status (p.last_error, 401))
			assert ("the GUI hears why", b.has_outage and attached b.outage as o and then o.same_string ({STRING_32} "session expired"))
			assert ("the next poll is refused", poll_is_refused (p))
			assert ("nothing else happened", p.polls = 1 and t.exchange_count = 2)
			p.run
			assert ("run with a lost session polls nothing", p.polls = 1)
			create p.make (c, 1, 0, b)
			t.script (401, "{%"code%":%"bad_credentials%",%"message%":%"gone%"}")
			p.run
			assert ("run ends on a 401 after one poll", p.session_lost and p.polls = 1)
			create b.make
			b.stop
			create p.make (c, 1, 0, b)
			p.run
			assert ("run on a stopped inbox polls nothing", p.polls = 0 and not p.session_lost)
		end

	test_poller_backoff_doubles_and_caps
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			b: EVENT_INBOX
			p: EVENT_POLLER
			i: INTEGER
			l_expected: ARRAY [INTEGER]
		do
			create t.make
			c := logged_in_client (t)
			create b.make
			create p.make (c, 1, 0, b)
			assert ("quiet when healthy", p.backoff_seconds = 0)
			l_expected := <<1, 2, 4, 8, 16, 30, 30, 30>>
			from i := 1 until i > l_expected.count loop
				t.script_failure ({STRING_32} "refused")
				p.poll_once (0)
				assert ("backoff after " + i.out + " failures", p.consecutive_failures = i and p.backoff_seconds = l_expected [i])
				i := i + 1
			end
			assert ("capped", p.backoff_seconds = {EVENT_POLLER}.Backoff_maximum_seconds)
			t.script (200, wire_page ("", ""))
			p.poll_once (0)
			assert ("quiet again", p.consecutive_failures = 0 and p.backoff_seconds = 0 and not b.has_outage)
		end

feature -- CHAT_PRESENTER

	test_presenter_unread_and_foreground_law
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			v: MEMORY_CHAT_VIEW
			n: MEMORY_NOTIFIER
			pr: CHAT_PRESENTER
			b, b2: EVENT_INBOX
		do
			create t.make
			c := logged_in_client (t)
			create v.make
			create n.make
			create pr.make (c, v, n)
			create b.make
			pr.remember (create {CHAT_MEMBER}.make (9, "nick", {STRING_32} "Nick", False, False))
			pr.open_room (1, 0, b)
			assert ("open", pr.is_room_open and pr.room_id = 1 and v.connected)
			v.set_foreground (False)
			b.put (wire_page (wire_message (1, 9, "hi larry") + "," + wire_message (2, 5, "my own echo"), ""))
			pr.pump
			assert ("both shown", v.shown_count = 2 and v.mine_count = 1 and pr.pages_pumped = 1 and b.count = 0)
			assert ("only the other's message is unread", pr.unread = 1 and n.unread = 1 and n.notify_count = 1)
			assert ("attributed", n.notices.first.starts_with ({STRING_32} "Nick: hi larry"))
			assert ("last seen", pr.last_seen_id = 2)
			pr.pump
			assert ("an empty pump changes nothing", pr.unread = 1 and n.unread = 1 and v.shown_count = 2 and pr.pages_pumped = 1)
			v.set_foreground (True)
			pr.pump
			assert ("foreground clears", pr.unread = 0 and n.unread = 0 and v.shown_count = 2)
			assert ("unknown sender named by id", pr.name_of (77).same_string ({STRING_32} "#77"))
			t.script (403, "{%"code%":%"not_member%",%"message%":%"not in this room%"}")
			pr.send ({STRING_32} "hello")
			assert ("send error shown, nothing else", v.errors.count = 1 and v.shown_count = 2 and t.last_request.url.ends_with ("/rooms/1/messages"))
			pr.close_room
			assert ("closed and the poller told through the inbox", not pr.is_room_open and b.is_stopped and pr.room_id = 0)
			create b2.make
			pr.open_room (1, 2, b2)
			assert ("reopened from where it left", pr.is_room_open and pr.last_seen_id = 2)
			t.script (200, "")
			pr.log_out
			assert ("logged out and closed", not pr.is_room_open and not c.is_logged_in and b2.is_stopped)
		end

	test_presenter_pumps_two_pages_from_inbox
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			v: MEMORY_CHAT_VIEW
			n: MEMORY_NOTIFIER
			pr: CHAT_PRESENTER
			b: EVENT_INBOX
		do
			create t.make
			c := logged_in_client (t)
			create v.make
			create n.make
			create pr.make (c, v, n)
			create b.make
			pr.open_room (1, 0, b)
			b.put (wire_page (wire_message (1, 9, "one") + "," + wire_message (2, 9, "two"), ""))
			b.put (wire_page (wire_message (3, 9, "three"), wire_status (1, "Claude", "thinking")))
			pr.pump
			assert ("both pages shown in order", v.shown_count = 3 and v.shown_ids [1] = 1 and v.shown_ids [2] = 2 and v.shown_ids [3] = 3 and pr.pages_pumped = 2 and b.count = 0 and pr.last_seen_id = 3)
			assert ("status shown", v.status.same_string ({STRING_32} "Claude thinking"))
			assert ("in front: nothing unread, no notice", pr.unread = 0 and n.notify_count = 0 and n.unread = 0)
			b.put ("garbage")
			pr.pump
			assert ("garbage is an error, not an exception", v.errors.count = 1 and v.shown_count = 3 and pr.pages_pumped = 3)
			b.put (wire_page (wire_event (4, 2, 9, "message", "elsewhere"), wire_status (2, "Claude", "elsewhere")))
			pr.pump
			assert ("foreign-room content is skipped", v.shown_count = 3 and v.status.same_string ({STRING_32} "Claude thinking") and pr.last_seen_id = 3 and pr.pages_pumped = 4)
		end

	test_presenter_foreground_toggled_mid_pump
			-- Every shown event brings the window to the front or sends it back; the laws still hold.
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			v: MEMORY_CHAT_VIEW
			n: MEMORY_NOTIFIER
			pr: CHAT_PRESENTER
			b: EVENT_INBOX
		do
			create t.make
			c := logged_in_client (t)
			create v.make
			create n.make
			create pr.make (c, v, n)
			create b.make
			pr.open_room (1, 0, b)
			v.set_foreground (False)
			v.set_flips_on_show (True)
			b.put (wire_page (wire_message (1, 9, "a") + "," + wire_message (2, 9, "b") + "," + wire_message (3, 9, "c") + "," + wire_message (4, 9, "d"), ""))
			pr.pump
			assert ("all shown", v.shown_count = 4)
			assert ("ends in the back with the two seen while in the back unread", not v.is_foreground and pr.unread = 2 and n.unread = 2 and n.notify_count = 2)
			b.put (wire_page (wire_message (5, 9, "e"), ""))
			pr.pump
			assert ("ends in front: cleared", v.is_foreground and pr.unread = 0 and n.unread = 0 and n.notify_count = 2)
			assert ("badge matches either way", n.unread = pr.unread)
		end

	test_presenter_foreground_pump_receives_others_message_quietly
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			v: MEMORY_CHAT_VIEW
			n: MEMORY_NOTIFIER
			pr: CHAT_PRESENTER
			b: EVENT_INBOX
		do
			create t.make
			c := logged_in_client (t)
			create v.make
			create n.make
			create pr.make (c, v, n)
			create b.make
			pr.open_room (1, 0, b)
			b.put (wire_page (wire_message (1, 9, "hi"), ""))
			pr.pump
			assert ("shown, not unread, no notice", v.is_foreground and v.shown_count = 1 and pr.unread = 0 and n.unread = 0 and n.notify_count = 0 and v.mine_count = 0)
		end

	test_presenter_system_events_and_name_collisions
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			v: MEMORY_CHAT_VIEW
			n: MEMORY_NOTIFIER
			pr: CHAT_PRESENTER
			b: EVENT_INBOX
		do
			create t.make
			c := logged_in_client (t)
			create v.make
			create n.make
			create pr.make (c, v, n)
			pr.remember (create {CHAT_MEMBER}.make (9, "nick", {STRING_32} "Nick", False, False))
			pr.remember (create {CHAT_MEMBER}.make (10, "nick2", {STRING_32} "Nick", False, False))
			pr.remember (create {CHAT_MEMBER}.make (11, "sue", {STRING_32} "Sue", False, False))
			assert ("system", pr.name_of (0).same_string ({STRING_32} "system"))
			assert ("collision disambiguated", pr.name_of (9).same_string ({STRING_32} "Nick (@nick)") and pr.name_of (10).same_string ({STRING_32} "Nick (@nick2)"))
			assert ("no collision, plain", pr.name_of (11).same_string ({STRING_32} "Sue") and not pr.has_name_twin (11) and pr.has_name_twin (9))
			create b.make
			pr.open_room (1, 0, b)
			v.set_foreground (False)
			b.put (wire_page (wire_event (1, 1, 0, "system", "Nick joined") + "," + wire_message (2, 9, "hello"), ""))
			pr.pump
			assert ("system event shown but neither unread nor rung", v.shown_count = 2 and pr.unread = 1 and n.unread = 1 and n.notify_count = 1 and n.notices.first.starts_with ({STRING_32} "Nick (@nick): hello"))
		end

	test_presenter_outage_reported_once
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			v: MEMORY_CHAT_VIEW
			n: MEMORY_NOTIFIER
			pr: CHAT_PRESENTER
			b: EVENT_INBOX
		do
			create t.make
			c := logged_in_client (t)
			create v.make
			create n.make
			create pr.make (c, v, n)
			create b.make
			pr.open_room (1, 0, b)
			b.report_outage ({STRING_32} "connection refused")
			pr.pump
			pr.pump
			assert ("shown once per outage", v.errors.count = 1 and pr.reported_outage and v.errors.first.same_string ({STRING_32} "connection refused"))
			b.report_recovery
			pr.pump
			assert ("recovered, latch released", not pr.reported_outage and v.errors.count = 1)
			b.report_outage ({STRING_32} "timed out")
			pr.pump
			assert ("a new outage is shown again", v.errors.count = 2 and pr.reported_outage and v.errors.last.same_string ({STRING_32} "timed out"))
		end

	test_presenter_load_roster_success_and_error
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			v: MEMORY_CHAT_VIEW
			n: MEMORY_NOTIFIER
			pr: CHAT_PRESENTER
		do
			create t.make
			c := logged_in_client (t)
			create v.make
			create n.make
			create pr.make (c, v, n)
			t.script (200, "{%"members%":[" + member_json (9, "nick", "Nick") + "," + member_json (11, "sue", "Sue") + "]}")
			pr.load_roster (1)
			assert ("remembered", pr.knows (9) and pr.knows (11) and pr.name_of (11).same_string ({STRING_32} "Sue") and v.errors.is_empty)
			t.script (403, "{%"code%":%"not_member%",%"message%":%"not in this room%"}")
			pr.load_roster (1)
			assert ("error shown, roster kept", v.errors.count = 1 and pr.knows (9) and pr.knows (11))
			t.script_failure ({STRING_32} "refused")
			pr.load_roster (1)
			assert ("transport failure shown too", v.errors.count = 2 and v.errors.last.same_string ({STRING_32} "refused"))
			t.script (200, "not json")
			pr.load_roster (1)
			assert ("garbage is an error, not an exception", v.errors.count = 3 and pr.members_model.count = 2)
		end

feature {NONE} -- Fixtures

	loopback: CHAT_ENDPOINT
		do
			create Result.make ("http://127.0.0.1:8080")
		end

	logged_in_client (a_transport: MEMORY_HTTP_TRANSPORT): CHAT_CLIENT
			-- A client logged in as user 5 ("larry") through one scripted reply.
		local
			r: CHAT_RESULT [CHAT_MEMBER]
		do
			create Result.make (a_transport, loopback)
			a_transport.script (200, login_reply (hex64))
			r := Result.login ("larry", {STRING_32} "correct horse battery staple")
			check logged_in: Result.is_logged_in end
		end

	login_reply (a_token: STRING_8): STRING_8
			-- A login reply for user 5 ("larry", admin) carrying `a_token'.
		do
			Result := "{%"token%":%"" + a_token + "%",%"member%":{%"id%":5,%"username%":%"larry%",%"display_name%":%"Larry%",%"is_admin%":true,%"is_bot%":false}}"
		end

	wire_event (a_id, a_room, a_sender: INTEGER_64; a_kind, a_body: STRING_8): STRING_8
			-- One event in wire form.
		do
			Result := "{%"id%":" + a_id.out + ",%"room_id%":" + a_room.out + ",%"sender_id%":" + a_sender.out
				+ ",%"kind%":%"" + a_kind + "%",%"created_at%":%"2026-08-29T12:00:00%",%"body%":%"" + a_body + "%",%"attachment%":null,%"payload%":{},%"is_bot%":false}"
		end

	wire_message (a_id, a_sender: INTEGER_64; a_body: STRING_8): STRING_8
			-- One message event in wire form, room 1.
		do
			Result := wire_event (a_id, 1, a_sender, "message", a_body)
		end

	wire_status (a_room: INTEGER_64; a_from, a_text: STRING_8): STRING_8
		do
			Result := "{%"room_id%":" + a_room.out + ",%"from%":%"" + a_from + "%",%"text%":%"" + a_text + "%"}"
		end

	wire_page (a_events, a_statuses: STRING_8): STRING_8
			-- A page in wire form from comma-separated event and status objects.
		do
			Result := "{%"events%":[" + a_events + "],%"statuses%":[" + a_statuses + "]}"
		end

	member_json (a_id: INTEGER_64; a_username, a_display: STRING_8): STRING_8
		do
			Result := "{%"id%":" + a_id.out + ",%"username%":%"" + a_username + "%",%"display_name%":%"" + a_display + "%",%"is_admin%":false,%"is_bot%":false}"
		end

	is_error_status (a_error: detachable CHAT_ERROR; a_status: INTEGER): BOOLEAN
			-- Is `a_error' there, with `a_status'?
		do
			Result := attached a_error as e and then e.http_status = a_status
		end

	poll_is_refused (a_poller: EVENT_POLLER): BOOLEAN
			-- Does `poll_once' refuse to run (a precondition violation, caught here)?
		local
			l_refused: BOOLEAN
		do
			if l_refused then
				Result := True
			else
				a_poller.poll_once (0)
			end
		rescue
			l_refused := True
			retry
		end

	hex64: STRING_8
		do
			Result := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
		end

end
