note
	description: "[
		`@shape-larry': answers a shape slug from shape.db, read-only, in
		Eiffel over simple_sql - the FITS / PARTIAL / FAILS / NO_DATA counts
		and the top instances. Numbers by default; prose when a response
		shaper is configured or chosen with `via'. The only argument shape
		is a slug: [a-z0-9_]{1,64} (`is_slug', Issue 38).
	]"
	author: "Larry Rix"

class
	SHAPE_TOOL_PARTICIPANT

inherit
	TOOL_PARTICIPANT
		redefine
			accepts_request
		end

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_database_path: READABLE_STRING_GENERAL; a_max_characters, a_timeout_seconds: INTEGER)
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
			database_given: not a_database_path.is_empty
			max_positive: a_max_characters > 0
			timeout_positive: a_timeout_seconds > 0
		do
			initialize_tool (a_handle, a_bot_user, Tool_description, a_max_characters, a_timeout_seconds)
			create database_path.make_from_string_general (a_database_path)
		ensure
			handle_set: handle.same_string_general (a_handle)
			database_set: database_path.same_string_general (a_database_path)
			plain_by_default: query_shaper.cost_tier = {SHAPER}.Tier_none and response_shaper.cost_tier = {SHAPER}.Tier_none
		end

feature -- Access

	database_path: STRING_32

	program_path: STRING_32
			-- <Precursor>: the database this tool opens read-only (no child
			-- process runs; `command_line_of' names what would be opened).
		do
			Result := database_path
		ensure then
			definition: Result = database_path
		end

feature -- Status report

	accepts_word (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- A shape slug and nothing else.
		do
			Result := is_slug (a_text)
		ensure then
			definition: Result = is_slug (a_text)
		end

	accepts_request (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- <Precursor>: exactly one slug - a multi-word request is not a query.
		do
			Result := words_of (a_text).count = 1
		ensure then
			one_word: Result = (words_of (a_text).count = 1)
		end

	is_slug (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- 1..`Slug_maximum' characters of [a-z0-9_]?
		local
			i: INTEGER
			c: NATURAL_32
		do
			Result := a_text.count >= 1 and a_text.count <= Slug_maximum
			from i := 1 until i > a_text.count or not Result loop
				c := a_text.code (i)
				Result := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c = 95
				i := i + 1
			end
		end

feature {NONE} -- Implementation

	run_arguments (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
			-- <Precursor>: parameterized SELECTs on shape and shape_instance
			-- over a read-only connection - the slug is always bound, never
			-- spliced into SQL. A missing database file, an unknown slug or
			-- a raising driver is an empty output with the time recorded:
			-- `answer' turns it into an honest error. No child process runs
			-- here, so the bound stays advisory (`record_run' still reports
			-- an overrun as timed out).
		local
			l_started, l_now: SIMPLE_DATE_TIME
			l_file: RAW_FILE
			l_db: detachable SIMPLE_SQL_DATABASE
			l_failed: BOOLEAN
		do
			create l_started.make_now
			create Result.make_empty
			if not l_failed then
				create l_file.make_with_name (database_path)
				if l_file.exists then
					create l_db.make_read_only (database_path)
					Result := shape_report (l_db, a_arguments.first)
					l_db.close
				end
			elseif attached l_db as l_open and then l_open.is_open then
				l_open.close
			end
			create l_now.make_now
			record_run ((l_now.to_timestamp - l_started.to_timestamp).to_integer_32.max (0))
		rescue
				-- One retry only: the retried body closes any open
				-- connection and answers an empty output; a second
				-- exception propagates instead of looping the rescue.
			if not l_failed then
				l_failed := True
				retry
			end
		end

	shape_report (a_db: SIMPLE_SQL_DATABASE; a_slug: READABLE_STRING_32): STRING_32
			-- The verdict census and first instances of `a_slug': the four
			-- verdicts are always named together - FITS, PARTIAL, FAILS,
			-- NO_DATA, zeroes included - because the store's own rule is
			-- that no query may return only the confirming cases. Empty for
			-- a slug the shape table does not carry.
		require
			open: a_db.is_open
			one_slug: is_slug (a_slug)
		local
			l_rows: SIMPLE_SQL_RESULT
			l_fits, l_partial, l_fails, l_no_data: INTEGER
			l_verdict: STRING_32
			i: INTEGER
		do
			create Result.make_empty
			l_rows := a_db.query_sql_with ("SELECT name FROM shape WHERE slug = ?", <<a_slug.to_string_8>>)
			if not l_rows.is_empty then
				Result.append (a_slug)
				Result.append ({STRING_32} " - ")
				Result.append (l_rows.first.string_value ("name"))
				l_rows := a_db.query_sql_with ("SELECT verdict, COUNT(*) AS n FROM shape_instance WHERE shape_id = (SELECT shape_id FROM shape WHERE slug = ?) GROUP BY verdict", <<a_slug.to_string_8>>)
				from i := 1 until i > l_rows.count loop
					l_verdict := l_rows [i].string_value ("verdict")
					if l_verdict.same_string ({STRING_32} "FITS") then
						l_fits := l_rows [i].integer_value ("n")
					elseif l_verdict.same_string ({STRING_32} "PARTIAL") then
						l_partial := l_rows [i].integer_value ("n")
					elseif l_verdict.same_string ({STRING_32} "FAILS") then
						l_fails := l_rows [i].integer_value ("n")
					elseif l_verdict.same_string ({STRING_32} "NO_DATA") then
						l_no_data := l_rows [i].integer_value ("n")
					end
					i := i + 1
				end
				Result.append ({STRING_32} "%NFITS ")
				Result.append_string_general (l_fits.out)
				Result.append ({STRING_32} "  PARTIAL ")
				Result.append_string_general (l_partial.out)
				Result.append ({STRING_32} "  FAILS ")
				Result.append_string_general (l_fails.out)
				Result.append ({STRING_32} "  NO_DATA ")
				Result.append_string_general (l_no_data.out)
				l_rows := a_db.query_sql_with ("SELECT ref, verdict FROM shape_instance WHERE shape_id = (SELECT shape_id FROM shape WHERE slug = ?) AND verdict IN ('FITS','PARTIAL') ORDER BY instance_id LIMIT " + Instance_limit.out, <<a_slug.to_string_8>>)
				from i := 1 until i > l_rows.count loop
					Result.append ({STRING_32} "%N")
					Result.append (l_rows [i].string_value ("verdict"))
					Result.append_character (' ')
					Result.append (l_rows [i].string_value ("ref"))
					i := i + 1
				end
			end
		ensure
			census_or_nothing: not Result.is_empty implies (Result.has_substring ({STRING_32} "FITS") and Result.has_substring ({STRING_32} "PARTIAL")
				and Result.has_substring ({STRING_32} "FAILS") and Result.has_substring ({STRING_32} "NO_DATA"))
		end

feature -- Constants

	Instance_limit: INTEGER = 5
			-- How many FITS and PARTIAL instances a reply names.

	Slug_maximum: INTEGER = 64

	Tool_description: STRING_32 = "the shape tool: one shape slug such as beachhead_that_moves"

invariant
	database_given: not database_path.is_empty

end
