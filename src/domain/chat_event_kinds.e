note
	description: "The event kinds and the bot marker, shared by CHAT_EVENT and its draft."
	author: "Larry Rix"

class
	CHAT_EVENT_KINDS

feature -- Validation

	is_known_kind (a_kind: READABLE_STRING_8): BOOLEAN
		do
			Result := a_kind.same_string (Kind_message) or a_kind.same_string (Kind_image) or a_kind.same_string (Kind_system)
				or a_kind.same_string (Kind_edit) or a_kind.same_string (Kind_delete) or a_kind.same_string (Kind_reaction)
		end

feature -- Constants

	Kind_message: STRING_8 = "message"
	Kind_image: STRING_8 = "image"
	Kind_system: STRING_8 = "system"

	Kind_edit: STRING_8 = "edit"
			-- A later text for an earlier message. The original is NEVER
			-- rewritten: the room is an append-only log and this event
			-- supersedes, which is how the room can honestly say a message
			-- was edited at all.

	Kind_delete: STRING_8 = "delete"
			-- A tombstone for an earlier message. The bubble reads "message
			-- deleted" rather than vanishing: history stays honest, and a
			-- conversation that quoted it still makes sense.

	Kind_reaction: STRING_8 = "reaction"
			-- One person's emoji on one message, on or off. Add and remove
			-- are both events folded in log order - the same shape favorites
			-- take - so the last word per person per emoji wins and nothing
			-- needs a table of its own.

	is_fold_kind (a_kind: READABLE_STRING_8): BOOLEAN
			-- Is `a_kind' an event that CHANGES an earlier one rather than
			-- standing on its own? These never draw a bubble of their own;
			-- they fold onto the message they name.
		do
			Result := a_kind.same_string (Kind_edit) or a_kind.same_string (Kind_delete)
				or a_kind.same_string (Kind_reaction)
		ensure
			known: Result implies is_known_kind (a_kind)
			never_a_message: Result implies not a_kind.same_string (Kind_message)
		end

feature -- Payload keys

	Key_target: STRING_32 = "target"
			-- The id of the message an edit, delete or reaction acts on.

	Key_emoji: STRING_32 = "emoji"
	Key_on: STRING_32 = "on"
			-- A reaction's emoji, and whether this event adds it or takes it away.

	Key_reply_to: STRING_32 = "reply_to"
			-- On an ordinary message: the id it answers. A reply is NOT a kind
			-- of its own - it is a message that names a parent - so every rule
			-- a message already obeys it obeys too, and nothing folds.

	Bot_marker: STRING_32 = "%/129302/"
			-- U+1F916, the robot face; every bot-authored message begins with it.

end
