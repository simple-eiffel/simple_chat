note
	description: "[
		DYNAMIC_DNS over Duck DNS: one HTTPS GET to the update URL every
		`interval_seconds'; the address is detected server-side when
		omitted; OK or KO comes back. The token never reaches a log:
		`update_url' is the exact request with the token masked, and the
		domains are validated so nothing can smuggle a second parameter.
		Phase 4 issues the request through simple_winhttp.
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
		ensure
			set: domains.same_string (a_domains) and interval_seconds = a_interval_seconds
			never_yet: last_result.same_string (Result_never) and update_count = 0
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

feature -- Basic operations

	update
		do
			update_count := update_count + 1
			create last_update_at.make_now
			last_result := Result_unreachable
			-- Implementation in Phase 4: GET Base_url + domains + "&token=" + token; "OK" -> Result_ok, "KO" -> Result_ko
		end

feature -- Constants

	Base_url: STRING_8 = "https://www.duckdns.org/update?domains="
	Masked_token: STRING_8 = "&token=****"

feature {NONE} -- Implementation

	token: STRING_8
			-- Never logged (DR-012).

invariant
	token_given: not token.is_empty
	known_result: is_known_result (last_result)
	count_non_negative: update_count >= 0
	token_not_in_url: not update_url.has_substring (token)

end
