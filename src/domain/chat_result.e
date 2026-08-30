note
	description: "[
		The outcome of a service operation: a value on success, an error
		otherwise, never both and never neither. Immutable. Every
		CHAT_SERVICE command returns one; nothing in the domain raises for
		a user's mistake.
	]"
	author: "Larry Rix"

class
	CHAT_RESULT [G]

create
	make_success,
	make_error

feature {NONE} -- Initialization

	make_success (a_value: G)
			-- Success carrying `a_value'.
		do
			value := a_value
			is_success := True
		ensure
			success: is_success
			value_set: value = a_value
			no_error: error = Void
		end

	make_error (a_error: CHAT_ERROR)
			-- Failure explained by `a_error'.
		do
			error := a_error
		ensure
			failure: not is_success
			error_set: error = a_error
			no_value: value = Void
		end

feature -- Access

	is_success: BOOLEAN
			-- Did the operation succeed?

	value: detachable G
			-- The result, when `is_success'.

	error: detachable CHAT_ERROR
			-- Why not, when not `is_success'.

invariant
	success_xor_error: is_success xor (error /= Void)
	success_has_value: is_success implies value /= Void

end
