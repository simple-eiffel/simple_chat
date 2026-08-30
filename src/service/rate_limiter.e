note
	description: "[
		Sliding-window limits per key - "post:<user>", "login:user:<name>",
		"login:ip:<ip>", "p:<handle>:<asker>" - where each configured key
		PREFIX carries its own maximum and its own window (`set_limit'):
		thirty posts a minute and ten login failures in ten minutes are two
		rules, not one window. Keys no rule covers get `Default_limit' per
		`window_seconds' - effectively unlimited, and named so in the
		contracts (`has_rule_for').

		Owned by the service's processor (approach section 8): no lock. In
		memory only - a restart forgets every count (intent-v2 Q9).

		Three numbers per key, so the contracts are exact without a clock
		in them: `count' is what is HELD (timestamps not yet pruned; pruned
		only by the commands `record' and `prune', never by a query);
		`live_count' is what falls inside the key's window now - the one
		`is_allowed' uses; `total' is how many times the key was recorded
		since it last had nothing live - the number a postcondition can
		name as `old total + 1'. Every `Sweep_every'-th record sweeps every
		key (keys with nothing live are dropped, totals with them), so a
		flood of attacker-chosen keys cannot grow memory without bound.

		`advance' moves this limiter's clock forward - the assault's way to
		let a window pass without waiting ten minutes.
	]"
	author: "Larry Rix"

class
	RATE_LIMITER

create
	make

feature {NONE} -- Initialization

	make (a_window_seconds: INTEGER)
			-- A limiter whose unconfigured keys allow `Default_limit' per `a_window_seconds'.
		require
			positive: a_window_seconds > 0
		do
			window_seconds := a_window_seconds
			create entries.make (32)
			create totals.make (32)
			create limits.make (8)
			create windows.make (8)
		ensure
			window_set: window_seconds = a_window_seconds
			no_counts: counts_model.is_empty
			no_limits: limits_model.is_empty
			nothing_recorded: records = 0
			clock_unmoved: offset_seconds = 0
		end

feature -- Model Queries (for MML postconditions)

	counts_model: MML_MAP [STRING_8, INTEGER]
			-- Held entries per key.
		do
			create Result
			across entries as ic loop
				Result := Result.updated (@ic.key, ic.count)
			end
		ensure
			same_count: Result.count = entries.count
		end

	limits_model: MML_MAP [STRING_8, INTEGER]
			-- Maximum per configured prefix.
		do
			create Result
			across limits as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = limits.count
		end

	windows_model: MML_MAP [STRING_8, INTEGER]
			-- Window (seconds) per configured prefix.
		do
			create Result
			across windows as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = windows.count
		end

