note
	description: "Handle to participant, built from the [[participants]] configuration; every handle unique. Modeled as a map, so registration states what it left alone."
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
		ensure
			empty: count = 0
			no_model: participants_model.is_empty
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

feature -- Access

	count: INTEGER
		do
			Result := table.count
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

feature -- Status report

	has (a_handle: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := table.has (a_handle.to_string_32)
		ensure
			definition: Result = handles_model.has (a_handle.to_string_32)
		end

feature -- Element change

	register (a_participant: PARTICIPANT)
		require
			fresh_handle: not has (a_participant.handle)
		do
			table.put (a_participant, a_participant.handle)
		ensure
			added: handles_model |=| ((old handles_model) & a_participant.handle)
			mapped: participants_model |=| (old participants_model).updated (a_participant.handle, a_participant)
			findable: find (a_participant.handle) = a_participant
			one_more: count = old count + 1
		end

feature {NONE} -- Implementation

	table: HASH_TABLE [PARTICIPANT, STRING_32]

invariant
	handles_are_keys: across table as ic all ic.handle.same_string (@ic.key) end
	models_consistent: handles_model.count = count and participants_model.count = count

end
