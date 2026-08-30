# CONTRACT DESIGN: simple_chat

Date: 2026-08-29. Contracts are the guardrails Larry asked for (I-003): ordering, the marker, rate limits and token entropy are invariants, not conventions.

## MML Model Queries

| Owner | Attribute | Model Query | MML Type | Used by |
|-------|-----------|-------------|----------|---------|
| `MEMORY_CHAT_STORE` | events | `events_model` | `MML_SEQUENCE [CHAT_EVENT]` | append/list frame conditions |
| `MEMORY_CHAT_STORE` | users | `users_model` | `MML_MAP [INTEGER_64, CHAT_USER]` | create_user frame conditions |
| `EVENT_BUS` | subscribers | `subscribers_model` | `MML_SET [EVENT_SUBSCRIBER]` | subscribe/unsubscribe/publish |
| `RATE_LIMITER` | windows | `counts_model` | `MML_MAP [STRING_8, INTEGER]` | record/is_allowed |

(`SQLITE_CHAT_STORE` satisfies the same postconditions by construction; its model queries read back from the database in the assault build only.)

## Class Contracts

### CHAT_STORE (deferred)
```eiffel
append_event (a_event: CHAT_EVENT_DRAFT): CHAT_EVENT
    require
        room_exists: has_room (a_event.room_id)
        sender_exists: a_event.kind ~ Kind_system or has_user (a_event.sender_id)
    deferred
    ensure
        assigned_id: Result.id > 0
        strictly_increasing: Result.id > old last_event_id          -- DR-001
        is_last: last_event_id = Result.id
        persisted: event (Result.id) ~ Result
        one_more: event_count = old event_count + 1
        others_untouched: events_model |=| (old events_model).extended (Result)   -- memory store; SQL store: count + ids

events_since (a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
    require
        room_exists: has_room (a_room_id)
        limit_positive: a_limit > 0
    deferred
    ensure
        bounded: Result.count <= a_limit
        all_after: across Result as e all e.id > a_since_id and e.room_id = a_room_id end
        ascending: across 1 |..| (Result.count - 1) as i all Result [i].id < Result [i + 1].id end
        contiguous: Result.count < a_limit implies Result.count = count_after (a_room_id, a_since_id)

put_session (a_session: CHAT_SESSION)
    require token_hashed: a_session.token_hash.count = 64
    ensure  stored: has_session_hash (a_session.token_hash)

invariant
    ids_monotonic: last_event_id >= 0
```

### CHAT_SERVICE
```eiffel
authenticate (a_username, a_password: READABLE_STRING_GENERAL; a_client_ip: READABLE_STRING_8): CHAT_RESULT [CHAT_SESSION]
    require
        username_given: not a_username.is_empty
        password_given: not a_password.is_empty
    ensure
        never_void: Result /= Void
        success_has_session: Result.is_success implies attached Result.value
        failure_counted: not Result.is_success implies
            limits.count ("login:user:" + a_username.as_lower.to_string_8) = old limits.count ("login:user:" + a_username.as_lower.to_string_8) + 1
        locked_out_stays_out: old not limits.is_allowed ("login:user:" + a_username.as_lower.to_string_8) implies not Result.is_success   -- DR-013
        session_is_fresh: Result.is_success implies (attached Result.value as s and then s.expires_at > s.created_at)

post_message (a_sender: CHAT_USER; a_room: CHAT_ROOM; a_body: READABLE_STRING_32): CHAT_RESULT [CHAT_EVENT]
    require
        active_sender: a_sender.is_active
        member: store.is_member (a_sender.id, a_room.id)                       -- DR-003
        body_given: not a_body.is_empty
        within_limit: a_body.count <= config.message_limit                     -- DR-007
    ensure
        never_void: Result /= Void
        appended_on_success: Result.is_success implies store.last_event_id = old store.last_event_id + 1
        published_on_success: Result.is_success implies bus.published_count = old bus.published_count + 1
        marker_enforced: Result.is_success and a_sender.is_bot implies
            (attached Result.value as e and then e.body.starts_with (Bot_marker))     -- DR-002
        nothing_on_failure: not Result.is_success implies store.last_event_id = old store.last_event_id
        rate_limited: not old limits.is_allowed ("post:" + a_sender.id.out) implies not Result.is_success

create_user (a_username, a_display_name, a_password: READABLE_STRING_GENERAL; a_is_admin: BOOLEAN): CHAT_RESULT [CHAT_USER]
    require
        valid_username: is_valid_username (a_username)
        valid_display: not a_display_name.is_empty and a_display_name.count <= 40
        password_long_enough: a_password.count >= config.password_minimum
    ensure
        unique_or_error: Result.is_success = not (old store.has_username (a_username.as_lower))
        hashed_properly: Result.is_success implies (attached Result.value as u and then
            hasher.iterations_of (u.password_hash) >= {PASSWORD_HASHER}.Minimum_iterations)     -- DR-005
        never_stores_plaintext: Result.is_success implies (attached Result.value as u and then not u.password_hash.has_substring (a_password))
```

