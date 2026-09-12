# Live validation against Jamf Pro 11.32.0

This document records the live Jamf Pro tests, their results, and the remaining
coverage gaps. `TESTING.md` covers layers 1–3: static checks, the library
harness, and mock end-to-end tests. Use the procedure here to repeat the live
run.

Run these tests only against a designated non-production Jamf instance. Never
run them against the work tenant.

| Date | Where it ran | Scope | Result |
|---|---|---|---|
| 2026-09-12 (first) | worker LXC, Debian 13 | 13 of 15 scripts, partial flag coverage | 55/55 after fixes |
| 2026-09-12 (second) | the authoring Mac | every flag of all 15 scripts | 161/161 |

The sections below document the 161/161 macOS run.

## Instance impact

The run created only `ZZ-LIVETEST-*` policies, deleted them afterward, and did
not modify any pre-existing policy, group, category, or user. Teardown confirms
cleanup by listing the instance rather than relying on its own delete loop.

## Run environment

The first run used the worker LXC. The scripts call `/usr/bin/plutil` and
`/sbin/md5`, neither of which exists on Debian, so that run required shims. GNU
`sed` and `awk` also hide the BSD incompatibilities that layers 2 and 3 expose
by forcing the stock `PATH`. A successful Debian run therefore did not prove
that the scripts worked on a Mac.

The macOS test host can reach the test instance directly.
`tests/live/every-flag.sh` runs the scripts under `env -i` with
`PATH=/usr/bin:/bin:/usr/sbin:/sbin` on macOS `/bin/bash` 3.2.57. One run tests
both environments:

| Axis | Proven by |
|---|---|
| Jamf Pro's real behaviour | the live instance |
| bash 3.2 / BSD toolchain | the stock PATH and the real `/bin/bash` |

No shims are required. When no preference file exists,
`ResolveJamfProCredentials` falls through to `JAMF_PRO_URL`,
`JAMF_PRO_CLIENT_ID`, and `JAMF_PRO_CLIENT_SECRET`.

## Directory service

The instance had no LDAP server or Cloud Identity Provider before 2026-09-12.
Without a directory service, positive writes to `limitations/user_groups`
through `Add_`/`Remove_Policy_Scope_Limitation.sh` could not be validated.

