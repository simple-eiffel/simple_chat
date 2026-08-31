note
	description: "[
		SERVER_CONFIG under assault (Phase 1c, M-D7): participant uniqueness
		beyond handles - bot usernames and aliases collide nowhere, and an
		alias is never a handle, in either direction, case-insensitively.
	]"
	author: "Larry Rix"

class
	CONFIG_ASSAULT

inherit
	TEST_SET_BASE

feature -- Tests

	test_config_addresses_and_bot_usernames_are_tracked
			-- The uniqueness queries see handles, aliases and bot usernames, in any case.
		local
			c: SERVER_CONFIG
			p: PARTICIPANT_CONFIG
		do
			create c.make_defaults
			create p.make ({STRING_32} "@claude", {PARTICIPANT_CONFIG}.Kind_none, "claude_bot", {STRING_32} "Claude", {STRING_32} "")
			p.add_alias ({STRING_32} "@cl")
			c.add_participant (p)
			assert ("handle tracked in any case", c.has_participant_handle ({STRING_32} "@Claude"))
			assert ("alias tracked in any case", c.has_participant_alias ({STRING_32} "@CL"))
			assert ("bot username tracked", c.has_participant_bot_username ("claude_bot"))
			assert ("fresh address is free", c.is_free_address ({STRING_32} "@qwen"))
			assert ("handle is not free", not c.is_free_address ({STRING_32} "@claude"))
			assert ("alias is not free", not c.is_free_address ({STRING_32} "@cl"))
		end

	test_config_refuses_colliding_participants
			-- M-D7: a second entry may not reuse a bot username, take an
			-- alias equal to a handle, take a handle equal to an alias, or
			-- reuse another entry's alias.
		local
			c: SERVER_CONFIG
			p, q: PARTICIPANT_CONFIG
		do
			create c.make_defaults
			create p.make ({STRING_32} "@claude", {PARTICIPANT_CONFIG}.Kind_none, "claude_bot", {STRING_32} "Claude", {STRING_32} "")
			p.add_alias ({STRING_32} "@cl")
			c.add_participant (p)
			create q.make ({STRING_32} "@other", {PARTICIPANT_CONFIG}.Kind_none, "claude_bot", {STRING_32} "Other", {STRING_32} "")
			assert ("duplicate bot username refused", not adds (c, q))
			create q.make ({STRING_32} "@third", {PARTICIPANT_CONFIG}.Kind_none, "third_bot", {STRING_32} "Third", {STRING_32} "")
			q.add_alias ({STRING_32} "@claude")
			assert ("alias equal to a handle refused", not adds (c, q))
			create q.make ({STRING_32} "@cl", {PARTICIPANT_CONFIG}.Kind_none, "fourth_bot", {STRING_32} "Fourth", {STRING_32} "")
			assert ("handle equal to an alias refused", not adds (c, q))
			create q.make ({STRING_32} "@fifth", {PARTICIPANT_CONFIG}.Kind_none, "fifth_bot", {STRING_32} "Fifth", {STRING_32} "")
			q.add_alias ({STRING_32} "@cl")
			assert ("alias equal to another entry's alias refused", not adds (c, q))
			create q.make ({STRING_32} "@qwen", {PARTICIPANT_CONFIG}.Kind_none, "qwen_bot", {STRING_32} "Qwen", {STRING_32} "")
			q.add_alias ({STRING_32} "@qw")
			c.add_participant (q)
			assert ("fresh entry accepted", c.participant_count = 2 and c.has_participant_handle ({STRING_32} "@qwen"))
		end

feature {NONE} -- Fixtures

	adds (a_config: SERVER_CONFIG; a_participant: PARTICIPANT_CONFIG): BOOLEAN
			-- Does `add_participant' accept `a_participant' (its precondition holds)?
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				a_config.add_participant (a_participant)
				Result := True
			end
		rescue
			l_failed := True
			retry
		end

end
