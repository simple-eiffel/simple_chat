note
	description: "DYNAMIC_DNS's validation rules (domain labels) usable without an updater - SERVER_CONFIG checks domains before any updater exists."
	author: "Larry Rix"

class
	NO_DNS_RULES

inherit
	DYNAMIC_DNS

feature -- Access

	domains: STRING_8
		once
			Result := "none"
		end

	interval_seconds: INTEGER
		do
			Result := Minimum_interval_seconds
		end

	last_result: STRING_8
		do
			Result := Result_never
		end

	last_update_at: detachable SIMPLE_DATE_TIME
		do
		end

	update_count: INTEGER
		do
		end

feature -- Basic operations

	update
		do
		end

end
