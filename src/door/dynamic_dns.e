note
	description: "Keeps a public name pointed at this host's current address (D-005). Duck DNS in the server's ops cluster; this contract in the library."
	author: "Larry Rix"

deferred class
	DYNAMIC_DNS

feature -- Access

	domains: STRING_8
			-- What is updated.
		deferred
		ensure
			given: not Result.is_empty
		end

	interval_seconds: INTEGER
		deferred
		ensure
			positive: Result > 0
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
		end

feature -- Validation (contract support)

	is_known_result (a_result: READABLE_STRING_8): BOOLEAN
		do
			Result := a_result.same_string (Result_never) or a_result.same_string (Result_ok)
				or a_result.same_string (Result_ko) or a_result.same_string (Result_unreachable)
		end

feature -- Constants

	Result_never: STRING_8 = "never"
	Result_ok: STRING_8 = "ok"
	Result_ko: STRING_8 = "ko"
	Result_unreachable: STRING_8 = "unreachable"

end
