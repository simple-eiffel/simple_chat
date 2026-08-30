note
	description: "[
		Handle to participant, built from the [[participants]] configuration;
		every handle unique, every key a copy (a participant cannot rename
		itself out of the table). Aliases live here too (M3): "claude:" or
		"@robot" to "@claude", lowercase, each pointing at a registered
		handle and never itself a handle - so the parser has one place to
		ask and the config's aliases have one home. Modeled as maps, so
		registration states what it left alone.
	]"
	author: "Larry Rix"

class
	PARTICIPANT_REGISTRY

create
	make

feature {NONE} -- Initialization

	make
		do
			create table.make (8)
			table.compare_objects
			create aliases.make (4)
			aliases.compare_objects
		ensure
			empty: count = 0
			no_model: participants_model.is_empty
			no_aliases: aliases_model.is_empty
		end

feature -- Model Queries (for MML postconditions)

	handles_model: MML_SET [STRING_32]
		do
			create Result
			across table as ic loop
				Result := Result & @ic.key
			end
		ensure
			same_count: Result.count = count
		end

	participants_model: MML_MAP [STRING_32, PARTICIPANT]
		do
			create Result
			across table as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = count
			same_handles: Result.domain |=| handles_model
		end

	aliases_model: MML_MAP [STRING_32, STRING_32]
			-- Lowercase alias -> the handle it addresses.
		do
			create Result
			across aliases as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = alias_count
		end

feature -- Access

	count: INTEGER
		do
			Result := table.count
		end

	alias_count: INTEGER
		do
			Result := aliases.count
		end

	find (a_handle: READABLE_STRING_GENERAL): detachable PARTICIPANT
		do
			Result := table.item (a_handle.to_string_32)
		ensure
			consistent: (Result /= Void) = has (a_handle)
			right_one: attached Result as p implies p.handle.same_string_general (a_handle)
			from_model: attached Result as p implies participants_model [a_handle.to_string_32] = p
		end

	participants: ARRAYED_LIST [PARTICIPANT]
		do
			create Result.make (table.count)
			across table as ic loop
				Result.extend (ic)
			end
		ensure
			same_count: Result.count = count
		end

	alias_names: ARRAYED_LIST [STRING_32]
			-- Every alias, lowercase, as copies.
		do
			create Result.make (aliases.count)
			across aliases as ic loop
				Result.extend (@ic.key.twin)
			end
		ensure
			same_count: Result.count = alias_count
			all_known: across Result as a all has_alias (a) end
		end

	handle_of_alias (a_alias: READABLE_STRING_GENERAL): STRING_32
			-- The registered handle `a_alias' stands for.
		require
			known: has_alias (a_alias)
		do
			check known_means_present: attached aliases.item (a_alias.to_string_32.as_lower) as h then
				Result := h.twin
			end
		ensure
			from_model: Result.same_string (aliases_model [a_alias.to_string_32.as_lower])
			registered: has (Result)
		end

feature -- Status report

	has (a_handle: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := table.has (a_handle.to_string_32)
		ensure
			definition: Result = handles_model.has (a_handle.to_string_32)
		end

	has_alias (a_alias: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_alias' (in any case) an alias here?
		do
			Result := aliases.has (a_alias.to_string_32.as_lower)
		ensure
			definition: Result = aliases_model.domain.has (a_alias.to_string_32.as_lower)
		end

feature -- Element change

	register (a_participant: PARTICIPANT)
		require
			fresh_handle: not has (a_participant.handle)
			not_an_alias: not has_alias (a_participant.handle)
		do
			table.put (a_participant, a_participant.handle.twin)
		ensure
			added: handles_model |=| ((old handles_model) & a_participant.handle)
			mapped: participants_model |=| (old participants_model).updated (a_participant.handle, a_participant)
			findable: find (a_participant.handle) = a_participant
			one_more: count = old count + 1
			aliases_unchanged: aliases_model |=| old aliases_model
		end

	register_alias (a_alias, a_handle: READABLE_STRING_GENERAL)
			-- Let `a_alias' (in any case) address `a_handle'.
		require
			alias_shape: (create {PARTICIPANT_RULES}).is_valid_alias (a_alias)
			target_known: has (a_handle)
			fresh: not has_alias (a_alias)
			not_a_handle: not has (a_alias.to_string_32.as_lower)
		do
			aliases.put (a_handle.to_string_32.twin, a_alias.to_string_32.as_lower)
		ensure
			mapped: aliases_model |=| (old aliases_model).updated (a_alias.to_string_32.as_lower, a_handle.to_string_32)
			resolves: handle_of_alias (a_alias).same_string_general (a_handle)
			one_more: alias_count = old alias_count + 1
			participants_unchanged: participants_model |=| old participants_model
		end

feature {NONE} -- Implementation

	table: HASH_TABLE [PARTICIPANT, STRING_32]

	aliases: HASH_TABLE [STRING_32, STRING_32]
			-- Lowercase alias -> handle.

invariant
	handles_are_keys: across table as ic all ic.handle.same_string (@ic.key) end
	alias_targets_exist: across aliases as ic all table.has (ic) end
	aliases_are_not_handles: across aliases as ic all not table.has (@ic.key) end
	aliases_lowercase: across aliases as ic all @ic.key.same_string (@ic.key.as_lower) end
	models_consistent: handles_model.count = count and participants_model.count = count and aliases_model.count = alias_count

end