feature -- Access

	window_seconds: INTEGER
			-- The window of every key no rule covers.

	records: INTEGER
			-- `record' calls so far.

	last_pruned: INTEGER
			-- Entries the last `record' dropped from its own key before counting.

	offset_seconds: INTEGER_64
			-- How far `advance' has moved this limiter's clock.

	matching_prefix (a_key: READABLE_STRING_8): detachable STRING_8
			-- The longest configured prefix `a_key' starts with; Void when none.
		do
			across limits as ic loop
				if a_key.starts_with (@ic.key) and then (not attached Result as r or else @ic.key.count > r.count) then
					Result := @ic.key
				end
			end
		ensure
			a_prefix: attached Result as p implies (a_key.starts_with (p) and limits_model.domain.has (p))
			the_longest: attached Result as p2 implies across limits as ic all (a_key.starts_with (@ic.key) implies @ic.key.count <= p2.count) end
			none_when_unmatched: Result = Void implies across limits as ic all not a_key.starts_with (@ic.key) end
		end

	has_rule_for (a_key: READABLE_STRING_8): BOOLEAN
			-- Does a configured prefix cover `a_key'?
		do
			Result := matching_prefix (a_key) /= Void
		ensure
			definition: Result = (matching_prefix (a_key) /= Void)
		end

	limit_for (a_key: READABLE_STRING_8): INTEGER
			-- The maximum of the longest matching prefix; `Default_limit' when none.
		do
			if attached matching_prefix (a_key) as p then
				Result := limits.item (p)
			else
				Result := Default_limit
			end
		ensure
			positive: Result > 0
			by_prefix: attached matching_prefix (a_key) as p implies Result = limits_model [p]
			configured_or_default: not has_rule_for (a_key) implies Result = Default_limit
		end

	window_for (a_key: READABLE_STRING_8): INTEGER
			-- The window of the longest matching prefix; `window_seconds' when none.
		do
			if attached matching_prefix (a_key) as p then
				Result := windows.item (p)
			else
				Result := window_seconds
			end
		ensure
			positive: Result > 0
			by_prefix: attached matching_prefix (a_key) as p implies Result = windows_model [p]
			default_otherwise: not has_rule_for (a_key) implies Result = window_seconds
		end

	count (a_key: READABLE_STRING_8): INTEGER
			-- Entries held for `a_key' - live, or expired and not yet pruned.
		do
			if attached entries.item (a_key.to_string_8) as l then
				Result := l.count
			end
		ensure
			non_negative: Result >= 0
			unknown_is_zero: not counts_model.domain.has (a_key.to_string_8) implies Result = 0
			from_model: counts_model.domain.has (a_key.to_string_8) implies Result = counts_model [a_key.to_string_8]
		end

	live_count (a_key: READABLE_STRING_8): INTEGER
			-- Entries for `a_key' inside its window as of `now_seconds'.
		local
			l_since: INTEGER_64
		do
			if attached entries.item (a_key.to_string_8) as l then
				l_since := now_seconds - window_for (a_key)
				across l as ts loop
					if ts > l_since then
						Result := Result + 1
					end
				end
			end
		ensure
			non_negative: Result >= 0
			within_held: Result <= count (a_key)
		end

	total (a_key: READABLE_STRING_8): INTEGER
			-- Times `a_key' was recorded since it last had nothing live.
		do
			Result := totals.item (a_key.to_string_8)
		ensure
			non_negative: Result >= 0
			at_least_held: Result >= count (a_key)
		end

	now_seconds: INTEGER_64
			-- Seconds since the epoch, plus whatever `advance' added.
		do
			Result := clock_seconds + offset_seconds
		ensure
			moved: Result >= offset_seconds
		end

feature -- Status report

	is_allowed (a_key: READABLE_STRING_8): BOOLEAN
			-- May `a_key' be recorded once more now?
		do
			Result := live_count (a_key) < limit_for (a_key)
		ensure
			granted_is_under: Result implies live_count (a_key) < limit_for (a_key)
			refused_is_full: not Result implies count (a_key) >= limit_for (a_key)
		end

feature -- Element change

	set_limit (a_prefix: READABLE_STRING_8; a_maximum, a_window_seconds: INTEGER)
			-- Keys beginning with `a_prefix' allow `a_maximum' per `a_window_seconds'.
		require
			prefix_given: not a_prefix.is_empty
			positive: a_maximum > 0
			window_positive: a_window_seconds > 0
		do
			limits.force (a_maximum, a_prefix.to_string_8)
			windows.force (a_window_seconds, a_prefix.to_string_8)
		ensure
			set: limits_model |=| (old limits_model).updated (a_prefix.to_string_8, a_maximum)
			window_set: windows_model |=| (old windows_model).updated (a_prefix.to_string_8, a_window_seconds)
			applies: limit_for (a_prefix) = a_maximum and window_for (a_prefix) = a_window_seconds
			counts_unchanged: counts_model |=| old counts_model
			records_unchanged: records = old records
		end

	record (a_key: READABLE_STRING_8)
			-- Count one event for `a_key' now: every `Sweep_every'-th call sweeps
			-- all keys first, then the key's own expired entries go, then the entry.
		require
			allowed: is_allowed (a_key)
		local
			l_key: STRING_8
			l_now: INTEGER_64
			l_total: INTEGER
			l_list: ARRAYED_LIST [INTEGER_64]
		do
			l_key := a_key.to_string_8
			l_now := now_seconds
			l_total := totals.item (l_key)
			records := records + 1
			if records \\ Sweep_every = 0 then
				prune_all_at (l_now)
			end
			last_pruned := prune_key_at (l_key, l_now)
			if attached entries.item (l_key) as l then
				l_list := l
			else
				create l_list.make (8)
				entries.force (l_list, l_key)
			end
			l_list.extend (l_now)
			totals.force (l_total + 1, l_key)
		ensure
			one_more_record: records = old records + 1
			counted: total (a_key) = old total (a_key) + 1
			held: (old records + 1) \\ Sweep_every /= 0 implies count (a_key) = old count (a_key) + 1 - last_pruned
			live: live_count (a_key) >= 1
			live_within: live_count (a_key) <= limit_for (a_key)
			others_unchanged: (old records + 1) \\ Sweep_every /= 0 implies (counts_model.removed (a_key.to_string_8)) |=| ((old counts_model).removed (a_key.to_string_8))
			limits_unchanged: limits_model |=| old limits_model and windows_model |=| old windows_model
		end

	prune
			-- Forget every expired entry; keys with nothing left go, and their totals with them.
		do
			prune_all_at (now_seconds)
		ensure
			never_grows: counts_model.domain.count <= (old counts_model).domain.count
			only_shrinks: across entries as ic all ((old counts_model).domain.has (@ic.key) and then ic.count <= (old counts_model) [@ic.key]) end
			no_empty_keys: across entries as ic all ic.count > 0 end
			records_unchanged: records = old records
			limits_unchanged: limits_model |=| old limits_model and windows_model |=| old windows_model
		end

	advance (a_seconds: INTEGER)
			-- Move this limiter's clock forward (the assault's way to let a window pass).
		require
			non_negative: a_seconds >= 0
		do
			offset_seconds := offset_seconds + a_seconds
		ensure
			moved: offset_seconds = old offset_seconds + a_seconds
			counts_unchanged: counts_model |=| old counts_model
			records_unchanged: records = old records
		end

