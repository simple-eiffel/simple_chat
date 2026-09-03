note
	description: "[
		The composer strip: a row that MEASURES its children at the width it
		will ARRANGE them to, so a wrapping text box grows on the same frame
		the wrap happens.

		WHY IT EXISTS. SW_WINDOW re-lays the whole tree out on every frame -
		`after_input' calls `render', and `render' calls `arrange' then
		`draw' - so nothing here is about dirty flags or stale caches. The
		lag Larry saw was a WIDTH DISAGREEMENT inside one frame.

		SW_ROW.arrange_line hands each child its SHARE of the row: the
		non-growers keep their natural widths and the growers split what is
		left. SW_ROW.preferred_height, though, asks every child for its
		height at the WHOLE row width, as if the child were alone on it. For
		a label or a button that is harmless - their heights do not depend on
		width. For a wrapping SW_TEXT_BOX it is the bug: the box is MEASURED
		as if it were `Send' plus the gap wider than it is DRAWN, so the
		paint wraps to a second line while the measurement still says one,
		the column gives the row a one-line height, and the second line lands
		BELOW the box until the text grows long enough to wrap at the wider
		measuring width too. That surplus - the Send button plus one theme
		gap - is exactly how far across the second line got before the box
		finally grew.

		THE FIX is to measure the way `arrange_line' allocates: the same
		natural widths, the same leftover, the same grow shares, and then ask
		each child its height at the width it is actually going to get.
		Contract-wise this is still SW_ROW's `preferred_height' - a
		non-negative natural height - only computed from the honest width.

		This is a library-shaped fix wearing an application's clothes: the
		disagreement is SW_ROW's, and every wrapping child of every row has
		it. It lives here because simple_widgets is checked out on somebody
		else's branch this week, not because the row is special.
	]"
	author: "Larry Rix"

class
	COMPOSER_ROW

inherit
	SW_ROW
		redefine
			preferred_height
		end

create
	make

feature -- Layout

	preferred_height (a_p: SW_PAINTER; a_width: REAL_64): REAL_64
			-- The tallest child, each measured at the width `arrange_line'
			-- would give it inside `a_width' - not at `a_width' itself.
			-- A wrapping row keeps the parent's own answer: it already
			-- measures every child at that child's natural width.
		local
			widths: ARRAYED_LIST [REAL_64]
			natural, leftover, total_grow, gp, cw, h: REAL_64
			i: INTEGER
		do
			if is_wrapping then
				Result := Precursor (a_p, a_width)
			else
				gp := effective_gap (a_p)
				create widths.make (children.count)
				across
					children as c
				loop
					widths.extend (c.clamped_width (c.preferred_width (a_p)))
					natural := natural + widths.last
					total_grow := total_grow + c.grow
				end
				if children.count > 1 then
					natural := natural + gp * (children.count - 1)
				end
				leftover := a_width - natural
				from
					i := 1
				until
					i > children.count
				loop
					cw := widths.i_th (i)
					if leftover > 0.0 and total_grow > 0.0 and children.i_th (i).grow > 0.0 then
						cw := children.i_th (i).clamped_width
							(cw + leftover * children.i_th (i).grow / total_grow)
					end
					h := children.i_th (i).clamped_height
						(children.i_th (i).preferred_height (a_p, cw))
					if h > Result then
						Result := h
					end
					i := i + 1
				end
			end
		ensure then
			empty_row_is_flat: children.is_empty implies Result = 0.0
		end

	allotted_width (a_p: SW_PAINTER; a_width: REAL_64; a_index: INTEGER): REAL_64
			-- The width child `a_index' gets when this row is `a_width' wide -
			-- `arrange_line''s own arithmetic, published so a test can name the
			-- number the measurement and the paint are supposed to agree on.
		require
			a_child: a_index >= 1 and a_index <= children.count
			sane_width: a_width >= 0.0
		local
			widths: ARRAYED_LIST [REAL_64]
			natural, leftover, total_grow, gp: REAL_64
		do
			gp := effective_gap (a_p)
			create widths.make (children.count)
			across
				children as c
			loop
				widths.extend (c.clamped_width (c.preferred_width (a_p)))
				natural := natural + widths.last
				total_grow := total_grow + c.grow
			end
			if children.count > 1 then
				natural := natural + gp * (children.count - 1)
			end
			leftover := a_width - natural
			Result := widths.i_th (a_index)
			if leftover > 0.0 and total_grow > 0.0 and children.i_th (a_index).grow > 0.0 then
				Result := children.i_th (a_index).clamped_width
					(Result + leftover * children.i_th (a_index).grow / total_grow)
			end
		ensure
			non_negative: Result >= 0.0
		end

end
