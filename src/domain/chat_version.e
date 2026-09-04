note
	description: "[
		WHAT VERSION AM I RUNNING. One place, for the window's Help > About
		and for anything else that needs to say so out loud.

		THE SINGLE SOURCE OF TRUTH IS `Product'. The installer declares the
		same number at installer\SimpleChat.iss line 48
		(#define AppVersion) and the two must be changed together - there
		is no build step that derives one from the other, so a release
		checklist has to touch both. Nothing else in the product hard-codes
		a version string.

		`Libraries' is the fleet this build was compiled against, kept in
		step with the CHANGELOG's release note by hand for the same reason.
	]"
	author: "Larry Rix"

class
	CHAT_VERSION

feature -- Access

	Product: STRING_32 = "0.2.1"
			-- Keep in step with installer\SimpleChat.iss #define AppVersion.

	Built_on: STRING_32 = "2026-09-03"

	Libraries: STRING_32 = "simple_widgets 0.7.2, simple_console 1.2.0, simple_ai_client (UTF-8 fix), simple_winhttp 0.1.1, simple_process 1.0.1, simple_encryption 2.1.1, simple_shell 1.9.3"

	About_text: STRING_32
			-- What Help > About says, in one readable block.
		do
			create Result.make (240)
			Result.append ({STRING_32} "simple_chat ")
			Result.append (Product)
			Result.append ({STRING_32} "%NBuilt ")
			Result.append (Built_on)
			Result.append ({STRING_32} "%NAgainst: ")
			Result.append (Libraries)
		ensure
			names_the_product: Result.has_substring ({STRING_32} "simple_chat")
			names_the_version: Result.has_substring (Product)
			names_the_build_date: Result.has_substring (Built_on)
			names_the_libraries: Result.has_substring (Libraries)
		end

end