### PASSWORD_HASHER
```eiffel
hash (a_password: READABLE_STRING_GENERAL): STRING_8
    require not_empty: not a_password.is_empty
    ensure
        format: Result.occurrences ('$') = 2
        floor: iterations_of (Result) >= Minimum_iterations                    -- 600,000
        salted: salt_of (Result).count = 32                                     -- 16 bytes hex

verify (a_password: READABLE_STRING_GENERAL; a_stored: STRING_8): BOOLEAN
    require not_empty: not a_password.is_empty and not a_stored.is_empty
    ensure constant_time: True   -- documented: delegates to SIMPLE_ENCRYPTION.verify_password (constant-time compare)

invariant
    floor_is_owasp: Minimum_iterations = 600_000
```

### SESSION_ISSUER
```eiffel
issue (a_user: CHAT_USER; a_lifetime_seconds: INTEGER_64; a_is_bot_token: BOOLEAN): TUPLE [token: STRING_8; session: CHAT_SESSION]
    require
        active: a_user.is_active
        lifetime_positive: a_lifetime_seconds > 0
        bots_get_bot_tokens: a_is_bot_token = a_user.is_bot
    ensure
        token_entropy: Result.token.count = 64                                   -- 32 CSPRNG bytes, hex  (DR-006)
        only_hash_stored: Result.session.token_hash ~ hash_of (Result.token)
        not_the_token: not Result.session.token_hash.same_string (Result.token)
        expiry_ahead: Result.session.expires_at > Result.session.created_at
```

### RATE_LIMITER
```eiffel
is_allowed (a_key: STRING_8): BOOLEAN
    ensure definition: Result = (count (a_key) < limit_for (a_key))

record (a_key: STRING_8)
    require allowed: is_allowed (a_key)
    ensure
        counted: count (a_key) = old count (a_key) + 1
        others_unchanged: across old counts_model.domain as k all k /~ a_key implies count (k) = (old counts_model) [k] end

invariant
    never_over: across counts_model.domain as k all count (k) <= limit_for (k) end
    windows_positive: window_seconds > 0
```

### EVENT_BUS
```eiffel
subscribe (a_subscriber: EVENT_SUBSCRIBER)
    require not_yet: not subscribers_model.has (a_subscriber)
    ensure  added: subscribers_model |=| (old subscribers_model) & a_subscriber

unsubscribe (a_subscriber: EVENT_SUBSCRIBER)
    require present: subscribers_model.has (a_subscriber)
    ensure  removed: subscribers_model |=| (old subscribers_model) / a_subscriber

publish (a_event: CHAT_EVENT)
    ensure
        counted: published_count = old published_count + 1
        delivered: across old subscribers_model as s all s.last_received_id >= a_event.id end
        subscribers_unchanged: subscribers_model |=| old subscribers_model

publish_status (a_status: CHAT_STATUS)
    ensure not_persisted: True   -- DR-009: the bus has no store reference; nothing to persist with
```

### EVENT_SOURCE (deferred) and SSE_STREAM
```eiffel
-- EVENT_SOURCE
open (a_room_id, a_since_id: INTEGER_64)
    require not_open: not is_open
    ensure  open: is_open; from_set: since_id = a_since_id; room_set: room_id = a_room_id
deliver_pending
    require open: is_open
    ensure  caught_up: last_delivered_id >= store.last_event_id_for (room_id) or else not is_open
    ensure  in_order: last_delivered_id >= old last_delivered_id

-- SSE_STREAM (EVENT_SOURCE + EVENT_SUBSCRIBER)
receive (a_event: CHAT_EVENT)      -- from the bus
    require open: is_open; relevant: a_event.room_id = room_id
    ensure
        monotonic: a_event.id <= last_delivered_id implies last_delivered_id = old last_delivered_id   -- duplicates dropped
        written: a_event.id > old last_delivered_id implies last_delivered_id = a_event.id
heartbeat
    require open: is_open
    ensure  written_comment: bytes_written > old bytes_written

invariant
    heartbeat_interval_positive: heartbeat_seconds > 0
    never_backwards: last_delivered_id >= since_id
```

