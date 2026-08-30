note
	description: "[
		DYNAMIC_DNS over Duck DNS: one HTTPS GET to the update URL every
		`interval_seconds'; the address is detected server-side when
		omitted; OK or KO comes back. The token never reaches a log.
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
			given: not a_domains.is_empty and not a_token.is_empty
			positive: a_interval_seconds > 0
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
			-- The request, without the token (safe to log).
		do
			Result := "https://www.duckdns.org/update?domains=" + domains + "&token=****"
		ensure
			no_token: not Result.has_substring (token)
		end

feature -- Basic operations

	update
		do
			update_count := update_count + 1
			create last_update_at.make_now
			last_result := Result_unreachable
			-- Implementation in Phase 4: GET update_url with the real token; "OK" -> Result_ok, "KO" -> Result_ko
		end

feature {NONE} -- Implementation

	token: STRING_8
			-- Never logged (DR-012).

invariant
	given: not domains.is_empty and not token.is_empty
	interval_positive: interval_seconds > 0
	known_result: is_known_result (last_result)
	count_non_negative: update_count >= 0

end
