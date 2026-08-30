note
	description: "[
		The one rule for where a client may send its token: https to a
		clean authority, or plain http to this machine's loopback - and
		nothing that merely starts like either. The authority is parsed,
		not prefix-matched, so `http://localhost@evil.example',
		`http://127.0.0.1.evil.example', `http://localhost.evil.example'
		and `https://user:pw@host' all fail, and a base URL carrying a
		query or fragment (which `url_for' would append a path to) is
		refused outright. CHAT_ENDPOINT and CLIENT_CONFIG inherit it; the
		assault fires the hostile forms at it directly.
	]"
	author: "Larry Rix"

class
	CHAT_URL_RULES

feature -- Validation (contract support)

	is_acceptable_url (a_url: READABLE_STRING_8): BOOLEAN
			-- https to a non-empty authority, or loopback http; clean throughout; no trailing slash.
		do
			Result := is_clean_url (a_url) and then not a_url.ends_with ("/")
				and then ((a_url.starts_with (Https_scheme) and then not authority_of (a_url).is_empty) or is_loopback_url (a_url))
		ensure
			clean: Result implies is_clean_url (a_url)
			no_trailing_slash: Result implies not a_url.ends_with ("/")
			https_or_loopback: Result implies (a_url.starts_with (Https_scheme) or is_loopback_url (a_url))
			has_authority: Result implies not authority_of (a_url).is_empty
		end

	is_loopback_url (a_url: READABLE_STRING_8): BOOLEAN
			-- A web URL whose authority is exactly a loopback host (127.0.0.1, localhost, [::1])
			-- with an optional digits-only port 1..65535 - nothing else before the first "/" or the end.
		local
			l_authority, l_host, l_rest: STRING_8
			l_cut: INTEGER
		do
			if is_clean_url (a_url) and then is_web_url (a_url) then
				l_authority := authority_of (a_url)
				create l_host.make_empty
				create l_rest.make_empty
				if l_authority.starts_with ("[") then
					l_cut := l_authority.index_of (']', 1)
					if l_cut > 0 then
						l_host := l_authority.substring (1, l_cut)
						l_rest := l_authority.substring (l_cut + 1, l_authority.count)
					end
				else
					l_cut := l_authority.index_of (':', 1)
					if l_cut = 0 then
						l_host := l_authority
					else
						l_host := l_authority.substring (1, l_cut - 1)
						l_rest := l_authority.substring (l_cut, l_authority.count)
					end
				end
				Result := is_loopback_host (l_host)
					and then (l_rest.is_empty or else (l_rest.count >= 2 and then l_rest [1] = ':' and then is_valid_port (l_rest.substring (2, l_rest.count))))
			end
		ensure
			web: Result implies is_web_url (a_url)
			clean: Result implies is_clean_url (a_url)
		end

	is_loopback_host (a_host: READABLE_STRING_8): BOOLEAN
			-- Exactly 127.0.0.1, [::1], or localhost (any case)?
		do
			Result := a_host.same_string ("127.0.0.1") or a_host.same_string ("[::1]") or a_host.as_lower.same_string ("localhost")
		end

	is_valid_port (a_text: READABLE_STRING_8): BOOLEAN
			-- One to five digits, 1..65535?
		do
			Result := a_text.count >= 1 and then a_text.count <= 5
				and then (across a_text as c all c.is_digit end)
				and then (a_text.to_integer >= 1 and a_text.to_integer <= 65535)
		ensure
			digits_only: Result implies across a_text as c all c.is_digit end
		end

	is_clean_url (a_url: READABLE_STRING_8): BOOLEAN
			-- Non-empty, printable ASCII only, and nowhere an "@", "?" or "#".
		do
			Result := not a_url.is_empty
				and then across a_url as c all (c.code >= 33 and c.code <= 126 and c /= '@' and c /= '?' and c /= '#') end
		end

	is_web_url (a_url: READABLE_STRING_8): BOOLEAN
		do
			Result := a_url.starts_with (Http_scheme) or a_url.starts_with (Https_scheme)
		end

	authority_of (a_url: READABLE_STRING_8): STRING_8
			-- What follows the scheme up to the first "/" or the end; empty when `a_url' is not a web URL.
		local
			l_start, l_slash: INTEGER
		do
			l_start := scheme_of (a_url).count + 1
			if l_start > 1 then
				l_slash := a_url.index_of ('/', l_start)
				if l_slash = 0 then
					Result := a_url.substring (l_start, a_url.count).to_string_8
				else
					Result := a_url.substring (l_start, l_slash - 1).to_string_8
				end
			else
				create Result.make_empty
			end
		ensure
			no_slash: not Result.has ('/')
			empty_unless_web: not is_web_url (a_url) implies Result.is_empty
		end

	scheme_of (a_url: READABLE_STRING_8): STRING_8
			-- "https://", "http://", or empty.
		do
			if a_url.starts_with (Https_scheme) then
				Result := Https_scheme
			elseif a_url.starts_with (Http_scheme) then
				Result := Http_scheme
			else
				create Result.make_empty
			end
		ensure
			prefix: a_url.starts_with (Result)
		end

	same_url (a_first, a_second: READABLE_STRING_8): BOOLEAN
			-- Equal once scheme and authority are compared without regard to case; the path compares as is.
		do
			Result := normalized_url (a_first).same_string (normalized_url (a_second))
		ensure
			reflexive_on_case: Result implies a_first.count = a_second.count
		end

	normalized_url (a_url: READABLE_STRING_8): STRING_8
			-- `a_url' with its scheme and authority lowered (whatever case they came in) and the rest untouched.
		local
			l_lower: STRING_8
			l_end: INTEGER
		do
			create l_lower.make_from_string (a_url)
			l_lower.to_lower
			l_end := scheme_of (l_lower).count + authority_of (l_lower).count
			create Result.make (a_url.count)
			Result.append (l_lower.substring (1, l_end))
			Result.append (a_url.substring (l_end + 1, a_url.count))
		ensure
			same_length: Result.count = a_url.count
		end

feature -- Constants

	Http_scheme: STRING_8 = "http://"
	Https_scheme: STRING_8 = "https://"

end
