note
	description: "[
		DYNAMIC_DNS over Duck DNS: one HTTPS GET to the update URL every
		`interval_seconds'; the address is detected server-side when
		omitted; OK or KO comes back in the body. The token never reaches
		a log: `update_url' is the request with the token masked and stays
		the only inspectable URL - the real URL is assembled privately,
		the domains are validated so nothing can smuggle a second
		parameter, and an invariant holds `last_result' free of the token.
		A transport failure is `Result_unreachable', never an exception.
		The request goes through simple_http (libcurl) with bounded
		timeouts.
	]"
	author: "Larry Rix"

class
	DUCKDNS_UPDATER

inherit
	DYNAMIC_DNS

create
	make

feature {NONE} -- Initialization

	make (a_domains, a_token: READABLE_STRING_8; a_interval_seconds: INTEGER)
		require
			domains_valid: is_valid_domains (a_domains)
			token_given: not a_token.is_empty
			at_least_a_minute: a_interval_seconds >= Minimum_interval_seconds
		do
			domains := a_domains.to_string_8
			token := a_token.to_string_8
			interval_seconds := a_interval_seconds
			last_result := Result_never
			service_base := Base_url.twin
		ensure
			set: domains.same_string (a_domains) and interval_seconds = a_interval_seconds
			never_yet: last_result.same_string (Result_never) and update_count = 0
			real_service: service_base.same_string (Base_url)
		end

feature -- Access

	domains: STRING_8
	interval_seconds: INTEGER
	last_result: STRING_8
	last_update_at: detachable SIMPLE_DATE_TIME
	update_count: INTEGER

	update_url: STRING_8
			-- The request with the token masked (safe to log).
		do
			Result := Base_url + domains + Masked_token
		ensure
			definition: Result.same_string (Base_url + domains + Masked_token)
			no_token: not Result.has_substring (token)
		end

feature {CHAT_TEST_BRIDGE} -- Test support

	set_service_base (a_base: READABLE_STRING_8)
			-- Send the real request to `a_base' instead of Duck DNS: lets
			-- tests prove the failure path against an unroutable address
			-- without touching the network. `update_url' (the masked,
			-- loggable form) keeps naming the real service on purpose.
		require
			base_given: not a_base.is_empty
			http_like: a_base.starts_with ("http")
		do
			service_base := a_base.to_string_8
		ensure
			taken: service_base.same_string (a_base)
			count_kept: update_count = old update_count
		end

feature -- Basic operations

	update
			-- One GET against the service: "OK" is `Result_ok', "KO" is
			-- `Result_ko'; anything else - a transport failure, a strange
			-- status, a strange body - is `Result_unreachable'. Never
			-- raises; never lets the token into anything inspectable.
		local
			l_http: SIMPLE_HTTP
			l_response: SIMPLE_HTTP_RESPONSE
			l_body: STRING_8
			l_failed: BOOLEAN
		do
			if not l_failed then
				update_count := update_count + 1
				create last_update_at.make_now
				last_result := Result_unreachable
				create l_http.make
				l_http.set_timeout (Request_timeout_seconds)
				l_http.set_connect_timeout (Connect_timeout_seconds)
				l_response := l_http.get (real_update_url)
				if not l_response.error_occurred and then l_response.is_success and then attached l_response.body as al_body then
					create l_body.make_from_string (al_body)
					l_body.left_adjust
					l_body.right_adjust
					if l_body.starts_with ("OK") then
						last_result := Result_ok
					elseif l_body.starts_with ("KO") then
						last_result := Result_ko
					end
				end
			end
				-- On the retried path the attempt was already counted and
				-- `last_result' already reads unreachable.
		ensure then
			token_hidden: not last_result.has_substring (token)
		rescue
			if not l_failed then
				l_failed := True
				retry
			end
		end

feature -- Constants

	Base_url: STRING_8 = "https://www.duckdns.org/update?domains="
	Masked_token: STRING_8 = "&token=****"

feature {NONE} -- Implementation

	token: STRING_8
			-- Never logged (DR-012).

	service_base: STRING_8
			-- Where the real request goes: `Base_url' in production; tests
			-- may point it at an unroutable address (`set_service_base').

	real_update_url: STRING_8
			-- The actual request: the token in full, an empty ip so the
			-- service detects the address. Never logged, never inspectable:
			-- `update_url' is its masked public face.
		do
			create Result.make (service_base.count + domains.count + token.count + 16)
			Result.append (service_base)
			Result.append (domains)
			Result.append ("&token=")
			Result.append (token)
			Result.append ("&ip=")
		ensure
			carries_token: Result.has_substring (token)
		end

	Request_timeout_seconds: INTEGER = 10
			-- The whole-request bound on the GET.

	Connect_timeout_seconds: INTEGER = 5
			-- The connection bound on the GET.

invariant
	token_given: not token.is_empty
	known_result: is_known_result (last_result)
	count_non_negative: update_count >= 0
	token_not_in_url: not update_url.has_substring (token)
	token_not_in_result: not last_result.has_substring (token)
	service_base_given: not service_base.is_empty

end