### AI_DISPATCHER (EVENT_SUBSCRIBER)
```eiffel
receive (a_event: CHAT_EVENT)
    ensure
        ignores_bots: a_event.is_bot_authored implies requests_seen = old requests_seen      -- no echo loops
        ignores_untriggered: not parser.is_triggered (a_event.body) implies requests_seen = old requests_seen
        rate_limited_not_asked: (parser.is_triggered (a_event.body) and not a_event.is_bot_authored
            and not old limits.is_allowed ("ai:" + a_event.sender_id.out)) implies participant.calls = old participant.calls
        asked_once: (parser.is_triggered (a_event.body) and not a_event.is_bot_authored
            and old limits.is_allowed ("ai:" + a_event.sender_id.out)) implies participant.calls = old participant.calls + 1
        always_answers: (parser.is_triggered (a_event.body) and not a_event.is_bot_authored) implies
            store.last_event_id > old store.last_event_id                     -- a reply, a refusal, or an apology

invariant
    one_at_a_time: max_concurrent = 1
    bot_user_is_bot: bot_user.is_bot
```

### AI_PARTICIPANT (deferred)
```eiffel
answer (a_request: AI_REQUEST): AI_ANSWER
    require asked: not a_request.question.is_empty; named: not a_request.asker_display_name.is_empty
    deferred
    ensure
        counted: calls = old calls + 1
        outcome: Result.is_success xor (Result.error /= Void)
        bounded: Result.is_success implies Result.text.count <= a_request.max_characters
```

### FRONT_DOOR (deferred)
```eiffel
start
    require
        not_serving: not is_serving
        upstream_known: upstream_port > 0
        named_when_public: is_public implies not public_name.is_empty
    deferred
    ensure
        outcome: is_serving xor (last_error /= Void)

stop
    ensure stopped: not is_serving; no_orphan: not has_child_process

invariant
    serving_has_name: is_serving and is_public implies not public_name.is_empty
    forwarded_headers: is_serving implies sets_forwarded_headers                 -- what CHAT_WEB_APP relies on (DR-010)
```
`CADDY_FRONT_DOOR` adds: `caddyfile_written: is_serving implies caddyfile_path_exists`, `supervised: is_serving implies child_is_alive`. `NO_FRONT_DOOR`: `start` ensures `is_serving` immediately. `EIFFEL_FRONT_DOOR` (v1 stub): `start` ensures `last_error /= Void` — honest until Tier 1 lands.

### SERVER_CONFIG
```eiffel
invariant
    port_in_range: port >= 1 and port <= 65535
    localhost_only: bind_address ~ "127.0.0.1"
    known_door: front_door_kind ~ "caddy" or front_door_kind ~ "eiffel" or front_door_kind ~ "none"
    public_when_doored: front_door_kind /~ "none" implies not public_name.is_empty
    limits_positive: message_limit > 0 and upload_limit_bytes > 0 and ai_requests_per_hour >= 0
    session_lifetime_positive: session_lifetime_seconds > 0
    ddns_needs_token: ddns_enabled implies not ddns_token.is_empty
```

### CHAT_USER
```eiffel
invariant
    username_shape: username.count >= 1 and username.count <= 32 and is_lower_alnum_underscore (username)
    display_shape: display_name.count >= 1 and display_name.count <= 40
    people_have_hashes: not is_bot implies password_hash.occurrences ('$') = 2
    bots_have_none: is_bot implies password_hash.is_empty
```

### CHAT_SESSION
```eiffel
invariant
    hash_shape: token_hash.count = 64
    lifetime: expires_at > created_at
```

## Contract Completeness Checklist
Every postcondition above answers:
- [x] **What changed?** — `appended_on_success`, `counted`, `added`, `caught_up`
- [x] **How did it change?** — relative to `old` (`last_event_id + 1`, `count + 1`, `|=| old … & x`)
- [x] **What did NOT change?** — `nothing_on_failure`, `others_unchanged`, `subscribers_unchanged`, `ignores_bots`
