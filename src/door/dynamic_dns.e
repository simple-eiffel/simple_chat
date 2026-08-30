note
	description: "[
		Keeps a public name pointed at this host's current address (D-005).
		Duck DNS in the server's ops cluster; this contract in the library.
		Under SCOOP the updater ticks on its own processor.
	]"
	author: "Larry Rix"

deferred class
	DYNAMIC_DNS

feature -- Access

	domains: STRING_8
			-- What is updated: one or more labels, comma-separated.
		deferred
		ensure
			given: not Result.is_empty
		end

	interval_seconds: INTEGER
		deferred
		ensure
			at_least_a_minute: Result >= Minimum_interval_seconds
		end

	last_result: STRING_8
			-- `Result_never', `Result_ok', `Result_ko' or `Result_unreachable'.
		deferred
		ensure
			known: is_known_result (Result)
		end

	last_update_at: detachable SIMPLE_DATE_TIME
		deferred
		end

	update_count: INTEGER
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Basic operations

	update
			-- One attempt; never raises.
		deferred
		ensure
			attempted: update_count = old update_count + 1
			timed: last_update_at /= Void
			reported: not last_result.same_string (Result_never)
			settings_unchanged: domains.same_string (old domains.twin) and interval_seconds = old interval_seconds
		end

feature -- Validation (contract support)

	is_known_result (a_result: READABLE_STRING_8): BOOLEAN
		do
			Result := a_result.same_string (Result_never) or a_result.same_string (Result_ok)
				or a_result.same_string (Result_ko) or a_result.same_string (Result_unreachable)
		end

	is_valid_domains (a_domains: READABLE_STRING_8): BOOLEAN
			-- [a-z0-9-]+ (,[a-z0-9-]+)* - labels only, so nothing can smuggle another query parameter.
		local
			l_parts: LIST [READABLE_STRING_8]
		do
			Result := not a_domains.is_empty
			if Result then
				l_parts := a_domains.split (',')
				Result := across l_parts as p all is_domain_label (p) end
			end
		end

	is_domain_label (a_label: READABLE_STRING_8): BOOLEAN
		local
			i: INTEGER
			c: CHARACTER_8
		do
			Result := a_label.count >= 1 and a_label.count <= 63
			from
				i := 1
			until
				i > a_label.count or not Result
			loop
				c := a_label [i]
				Result := (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c = '-'
				i := i + 1
			end
		end

feature -- Constants

	Result_never: STRING_8 = "never"
	Result_ok: STRING_8 = "ok"
	Result_ko: STRING_8 = "ko"
	Result_unreachable: STRING_8 = "unreachable"

	Minimum_interval_seconds: INTEGER = 60
			-- Duck DNS asks for no more than a few updates a minute; one a minute is plenty.

invariant
	domains_valid: is_valid_domains (domains)

end
