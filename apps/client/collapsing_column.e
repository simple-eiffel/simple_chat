note
	description: "[
		A column in which a child of zero height is ABSENT: it costs no row
		and, just as important, no GAP.

		SW_COLUMN separates siblings by `effective_gap' - the theme's own
		padding, which scales with the text - and charges one gap for every
		join, counting every child whether or not it has any height. The room
		has five children: header, thread, status, error, composer. With the
		status and the error empty and flat (STATUS_LINE), the plain column
		still puts three theme gaps between the thread and the composer where
		one belongs. At 2x that is thirty-two surplus pixels sitting under the
		last bubble, fixed, exactly as Larry described it - "a rather large
		space ... which remains fixed".

		So a flat child is skipped: not laid out at a height, not counted for
		a join, and not given a share of the leftover a grower would claim.
		It still gets `set_bounds' - at the running position, zero tall - so
		its geometry stays honest for hit testing and for anything that reads
		it, and it is still DRAWN, so a widget that paints something inside a
		zero rectangle is the widget's own business, not the column's.

		This belongs in simple_widgets, as an SW_WIDGET-level rule: a widget
		whose clamped preferred height is zero takes no space and no gap in
		either box. It lives here because simple_widgets is checked out on
		another branch this week.
	]"
	author: "Larry Rix"

class
	COLLAPSING_COLUMN

inherit
	SW_COLUMN
		redefine
			preferred_height, arrange
		end

create
	make

feature -- Layout

	is_collapsed (a_w: SW_WIDGET; a_p: SW_PAINTER; a_inner: REAL_64): BOOLEAN
			-- Would `a_w', laid out `a_inner' wide, take no vertical space?
			-- Asked through `clamped_height', because that is what `arrange'
			-- would actually give it - a minimum height beats a zero natural one.
		require
			sane_width: a_inner >= 0.0
		do
			Result := a_w.clamped_height (a_w.preferred_height (a_p, a_inner)) <= 0.0
		end

	visible_children (a_p: SW_PAINTER; a_inner: REAL_64): INTEGER
			-- How many children are actually taking space at `a_inner' wide.
		require
			sane_width: a_inner >= 0.0
		do
			across
				children as c
			loop
				if not is_collapsed (c, a_p, a_inner) then
					Result := Result + 1
				end
			end
		ensure
			in_range: Result >= 0 and Result <= children.count
		end

	preferred_height (a_p: SW_PAINTER; a_width: REAL_64): REAL_64
			-- SW_COLUMN's own sum, with the flat children left out of both
			-- the heights and the joins.
		local
			inner, pad, gp, h: REAL_64
			n: INTEGER
		do
			pad := effective_padding (a_p)
			gp := effective_gap (a_p)
			inner := (a_width - 2.0 * pad).max (0.0)
			across
				children as c
			loop
				h := c.clamped_height (c.preferred_height (a_p, inner))
				if h > 0.0 then
					Result := Result + h
					n := n + 1
				end
			end
			if n > 1 then
				Result := Result + gp * (n - 1)
			end
			Result := Result + 2.0 * pad
		end

	arrange (a_p: SW_PAINTER)
			-- SW_COLUMN's own pass, with the flat children given a zero
			-- rectangle at the running position and no gap after them.
		local
			cy, inner, ch, natural, leftover, total_grow, pad, gp: REAL_64
			heights: ARRAYED_LIST [REAL_64]
			i, n: INTEGER
		do
			pad := effective_padding (a_p)
			gp := effective_gap (a_p)
			inner := (width - 2.0 * pad).max (0.0)
			create heights.make (children.count)
			across
				children as c
			loop
				heights.extend (c.clamped_height (c.preferred_height (a_p, inner)))
				if heights.last > 0.0 then
					natural := natural + heights.last
					total_grow := total_grow + c.grow
					n := n + 1
				end
			end
			if n > 1 then
				natural := natural + gp * (n - 1)
			end
			leftover := height - 2.0 * pad - natural
			cy := y + pad
			from
				i := 1
			until
				i > children.count
			loop
				ch := heights.i_th (i)
				if ch > 0.0 then
					if leftover > 0.0 and total_grow > 0.0 and children.i_th (i).grow > 0.0 then
						ch := children.i_th (i).clamped_height
							(ch + leftover * children.i_th (i).grow / total_grow)
					end
					children.i_th (i).set_bounds (x + pad, cy, inner, ch)
					children.i_th (i).arrange (a_p)
					cy := cy + ch + gp
				else
					children.i_th (i).set_bounds (x + pad, cy, inner, 0.0)
					children.i_th (i).arrange (a_p)
				end
				i := i + 1
			end
		end

end
