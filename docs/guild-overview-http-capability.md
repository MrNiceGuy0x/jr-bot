# Bounded Guild Overview HTTP capability

Candidate only; no live endpoint was called. A GET to this API writes server data.

Only `payload.action=guild_overview_refresh` resolves to the local policy at
`config/capabilities.d/guild_overview.http.json`. The supplied repo policy is an
example candidate, not automatically installed. Exact HTTPS origin, GET path,
TLS verification, no redirects/proxy/job overrides, 10-second connection limit,
60-second parent-enforced request budget and 1-MiB response limit are mandatory.
The spawned child is terminated on budget expiry; cleanup has an additional
bounded four seconds. Neither timeout nor ambiguous response causes an automatic
HTTP retry. Provider max_attempts=1; the next regular occurrence is independent.
The HTTP lease lasts at least 120 seconds so the request/cleanup budget fits
within the renewed dispatch. This does not modify tbl_jobs.grace_sec.

Success requires the complete expected UTF-8 response: one positive member
count, exactly that many distinct member-save lines and the completion line,
with only the expected p/br markup. Other messages, PHP diagnostics, cooldown,
partial response, duplicate members, non-200, compression, redirects and body
limits produce an unconfirmed failure. This proves the received response only,
not an atomic server transaction. The supplied API is not transactionally
idempotent; no blind replay follows a lost response. Imported guild_protocol.php
may add output: that output is conservatively unconfirmed until separately
reviewed. No undocumented output is accepted merely to obtain a green status.

At startup coalesce_latest gives each due active job at most one current
occurrence, not historical snapshots. Explicitly disabled jobs stay disabled.
The policy is fixed; arbitrary URL HTTP and legacy shell execution are absent.
Deployment of module and root-controlled policy, published-byte verification,
credentials and activation require their separate gates. The existing installers
remain pinned to their accepted pre-correction release; this candidate is not
silently installed by those installers.
