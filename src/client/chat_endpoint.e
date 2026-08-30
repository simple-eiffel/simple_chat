note
	description: "[
		Where a client talks to: a base URL and whether it is the local
		service. Built by SERVICE_LOCATOR; every request URL comes from
		`url_for', so no other class concatenates paths onto the base.
	]"
	author: "Larry Rix"

class
	CHAT_ENDPOINT

create
	make

feature {NONE} -- Initialization

	make (a_base_url: READABLE_STRING_8; a_is_local: BOOLEAN)
		require
			web_url: a_base_url.starts_with ("http://") or a_base_url.starts_with ("https://")
			no_trailing_slash: not a_base_url.ends_with ("/")
			local_means_loopback: a_is_local implies (a_base_url.starts_with ("http://127.0.0.1") or a_base_url.starts_with ("http://localhost"))
		do
			base_url := a_base_url.to_string_8
			is_local := a_is_local
		ensure
			set: base_url.same_string (a_base_url) and is_local = a_is_local
		end

feature -- Access

	base_url: STRING_8

	is_local: BOOLEAN
			-- The service on this machine?

	url_for (a_path: READABLE_STRING_8): STRING_8
			-- `base_url' + `a_path'.
		require
			rooted: a_path.starts_with ("/")
		do
			Result := base_url + a_path
		ensure
			prefixed: Result.starts_with (base_url)
			suffixed: Result.ends_with (a_path)
		end

feature -- Status report

	is_secure: BOOLEAN
			-- https, or loopback (which needs no TLS)?
		do
			Result := base_url.starts_with ("https://") or is_local
		end

invariant
	web_url: base_url.starts_with ("http://") or base_url.starts_with ("https://")
	local_is_loopback: is_local implies (base_url.starts_with ("http://127.0.0.1") or base_url.starts_with ("http://localhost"))

end
