note
	description: "[
		The room's thread, with a per-message menu on it.

		SW_CHAT_THREAD offers Copy and the two ways to change what Copy
		would take. THE MENU IS THE HOST'S TO DRAW, and this is the host:
		it keeps the library's items and adds the four a chat room wants -
		Reply, React, Edit, Delete - on the bubble the pointer actually
		landed on (`message_at', the same geometry the selection uses, so
		a menu and a selection can never disagree about which message was
		meant).

		WHAT IS GREYED IS THE PERMISSION RULE, and the rule is the
		server's: the author may edit their own; the author OR AN
		ADMINISTRATOR may delete; nobody may edit anyone else's words. The
		predicates are supplied by the host that knows who is signed in
		(`set_permissions'), so this widget carries no idea of identity of
		its own and cannot get the rule subtly different from the server.
		A greyed item is still SHOWN: a menu that hides what you may not
		do teaches nothing, and a member who wonders why Delete is grey
		has learned the rule.

		A CLICK ON A REACTION CHIP TOGGLES IT (`reaction_at'), which is
		why `handle_click' is redefined: the chip is asked first, and only
		when the point is on no chip does the click mean what it always
		meant to the thread beneath.
	]"
	author: "Larry Rix"

class
	MESSAGE_THREAD

inherit
	SW_CHAT_THREAD
		redefine
			context_menu, handle_click
		end

create
	make

feature -- Element change

	set_actions (a_reply, a_edit, a_delete: PROCEDURE [INTEGER]; a_react: PROCEDURE [INTEGER, STRING_32])
			-- What the four items do, each given the bubble it acts on.
		do
			on_reply := a_reply
			on_edit := a_edit
			on_delete := a_delete
			on_react := a_react
		ensure
			set: on_reply = a_reply and on_edit = a_edit and on_delete = a_delete and on_react = a_react
		end

	set_permissions (a_may_edit, a_may_delete: FUNCTION [INTEGER, BOOLEAN])
			-- The rule, asked fresh every time the menu opens, so an item
			-- greys the instant state turns against it.
		do
			may_edit := a_may_edit
			may_delete := a_may_delete
		ensure
			set: may_edit = a_may_edit and may_delete = a_may_delete
		end

	set_emoji_choices (a_list: ARRAYED_LIST [STRING_32])
			-- The small set React offers.
		require
			choices_given: not a_list.is_empty
		do
			emoji_choices := a_list
		ensure
			set: emoji_choices = a_list
		end

feature -- Access

	emoji_choices: ARRAYED_LIST [STRING_32]
			-- The handful React offers. A picker, not a keyboard: a room
			-- that offers every emoji offers a search box, and that is a
			-- different feature.
		attribute
			create Result.make (8)
			Result.extend ({STRING_32} "%/128077/")
			Result.extend ({STRING_32} "%/10084/")
			Result.extend ({STRING_32} "%/128512/")
			Result.extend ({STRING_32} "%/128514/")
			Result.extend ({STRING_32} "%/128558/")
			Result.extend ({STRING_32} "%/128546/")
			Result.extend ({STRING_32} "%/128591/")
			Result.extend ({STRING_32} "%/127881/")
		end

feature -- The menu

	context_menu (a_px, a_py: REAL_64): detachable SW_MENU
			-- The library's Copy items, then the room's four - on the
			-- bubble the pointer landed on.
		local
			l_message: INTEGER
			l_menu: SW_MENU
		do
			Result := Precursor (a_px, a_py)
			l_message := message_at (a_px, a_py)
			if l_message > 0 and then attached Result as m then
				l_menu := m
				l_menu.add_separator
				l_menu.add_item (Text_reply, "", on_reply /= Void and not is_tombstone (l_message),
					reply_action (l_message))
				if on_react /= Void and then not is_tombstone (l_message) then
						-- The emoji go in as ITEMS, not behind a "React..." that
						-- opens a second popup: SW_MENU has no submenu and the
						-- window's popup door is its own. Eight choices read fine
						-- in a menu, and one click is better than two.
					across emoji_choices as em loop
						l_menu.add_item (em, Text_react_hint, True, emoji_action (l_message, em))
					end
					l_menu.add_separator
				end
				l_menu.add_item (Text_edit, "", allowed (may_edit, l_message) and not is_tombstone (l_message),
					edit_action (l_message))
				l_menu.add_item (Text_delete, "", allowed (may_delete, l_message) and not is_tombstone (l_message),
					delete_action (l_message))
			end
		end

feature -- Input

	handle_click (a_px, a_py: REAL_64): BOOLEAN
			-- A reaction chip first: a click on one toggles that emoji.
			-- Anywhere else the thread beneath answers as it always did.
		local
			hit: TUPLE [message: INTEGER; emoji: STRING_32]
		do
			hit := reaction_at (a_px, a_py)
			if hit.message > 0 and then not hit.emoji.is_empty and then attached on_react as r then
				r.call ([hit.message, hit.emoji])
				Result := True
			else
				Result := Precursor (a_px, a_py)
			end
		end

feature {NONE} -- Implementation

	on_reply, on_edit, on_delete: detachable PROCEDURE [INTEGER]
	on_react: detachable PROCEDURE [INTEGER, STRING_32]
	may_edit, may_delete: detachable FUNCTION [INTEGER, BOOLEAN]

	allowed (a_rule: detachable FUNCTION [INTEGER, BOOLEAN]; a_message: INTEGER): BOOLEAN
			-- Does `a_rule' permit this, and is there anything to do it
			-- with? No rule means NO - the safe way round for a menu whose
			-- items change other people's room.
		do
			Result := attached a_rule as r and then r.item ([a_message])
		end

	reply_action (a_message: INTEGER): detachable PROCEDURE
		do
			if attached on_reply as p then
				Result := agent p.call ([a_message])
			end
		end

	edit_action (a_message: INTEGER): detachable PROCEDURE
		do
			if attached on_edit as p then
				Result := agent p.call ([a_message])
			end
		end

	delete_action (a_message: INTEGER): detachable PROCEDURE
		do
			if attached on_delete as p then
				Result := agent p.call ([a_message])
			end
		end

	emoji_action (a_message: INTEGER; a_emoji: STRING_32): detachable PROCEDURE
			-- One emoji on one bubble. It TOGGLES: the host asks the drawn
			-- row whether the reader already has it.
		do
			if attached on_react as p then
				Result := agent p.call ([a_message, a_emoji])
			end
		end

feature -- Constants

	Text_reply: STRING_32 = "Reply"
	Text_react_hint: STRING_32 = "react"
	Text_edit: STRING_32 = "Edit"
	Text_delete: STRING_32 = "Delete"

end
