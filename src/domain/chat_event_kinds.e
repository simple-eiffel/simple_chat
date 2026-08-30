note
	description: "The event kinds and the bot marker, shared by CHAT_EVENT and its draft."
	author: "Larry Rix"

class
	CHAT_EVENT_KINDS

feature -- Validation

	is_known_kind (a_kind: READABLE_STRING_8): BOOLEAN
		do
			Result := a_kind.same_string (Kind_message) or a_kind.same_string (Kind_image) or a_kind.same_string (Kind_system)
		end

feature -- Constants

	Kind_message: STRING_8 = "message"
	Kind_image: STRING_8 = "image"
	Kind_system: STRING_8 = "system"

	Bot_marker: STRING_32 = "%/129302/"
			-- U+1F916, the robot face; every bot-authored message begins with it.

end