A self-hosted [lldap](https://github.com/lldap/lldap) instance now supplies the
directory fixtures. Its host, network, ports, base DN and bind account are
intentionally omitted.

Use this working attribute mapping when rebuilding it:

- Users: `ou=people`; object classes `inetOrgPerson, person`; attributes
  `uid`/`cn`/`mail`/`entryuuid`.
- Groups: `ou=groups`; object classes `groupOfUniqueNames, groupOfNames`; `cn`
  for both ID and name.
- Membership: stored in `group object`, using `uniqueMember` with DN enabled.
  Jamf rejects the string `The group object` with HTTP 409.

Seeded groups are `ZZ-LIVETEST-Limited`, `ZZ-LIVETEST-Excluded`,
`Corp.Marketing` (contains a regex metacharacter), and `Design Team` (contains a
space). Seeded users are `zz-livetest-alice` and `zz-livetest-bob`.

Entra group lookup by name on the work tenant remains untested because its
backing directory differs, even though it uses the same container and code path.

## Credentials

Create a dedicated API role and client for each run. Grant access only to
policies, categories, and group reads. Do not grant computer, profile, script,
package, or MDM-command privileges; this limits the impact of a scope bug.
Delete the client and role after the run instead of leaving them enabled.

## Independent oracle

Every assertion reads the policy through `live_api` in
`tests/live/guard.sh`. This is plain curl and follows a different code path
from the script under test. The script's own read-back is not sufficient
evidence because these scripts specifically guard against successful-looking
writes that do not persist.

The runner's `xp()` function fails closed. An empty body becomes the literal
string `ORACLE-FAIL`, never `0`, so a failed read cannot look like a successful
removal.

## Defects found in the second run

The run found five defects. Four were invisible to every offline layer.

### 1. HTTP 409 can partially apply

A policy referenced a directory group that was later deleted. To make an
unrelated change, the writer resent the complete `<scope>`, as required by hard
rule 1:

```
PUT (add a computer group target)  -> HTTP 409
targets now                        -> 1 (change applied)
limitations/user_groups            -> <user_groups/> (orphan removed)
```

Because every writer returned before read-back on a non-2xx response, it
reported `FAILED` even when the write landed and did not report the orphan
deletion. A fleet-wide run over policies with stale directory groups could
therefore remove scope entries while appearing to fail.

Fix: HTTP 409 now proceeds to read-back after printing a warning that names the
backup.

### 2. `Remove_Policy_Scope_Limitation.sh --user-group` removed nothing

`limit_to_users` is the source and `limitations/user_groups` is the mirror;
the stored set is their union. The writer changed only the mirror, so Jamf
restored the entry and the script reported success. See `CLAUDE.md`,
"`limit_to_users` is the source".

### 3. Jamf discards logout trigger writes

Jamf responds with HTTP 201 to `<trigger_logout>true</trigger_logout>` but
discards the element. A `trigger_startup` in the same request persists, and a
subsequent GET never returns the logout element. The flag now fails with an
explanation.

### 4. `--show` and `--hide` together used the last value

The script silently accepted both flags and used whichever appeared last. The
flag parser now rejects the combination, matching `Set_Policy_Category.sh`.

### 5. An invalid `--category-id` left an empty backup directory and log

`PreflightCategory` ran after `mkdir`, unlike the exclusion pair's
`PreflightUserGroup`. The invalid ID was rejected only after the script created
an empty backup directory and log.

## Confirmed behavior

- A target write preserves all existing targets without modifying
  `<exclusions>`, confirming the container-replacement hazard covered by hard
  rule 1.
- Removing the only target returns `REFUSED` unless `--allow-empty-scope` is
  supplied.
- `Set_Policy_Category.sh` changes `general/category` and leaves
  `self_service/self_service_categories` unchanged.
- Enable and disable leave exactly one `<enabled>` element.
- `Add_Policy_Trigger.sh` rejects an automatic trigger on an enabled policy
  unless `--allow-auto-trigger` is supplied. It skips a policy that has a
  different custom event.
- Names containing spaces or regex metacharacters round-trip, including the
  tested username and the groups `Corp.Marketing` and `Design Team`.
- A wrong client secret exits 1, identifies the credentials rather than the
  URL, and leaves no backup directory.
- Jamf derives `general/trigger` from the trigger booleans, so these scripts do
  not write it.

## Token renewal with a token shorter than the renewal buffer

The library renews a token when it is within `token_renewal_buffer` (90
seconds) of expiry. Clients on this instance are often configured with a
60-second lifetime, so every check considers the token close to expiry.

This was tested with `accessTokenLifetimeSeconds` set to 60 and
`Enable_Policy.sh` run over three policies with `--delay 35`. The run took 217
seconds and enabled 3/3 policies. Renewal completed without authentication
failures but made extra token requests. If request volume becomes a concern,
increase the client lifetime rather than reducing the buffer.

## Test-runner failure modes

### Expired driver token

A driver that obtains one token and reuses it after a long run eventually gets
HTTP 401 from its own token. During verification, that can make a successful
script look broken. During cleanup, the DELETE requests can fail silently and
leave test policies on the server.

This happened during the first run: three `ZZ-LIVETEST-tok-*` policies remained
after the log claimed they had been deleted. Mint a new token before
verification and again before cleanup. Then confirm cleanup by listing the
instance.

### Assignment inside `$( )`

`mkpolicy` originally appended created IDs to a variable while running in a
command substitution. The list disappeared with the subshell, so teardown
deleted nothing. This is the same issue documented for `FetchPolicyXML` in the
library.

Teardown now finds policies to delete by listing the instance. This also
removes fixtures left by an earlier crashed run.

## Run procedure

```bash
export JAMF_PRO_URL=https://jamf.example.invalid
export JAMF_PRO_CLIENT_ID=...
export JAMF_PRO_CLIENT_SECRET=...
tests/live/every-flag.sh          # KEEP=1 keeps the work dir
```

`guard.sh` rejects any host other than the configured test instance with exit 3
and never prints a credential. Both `guard.sh` and `every-flag.sh` are checked
in. The first run's ad hoc phase drivers are not stored in the repository,
preventing accidental execution against the wrong instance.

Before rerunning:

- Confirm that the API client exists and has only the privileges listed above.
- Confirm that `ZZ-LIVETEST-` remains unused on the target.
- Confirm that lldap is running. The limitation tests cannot pass without it.
