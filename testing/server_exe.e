note
	description: "[
		WHERE THE FINALIZED SERVER EXECUTABLE IS, asked from wherever this test
		runner happens to have been started.

		The live assaults in WIRING_ASSAULT boot the real server. Until
		2026-09-03 they looked for it at a fixed relative path -
		EIFGENs\simple_chat_server\F_code\simple_chat.exe - which the file
		system resolves against the CURRENT WORKING DIRECTORY. So the answer
		changed with the directory the runner was launched from: right from the
		project root, wrong from inside EIFGENs\simple_chat_tests\F_code, which
		is where the runner exe itself sits and the most natural place to start
		it from. A wrong answer there meant "not built", and "not built" meant a
		SKIP that counted as a pass. That hid a real failure three times on
		2026-09-02 and 2026-09-03.

		So this asks TWICE, and asks the file system both times, so neither
		answer can be right by accident:

		1. The working directory, extended by the relative path. This is where
		   RUNBOOK.md says to run from, and it keeps the old answer exactly.
		2. The directory of THIS RUNNING EXECUTABLE and each of its ancestors,
		   up to `Search_ceiling' levels. A runner started inside
		   EIFGENs\simple_chat_tests\F_code walks the three levels up to the
		   project root and finds the same file the first search would have
		   found from there.

		`path' is Void only when the executable really is not built, and then
		the assault FAILS - it does not skip. TEST_APP asks `is_built' when the
		run has failures, so the summary can name the one build that fixes them.
	]"
	author: "Larry Rix"

class
	SERVER_EXE

feature -- Access

	path: detachable PATH
			-- The finalized server executable, found from the working directory
			-- or from this running executable's own place in the tree; Void when
			-- it is not built.
		local
			l_at: PATH
			l_depth: INTEGER
			l_parent: PATH
		do
			Result := existing_under (working_directory)
			if Result = Void then
				from
					l_at := running_directory
					l_depth := 0
				until
					Result /= Void or l_depth > Search_ceiling
				loop
					Result := existing_under (l_at)
					if Result = Void then
						l_parent := l_at.parent
						if l_parent.same_as (l_at) then
								-- The root of the drive: there is nowhere further up.
							l_depth := Search_ceiling + 1
						else
							l_at := l_parent
							l_depth := l_depth + 1
						end
					end
				end
			end
		end

	is_built: BOOLEAN
			-- Can either search find the finalized server executable?
		do
			Result := path /= Void
		ensure
			definition: Result = (path /= Void)
		end

	name: STRING_32
			-- `path' as text, for a command line; empty when it is not built.
		do
			if attached path as p then
				Result := p.name.to_string_32
			else
				create Result.make_empty
			end
		ensure
			empty_exactly_when_unbuilt: Result.is_empty = not is_built
		end

feature -- Report

	Relative_path: STRING_8 = "EIFGENs\simple_chat_server\F_code\simple_chat.exe"
			-- What to SAY when it is missing: where the file belongs, relative to
			-- the project root. Never used to look for it - `path' does that.

	Build_command: STRING_8 = "ec.sh test -config simple_chat.ecf -target simple_chat_server"
			-- The one command that builds it. Run from the project root.

	explain_missing
			-- Print where the executable belongs and the one command that builds
			-- it, so every assault that needs it says the same thing.
		require
			not_built: not is_built
		do
			print ("  NOT BUILT: " + Relative_path + "%N")
			print ("             Build it FIRST, from the project root:%N")
			print ("                 " + Build_command + "%N")
		end

feature {NONE} -- Implementation

	existing_under (a_root: PATH): detachable PATH
			-- `a_root' extended by the four names between the project root and
			-- the executable - when that file is really on disk.
		local
			l_candidate: PATH
			l_file: RAW_FILE
		do
			l_candidate := a_root.extended ("EIFGENs").extended ("simple_chat_server").extended ("F_code").extended ("simple_chat.exe")
			create l_file.make_with_path (l_candidate)
			if l_file.exists then
				Result := l_candidate
			end
		end

	working_directory: PATH
			-- Where this process was started.
		local
			l_environment: EXECUTION_ENVIRONMENT
		do
			create l_environment
			Result := l_environment.current_working_path
		end

	running_directory: PATH
			-- The directory holding THIS executable. `command_name' is argv[0],
			-- which may be relative or bare; `absolute_path' resolves it against
			-- the working directory, so the answer is a real directory either
			-- way, and when argv[0] carries no directory at all the two searches
			-- simply coincide - which costs one extra stat and nothing else.
		local
			l_command: PATH
		do
			create l_command.make_from_string ({ARGUMENTS_32}.command_name)
			if l_command.is_empty then
				Result := working_directory
			else
				Result := l_command.absolute_path.parent
			end
		end

	Search_ceiling: INTEGER = 8
			-- How far up from the running executable to look. Three levels reach
			-- the project root from EIFGENs\simple_chat_tests\F_code; eight
			-- leaves room without walking a whole drive.

end
