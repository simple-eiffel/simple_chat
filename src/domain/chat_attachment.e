note
	description: "[
		An uploaded image, stored on disk under its content hash - never
		under a name the uploader chose. `stored_relpath' is computed, not
		given: uploads/<sha256>.<png|jpg>, so no caller and no wire form
		can name a path. `original_name' is metadata for display only.
		`id' is 0 until the store has assigned one.

		Value semantics (Issue 23 / M-D3): `make' copies its incoming text,
		`is_equal' compares by value, `duplicate' builds an independent copy.
		The attributes stay STRING_8/STRING_32; moving them to
		READABLE_/IMMUTABLE_ types is a Phase 4 task.
	]"
	author: "Larry Rix"

class
	CHAT_ATTACHMENT

inherit
	ANY
		redefine
			is_equal
		end

create
	make

feature {NONE} -- Initialization

	make (a_id, a_uploader_id: INTEGER_64; a_original_name: READABLE_STRING_GENERAL; a_mime: READABLE_STRING_8;
			a_size: INTEGER_64; a_sha256: READABLE_STRING_8; a_created_at: SIMPLE_DATE_TIME)
		require
			id_non_negative: a_id >= 0
			uploader_stored: a_uploader_id > 0
			valid_name: rules.is_valid_name (a_original_name)
			has_bytes: a_size > 0
			allowed_type: rules.is_allowed_mime (a_mime)
			hash_shape: rules.is_sha256_hex (a_sha256)
		do
			id := a_id
			uploader_id := a_uploader_id
			create original_name.make_from_string_general (a_original_name)
			create mime.make_from_string (a_mime)
			size := a_size
			create sha256.make_from_string (a_sha256)
			stored_relpath := rules.stored_path_for (sha256, mime)
			created_at := a_created_at
		ensure
			set: id = a_id and uploader_id = a_uploader_id and size = a_size
			name_set: original_name.same_string_general (a_original_name)
			mime_set: mime.same_string (a_mime)
			hash_set: sha256.same_string (a_sha256)
			owns_text: original_name /= a_original_name and mime /= a_mime and sha256 /= a_sha256
			created_set: created_at = a_created_at
			path_computed: stored_relpath.same_string (rules.stored_path_for (a_sha256, a_mime))
		end

feature -- Access

	id, uploader_id: INTEGER_64
	original_name: STRING_32
	mime: STRING_8
	size: INTEGER_64
	sha256: STRING_8
	stored_relpath: STRING_8
	created_at: SIMPLE_DATE_TIME

feature -- Status report

	is_stored: BOOLEAN
		do
			Result := id > 0
		ensure
			definition: Result = (id > 0)
		end

feature -- Element change

	set_id (a_id: INTEGER_64)
		require
			not_yet_stored: id = 0
			positive: a_id > 0
		do
			id := a_id
		ensure
			set: id = a_id
			rest_unchanged: uploader_id = old uploader_id and sha256 = old sha256 and stored_relpath = old stored_relpath
		end

feature -- Comparison

	is_equal (a_other: like Current): BOOLEAN
			-- Do `Current' and `a_other' carry the same values, text compared by content?
		do
			Result := id = a_other.id
				and uploader_id = a_other.uploader_id
				and original_name.same_string (a_other.original_name)
				and mime.same_string (a_other.mime)
				and size = a_other.size
				and sha256.same_string (a_other.sha256)
				and stored_relpath.same_string (a_other.stored_relpath)
				and created_at ~ a_other.created_at
		ensure then
			definition: Result = (id = a_other.id
				and uploader_id = a_other.uploader_id
				and original_name.same_string (a_other.original_name)
				and mime.same_string (a_other.mime)
				and size = a_other.size
				and sha256.same_string (a_other.sha256)
				and stored_relpath.same_string (a_other.stored_relpath)
				and created_at ~ a_other.created_at)
		end

feature -- Duplication

	duplicate: like Current
			-- An independent copy with fresh strings, equal to `Current' by value.
		do
			create Result.make (id, uploader_id, original_name, mime, size, sha256, created_at)
		ensure
			equal_value: Result ~ Current
			distinct: Result /= Current
			own_text: Result.original_name /= original_name and Result.mime /= mime and Result.sha256 /= sha256
		end

feature -- Validation (contract support)

	is_allowed_mime (a_mime: READABLE_STRING_8): BOOLEAN
		do
			Result := rules.is_allowed_mime (a_mime)
		end

	rules: CHAT_ATTACHMENT_RULES
		once
			create Result
		end

feature -- Constants

	Mime_png: STRING_8 = "image/png"
	Mime_jpeg: STRING_8 = "image/jpeg"
	Uploads_prefix: STRING_8 = "uploads/"

invariant
	id_non_negative: id >= 0
	uploader_stored: uploader_id > 0
	name_shape: rules.is_valid_name (original_name)
	has_bytes: size > 0
	allowed_type: rules.is_allowed_mime (mime)
	hash_shape: rules.is_sha256_hex (sha256)
	path_pinned: stored_relpath.same_string (rules.stored_path_for (sha256, mime))

end
