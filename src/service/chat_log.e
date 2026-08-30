note
	description: "[
		The server's log, redacting: no password, token or hash ever reaches
		a log line (NFR-007, DR-012). Before a line is written, every run of
		`Hex_run_length' or more hex digits (a token, a token hash, a
		SHA-256) becomes `Mask', and the value after any secret-bearing
		field - `password=', `token=', `hash=' and their JSON forms
		`"password":' ..., and `Bearer ' - becomes `Mask', whether the value
		is bare or quoted. `last_line' is what went out, so a test can read
		it; the contracts say what it never contains.

		Owned by the service's processor (approach section 8): no lock.
	]"
	author: "Larry Rix"

class
	CHAT_LOG

create
	make

feature {NONE} -- Initialization

	make (a_logger: SIMPLE_LOGGER)
		do
			logger := a_logger
			create last_line.make_empty
		ensure
			logger_set: logger = a_logger
			nothing_written: lines_written = 0
			no_line: last_line.is_empty
		end

feature -- Access

	lines_written: INTEGER

	last_line: STRING_32
			-- The last line written, after redaction; empty before the first.

feature -- Basic operations

	info (a_text: READABLE_STRING_GENERAL)
		do
			write (Level_info, a_text)
		ensure
			counted: lines_written = old lines_written + 1
			redacted_line: last_line.same_string (redact (a_text))
		end

	warn (a_text: READABLE_STRING_GENERAL)
		do
			write (Level_warn, a_text)
		ensure
			counted: lines_written = old lines_written + 1
			redacted_line: last_line.same_string (redact (a_text))
		end

	error (a_text: READABLE_STRING_GENERAL)
		do
			write (Level_error, a_text)
		ensure
			counted: lines_written = old lines_written + 1
			redacted_line: last_line.same_string (redact (a_text))
		end

feature -- Redaction

	redact (a_text: READABLE_STRING_GENERAL): STRING_32
			-- `a_text' with every secret masked. Pure: the same text always gives the same line.
		do
			Result := mask_hex_runs (mask_secret_fields (a_text.to_string_32))
		ensure
			no_hex_runs: not has_hex_run (Result, Hex_run_length)
			no_secret_fields: not has_secret_field (Result)
			plain_text_kept: (not has_hex_run (a_text, Hex_run_length) and not has_secret_field (a_text)) implies Result.same_string_general (a_text)
		end

