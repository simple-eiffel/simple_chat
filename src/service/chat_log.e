note
	description: "[
		The server's log, redacting: no password, token or hash ever reaches
		a log line (NFR-007, DR-012). Anything that looks like a 64-hex run
		or follows a secret-bearing field name is masked before writing.
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
		ensure
			logger_set: logger = a_logger
		end

feature -- Basic operations

	info (a_text: READABLE_STRING_GENERAL)
		do
			-- Implementation in Phase 4: logger.info (redact (a_text))
		ensure
			counted: lines_written = old lines_written + 1
		end

	warn (a_text: READABLE_STRING_GENERAL)
		do
			-- Implementation in Phase 4
		ensure
			counted: lines_written = old lines_written + 1
		end

	error (a_text: READABLE_STRING_GENERAL)
		do
			-- Implementation in Phase 4
		ensure
			counted: lines_written = old lines_written + 1
		end

feature -- Access

	lines_written: INTEGER

	redact (a_text: READABLE_STRING_GENERAL): STRING_32
			-- `a_text' with secrets masked.
		do
			Result := a_text.to_string_32
			-- Implementation in Phase 4
		ensure
			no_hex_runs: not has_hex_run (Result, 64)
			no_secret_fields: not has_secret_field (Result)
		end

feature -- Validation (contract support)

	has_hex_run (a_text: READABLE_STRING_GENERAL; a_length: INTEGER): BOOLEAN
			-- Does `a_text' contain `a_length' consecutive hex digits?
		require
			positive: a_length > 0
		local
			i, run: INTEGER
			c: NATURAL_32
		do
			from i := 1 until i > a_text.count or Result loop
				c := a_text.code (i)
				if (c >= 48 and c <= 57) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70) then
					run := run + 1
					Result := run >= a_length
				else
					run := 0
				end
				i := i + 1
			end
		end

	has_secret_field (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_text' contain "password=", "token=" or "hash=" followed by anything but a mask?
		do
			-- Implementation in Phase 4
		end

feature {NONE} -- Implementation

	logger: SIMPLE_LOGGER

invariant
	lines_non_negative: lines_written >= 0

end
