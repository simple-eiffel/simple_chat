note
	description: "[
		Sliding-window counts per key - "ai:<user>", "post:<user>",
		"login:user:<name>", "login:ip:<ip>" - each key prefix with its own
		limit per window. Guarded by its own lock (middle of the order:
		store < limiter < bus). Lives in memory: only the host can restart
		the server (intent-v2 Q9). Both tables carry models, so every
		command says what it left alone.
	]"
	author: "Larry Rix"

class
	RATE_LIMITER

create
	make

feature {NONE} -- Initialization

	make (a_window_seconds: INTEGER)
		require
			positive: a_window_seconds > 0
		do
			window_seconds := a_window_seconds
			create counts.make (32)
			create limits.make (8)
			create lock.make
		ensure
			window_set: window_seconds = a_window_seconds
			no_counts: counts_model.is_empty
			no_limits: limits_model.is_empty
		end

feature -- Model Queries (for MML postconditions)

	counts_model: MML_MAP [STRING_8, INTEGER]
			-- Current count per key within the window.
		do
			create Result
			across counts as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = counts.count
		end

	limits_model: MML_MAP [STRING_8, INTEGER]
			-- Configured limit per key prefix.
		do
			create Result
			across limits as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = limits.count
		end

feature -- Access

	window_seconds: INTEGER

	limit_for (a_key: READABLE_STRING_8): INTEGER
			-- The limit whose prefix `a_key' starts with; `Default_limit' otherwise.
		do
			Result := Default_limit
			-- Implementation in Phase 4 (longest matching prefix)
		ensure
			positive: Result > 0
			configured_or_default: limits_model.is_empty implies Result = Default_limit
		end

	count (a_key: READABLE_STRING_8): INTEGER
			-- Events recorded for `a_key' inside the current window.
		do
			-- Implementation in Phase 4
		ensure
			non_negative: Result >= 0
			unknown_is_zero: not counts_model.domain.has (a_key.to_string_8) implies Result = 0
		end

feature -- Status report

	is_allowed (a_key: READABLE_STRING_8): BOOLEAN
		do
			Result := count (a_key) < limit_for (a_key)
		ensure
			definition: Result = (count (a_key) < limit_for (a_key))
		end

feature -- Element change

	set_limit (a_prefix: READABLE_STRING_8; a_limit: INTEGER)
			-- Keys beginning with `a_prefix' allow `a_limit' per window.
		require
			prefix_given: not a_prefix.is_empty
			positive: a_limit > 0
		do
			limits.force (a_limit, a_prefix.to_string_8)
		ensure
			set: limits_model |=| (old limits_model).updated (a_prefix.to_string_8, a_limit)
			counts_unchanged: counts_model |=| old counts_model
		end

	record (a_key: READABLE_STRING_8)
			-- Count one event for `a_key' now.
		require
			allowed: is_allowed (a_key)
		do
			-- Implementation in Phase 4 (under `lock')
		ensure
			counted: count (a_key) = old count (a_key) + 1
			others_unchanged: (counts_model.removed (a_key.to_string_8)) |=| ((old counts_model).removed (a_key.to_string_8))
			limits_unchanged: limits_model |=| old limits_model
		end

	prune
			-- Forget events older than the window.
		do
			-- Implementation in Phase 4
		ensure
			never_grows: counts_model.domain.count <= (old counts_model).domain.count
			only_shrinks: across counts as ic all (old counts_model).domain.has (@ic.key) and then ic <= (old counts_model) [@ic.key] end
			limits_unchanged: limits_model |=| old limits_model
		end

feature -- Constants

	Default_limit: INTEGER = 1000000
			-- Effectively unlimited, for keys nobody configured.

feature {NONE} -- Implementation

	counts: HASH_TABLE [INTEGER, STRING_8]
			-- Phase 4 keeps timestamps per key; this holds the window counts.

	limits: HASH_TABLE [INTEGER, STRING_8]

	lock: MUTEX

invariant
	window_positive: window_seconds > 0
	never_over: across counts as ic all ic <= limit_for (@ic.key) end
	models_consistent: counts_model.count = counts.count and limits_model.count = limits.count

end