feature -- Constants

	Default_limit: INTEGER = 1000000
			-- Effectively unlimited, for keys nobody configured.

	Sweep_every: INTEGER = 256
			-- Records between two sweeps of every key.

feature {NONE} -- Implementation

	entries: HASH_TABLE [ARRAYED_LIST [INTEGER_64], STRING_8]
			-- Timestamps (seconds) held per key, oldest first.

	totals: HASH_TABLE [INTEGER, STRING_8]
			-- Records per key since it last had nothing live.

	limits: HASH_TABLE [INTEGER, STRING_8]
			-- Maximum per prefix.

	windows: HASH_TABLE [INTEGER, STRING_8]
			-- Window per prefix.

	clock_seconds: INTEGER_64
			-- Seconds since 1970-01-01T00:00:00Z.
		local
			l_now: SIMPLE_DATE_TIME
		do
			create l_now.make_now_utc
			Result := l_now.to_timestamp
		ensure
			after_the_epoch: Result >= 0
		end

	prune_key_at (a_key: STRING_8; a_now: INTEGER_64): INTEGER
			-- Drop `a_key''s entries at or before `a_now' less its window; how many went.
		local
			l_since: INTEGER_64
		do
			if attached entries.item (a_key) as l then
				l_since := a_now - window_for (a_key)
				from
					l.start
				until
					l.after
				loop
					if l.item <= l_since then
						l.remove
						Result := Result + 1
					else
						l.forth
					end
				end
			end
		ensure
			non_negative: Result >= 0
			dropped: count (a_key) = old count (a_key) - Result
		end

	prune_all_at (a_now: INTEGER_64)
			-- Prune every key; drop the keys left empty, and their totals.
		local
			l_gone: ARRAYED_LIST [STRING_8]
			l_dropped: INTEGER
		do
			create l_gone.make (4)
			across entries as ic loop
				l_dropped := l_dropped + prune_key_at (@ic.key, a_now)
				if ic.is_empty then
					l_gone.extend (@ic.key)
				end
			end
			across l_gone as k loop
				entries.remove (k)
				totals.remove (k)
			end
		ensure
			no_empty_keys: across entries as ic all ic.count > 0 end
			never_grows: counts_model.domain.count <= (old counts_model).domain.count
		end

invariant
	window_positive: window_seconds > 0
	rules_paired: limits.count = windows.count and across limits as ic all windows.has (@ic.key) end
	no_empty_keys: across entries as ic all ic.count > 0 end
	totals_cover_held: across entries as ic all totals.item (@ic.key) >= ic.count end
	counts_non_negative: records >= 0 and last_pruned >= 0 and offset_seconds >= 0
	models_consistent: counts_model.count = entries.count and limits_model.count = limits.count and windows_model.count = windows.count

end