feature -- Validation (contract support)

	has_hex_run (a_text: READABLE_STRING_GENERAL; a_length: INTEGER): BOOLEAN
			-- Does `a_text' contain `a_length' consecutive hex digits?
		require
			positive: a_length > 0
		local
			i, run: INTEGER
		do
			from i := 1 until i > a_text.count or Result loop
				if is_hex_code (a_text.code (i)) then
					run := run + 1
					Result := run >= a_length
				else
					run := 0
				end
				i := i + 1
			end
		end

	has_secret_field (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Does any secret-bearing field in `a_text' carry a value other than `Mask'?
		local
			l_lower: STRING_32
			l_text: STRING_32
			i, s, e: INTEGER
		do
			l_text := a_text.to_string_32
			l_lower := l_text.as_lower
			across Markers as m until Result loop
				from
					i := l_lower.substring_index (m, 1)
				until
					i = 0 or Result
				loop
					s := value_start (l_text, i + m.count)
					e := value_end (l_text, s)
					Result := e >= s and then not l_text.substring (s, e).same_string (Mask)
					i := l_lower.substring_index (m, i + m.count)
				end
			end
		end

feature -- Constants

	Hex_run_length: INTEGER = 64
			-- The shortest hex run that is masked: a session token, its hash, a SHA-256.

	Mask: STRING_32 = "****"

	Markers: ARRAY [STRING_32]
			-- Lowercase; what precedes a secret value.
		once
			Result := <<{STRING_32} "password=", {STRING_32} "token=", {STRING_32} "hash=",
				{STRING_32} "%"password%":", {STRING_32} "%"token%":", {STRING_32} "%"hash%":", {STRING_32} "bearer ">>
		end

	Level_info: INTEGER = 1
	Level_warn: INTEGER = 2
	Level_error: INTEGER = 3

feature {NONE} -- Implementation

	logger: SIMPLE_LOGGER

	write (a_level: INTEGER; a_text: READABLE_STRING_GENERAL)
			-- Redact, remember, send.
		do
			last_line := redact (a_text)
			inspect a_level
			when Level_warn then
				logger.warn (last_line)
			when Level_error then
				logger.error (last_line)
			else
				logger.info (last_line)
			end
			lines_written := lines_written + 1
		ensure
			counted: lines_written = old lines_written + 1
			remembered: last_line.same_string (redact (a_text))
		end

	mask_secret_fields (a_text: STRING_32): STRING_32
			-- `a_text' with the value after every marker replaced by `Mask'.
		local
			l_lower: STRING_32
			i, s, e: INTEGER
		do
			Result := a_text.twin
			across Markers as m loop
				l_lower := Result.as_lower
				from
					i := l_lower.substring_index (m, 1)
				until
					i = 0
				loop
					s := value_start (Result, i + m.count)
					e := value_end (Result, s)
					if e >= s and then not Result.substring (s, e).same_string (Mask) then
						Result.replace_substring (Mask, s, e)
						l_lower := Result.as_lower
					end
					i := l_lower.substring_index (m, s)
				end
			end
		ensure
			no_secret_fields: not has_secret_field (Result)
		end

	mask_hex_runs (a_text: STRING_32): STRING_32
			-- `a_text' with every run of `Hex_run_length' or more hex digits replaced by `Mask'.
		local
			i, l_start: INTEGER
			l_runs: ARRAYED_LIST [TUPLE [first, last: INTEGER]]
		do
			Result := a_text.twin
			create l_runs.make (2)
			from
				i := 1
				l_start := 0
			until
				i > Result.count + 1
			loop
				if i <= Result.count and then is_hex_code (Result.code (i)) then
					if l_start = 0 then
						l_start := i
					end
				else
					if l_start > 0 and then i - l_start >= Hex_run_length then
						l_runs.extend ([l_start, i - 1])
					end
					l_start := 0
				end
				i := i + 1
			end
			from
				l_runs.finish
			until
				l_runs.before
			loop
				Result.replace_substring (Mask, l_runs.item.first, l_runs.item.last)
				l_runs.back
			end
		ensure
			no_hex_runs: not has_hex_run (Result, Hex_run_length)
		end

	value_start (a_text: STRING_32; a_from: INTEGER): INTEGER
			-- Where a field value begins at or after `a_from': past spaces and one opening quote.
		do
			Result := a_from
			from
			until
				Result > a_text.count or else a_text [Result] /= ' '
			loop
				Result := Result + 1
			end
			if Result <= a_text.count and then (a_text [Result] = '"' or a_text [Result] = '%'') then
				Result := Result + 1
			end
		ensure
			at_or_after: Result >= a_from
		end

	value_end (a_text: STRING_32; a_start: INTEGER): INTEGER
			-- The last index of the value starting at `a_start': up to the closing quote
			-- when the value was quoted, else up to a delimiter; `a_start' - 1 when empty.
		local
			l_quoted: BOOLEAN
		do
			l_quoted := a_start >= 2 and then (a_text [a_start - 1] = '"' or a_text [a_start - 1] = '%'')
			Result := a_start - 1
			from
			until
				Result + 1 > a_text.count or else
					(if l_quoted then a_text [Result + 1] = a_text [a_start - 1] else is_delimiter (a_text [Result + 1]) end)
			loop
				Result := Result + 1
			end
		ensure
			bounded: Result >= a_start - 1 and Result <= a_text.count
		end

	is_delimiter (a_char: CHARACTER_32): BOOLEAN
		do
			Result := a_char = ' ' or a_char = '%T' or a_char = '%R' or a_char = '%N'
				or a_char = '&' or a_char = ',' or a_char = ';' or a_char = '"' or a_char = '%''
				or a_char = '}' or a_char = ']'
		end

	is_hex_code (a_code: NATURAL_32): BOOLEAN
		do
			Result := (a_code >= 48 and a_code <= 57) or (a_code >= 97 and a_code <= 102) or (a_code >= 65 and a_code <= 70)
		end

invariant
	lines_non_negative: lines_written >= 0
	last_line_clean: not has_hex_run (last_line, Hex_run_length) and not has_secret_field (last_line)

end
