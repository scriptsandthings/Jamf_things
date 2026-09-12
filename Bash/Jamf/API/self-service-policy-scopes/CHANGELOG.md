# Changelog

All notable changes to the scripts, library and tests in this directory.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Entries are dated, newest first; the per-script SCRIPT_VERSION constants are
not bumped for review fixes.

---

## 2026-09-12 — one runner for all four layers; mock taught the rest of Jamf's resolution

### Added

- **`tests/run-all.sh`** — all four layers, in order, one exit code. Layer 4 is
  reported as SKIPPED *loudly* when the `JAMF_PRO_*` variables are absent,
  never quietly omitted: every defect fixed earlier today passed layers 1–3
  before the live suite caught it, so a green offline run is a model agreeing
  with itself.
- **`tests/install-hooks.sh`** — installs a `pre-push` hook that runs layers
  1–3 and blocks the push on a failure, then warns when `scripts/` is newer
  than the last successful live run. It warns rather than blocks because a
  live run needs a reachable server and a credential, and refusing a push
  because a host is down would be worse than the gap. `every-flag.sh` now
  stamps `tests/live/.last-success` on a clean run; it is gitignored, being a
  fact about one machine rather than about the repo.
- **Mock parity, four gaps closed.** The mock now returns a category body for
  `Set_Policy_Category.sh`'s preflight, can be made to answer 429 on a PUT
  (not only a GET), models the `limit_to_users` union, and models the
  409-with-partial-apply shape. Two new `tests/e2e.sh` sections cover
  server-side resolution and the PUT-side 429.
- **Fixture gaps.** `policy-101.xml` now populates `jss_users` in both targets
  and exclusions — the container that distinguishes a Jamf Pro user from a
  directory user, and the one most likely to be confused. `policy-202.xml`
  carries a comment saying its shape is deliberately unrealistic, so nobody
  "fixes" it to match the server.

### Fixed

- **The documented lint command was wrong.** `shellcheck -x` alone cannot
  follow `# shellcheck source=lib/jamf-api-common.sh`, which resolves relative
  to the script, so it reported `SC1091` plus a wall of `SC2154` for every
  library variable — noise that trained the eye to ignore layer 1.
  `--source-path=scripts` is required, and with it there are zero findings.
  Corrected in `CLAUDE.md`, `TESTING.md` and `run-all.sh`.
- Stale check counts in `README.md`, `CLAUDE.md` and `TESTING.md`: the harness
  is 137 and the end-to-end suite 135, not 136 and 129.

---

## 2026-09-12 — every flag validated against live Jamf Pro; five defects fixed

`tests/live/every-flag.sh` exercises all 29 flags across the 15 scripts plus
every refusal path against the homelab instance — 161 checks — with an
independent curl oracle. It runs **on macOS** under `env -i` and a stock PATH,
so one pass proves both Jamf's behaviour and bash 3.2 / BSD compatibility. The
earlier run on the Debian worker proved only the first: `plutil` and `md5` had
to be shimmed there, and GNU `sed`/`awk` mask exactly what the stock PATH
exists to expose.

A self-hosted lldap directory service was added to the homelab instance first.
Without one, `limitations/user_groups` cannot hold anything, and three of the
five defects below are invisible.

### Fixed

- **A 409 partially applies, and every writer reported it as a clean failure.**
  A policy carried a directory group later deleted from the directory. A PUT
  resending the whole `<scope>` — which hard rule 1 requires — to make an
  *unrelated* change answered 409, applied the change anyway, and silently
  dropped the unresolvable entry. Every writer returned on any non-2xx before
  the read-back, so the operator saw FAILED for a write that landed and nothing
  about the entry Jamf destroyed. A fleet-wide run against policies carrying
  stale directory groups would have reported a wall of failures while quietly
  stripping scope. 409 now falls through to the read-back after a WARNING
  naming the backup; every other non-2xx still returns early. The block was
  byte-identical in all fourteen writers and was patched identically.

- **`Remove_Policy_Scope_Limitation.sh --user-group` never removed anything.**
  It answered 201 and reported success while the group stayed on the policy.
  `limit_to_users/user_groups` is the source and `limitations/user_groups` a
  mirror Jamf regenerates from it; the stored set is their union, so an add
  works from either side but a removal only sticks when the entry is gone from
  both. The writer edited only the mirror. `RemoveLimitToUsersGroup` now strips
  the source entry too, gated on removal by name because the source stores no
  ids.

- **The logout trigger is retired and could never be written.** A PUT carrying
  `<trigger_logout>true</trigger_logout>` is answered 201 and discarded while a
  `trigger_startup` in the same request lands; a GET never returns the element.
  The help text claimed it was "accepted because the API still carries it".
  `ResolveTriggerElement` no longer maps it, `TRIGGER_FLAG_NAMES` drops it, and
  `ExplainRetiredTrigger` prints the reason so the rejection does not read as a
  typo. `Set_Policy_Triggers.sh` owns five booleans now, not six.
  `DescribeTriggers` still recognises the element so archived backups still read.

- **`Set_Policy_Self_Service.sh --show --hide` silently took the last flag.**
  `Set_Policy_Category.sh` refuses `--category-id` with `--no-category`; this
  now counts selectors the same way.

- **`Set_Policy_Category.sh` left an empty backup directory and log behind** on
  a mistyped category. `PreflightCategory` ran after `mkdir` — the opposite
  order from the exclusion pair's `PreflightUserGroup`, and the same leftover
  the early authentication four lines above exists to prevent.

### Added

- `tests/live/every-flag.sh`. Teardown discovers what to delete by **listing the
  instance** rather than from a variable: `mkpolicy` runs inside `$( )`, so
  anything it assigns dies with the subshell — the same trap the library
  documents for `FetchPolicyXML`. Listing is also self-healing, clearing
  fixtures a crashed earlier run left behind.

- The mock now models Jamf's server-side resolution. It previously stored
  whatever a PUT contained, which made the writers' read-back branch — the
  entire reason hard rule 2 exists — unreachable in every test, and is why the
  retired logout trigger passed 129/129 both before and after removal. It now
  reproduces: a valid directory group stored and mirrored; an invalid one
  dropped with the rest of the request still applied and a 409 returned;
  `limitations/users` stored unvalidated; `exclusions/users` silently
  discarded; `jss_user_groups` name filled in server-side; `trigger_logout`
  stripped. `DIRECTORY_GROUPS` keeps `CorpXMarketing` resolvable on purpose —
  fixture 101 uses it as the decoy proving that removing `Corp.Marketing` does
  not also take it out, and the unresolvable case gets its own name so the two
  tests stay independent.

### Changed

- One e2e assertion was wrong and is corrected: a Jamf Pro user group ID cannot
  become a *directory* limitation. It only ever passed because the mock stored
  whatever it was handed.

- `CLAUDE.md`, `README.md`, `TESTING.md` and `LIVE-VALIDATION.md` rewritten
  where they now contradict the wire. The largest correction: "a scope entry
  Jamf cannot resolve is silently discarded with a 201" is **directory-state
  dependent and not uniform across containers** — groups are validated, users
  are not, and with a directory configured an unresolvable group is refused
  with a 409 rather than discarded.

### Still open

- Whether an **Entra** group arriving through a Cloud Identity Provider resolves
  by name. The homelab resolves through LDAP; same container, same code path,
  different directory.
- PI-005747, not observed on this instance.
- A real 429, never provoked.

---

## 2026-09-12 — scope container map wire-checked against live Jamf Pro 11.32.0

First contact with a real Jamf Pro server. Read-only apart from two throwaway
`ZZ-LIVETEST-probe*` policies, both deleted.

### Added

- `CLAUDE.md`: the full ten-container scope map, with each container tied to
  the UI menu label that produces it, read off `GET /JSSResource/policies/id/13`
  rather than inferred. Jamf returns every container even when empty, so the
  server states its own schema.
- `CLAUDE.md`: the three "Add" menus recorded verbatim — Deployment Targets
  offers four kinds, Limitations four, Exclusions ten.

### Discovered

- **`jss_user_groups` and `user_groups` are different containers**, as are
  `jss_users` and `users`. The UI's "User Groups" is `jss_user_groups`, a Jamf
  Pro object addressed by `<id>`; "Directory Service User Groups" is
  `user_groups`, resolved against LDAP or a Cloud Identity Provider at scope
  time. The previous four-row table in `CLAUDE.md` collapsed both pairs into
  one row each and omitted the `jss_*` containers entirely.
- **A scope entry Jamf cannot resolve is silently discarded.** A PUT carrying
  four exclusion entries answered success and stored three of them. An invented
  username in `exclusions/users`, an invented name in `exclusions/jss_users`,
  and a Jamf Pro user group id placed in `exclusions/user_groups` were all
  dropped with no error. Same failure shape as the `self_service_categories`
  finding, and the reason hard rule 2 exists: success is read-back, never the
  HTTP status.
- **`limitations/user_groups` is a no-op on a tenant with no directory
  service.** There is no directory in which to resolve the group, so the write
  is discarded. `Add_Policy_Scope_Limitation.sh --user-group` therefore cannot
  be positively validated on the homelab instance; its read-back will correctly
  report FAILED after a 201.
- **The exclusion pair cannot exclude a user group at all.** It accepts only
  `--group-id` (a computer group) and `--username`. No reason for the omission
  is recorded anywhere in this repo, and `CLAUDE.md` lists user groups as valid
  exclusions. This blocks the directory's driving use case, so the pair is
  gaining `--user-group` / `--user-group-id`, writing `jss_user_groups`.

### Defects found — the `jss_*` containers were never modelled

All three share one root cause: `jss_users` and `jss_user_groups` are
deployment targets and exclusion containers, and nothing in this directory knew
they existed. None is a regression; they have been latent since the first
commit.

1. **`CountScopeTargets` under-counts.** It sums `computers`,
   `computer_groups`, `buildings` and `departments` only. A policy scoped to a
   Jamf Pro user group has targets it does not see. Demonstrated against
   `tests/fixtures/policy-101.xml`, which now carries five targets:

   ```
   computers 1 · computer_groups 3 · jss_user_groups 1  -> real total 5
   CountScopeTargets reports: 4
   ```

   Impact is a **false refusal**, at `Remove_Policy_Scope_Target.sh:323`:
   removing the last computer group from a policy that also targets a Jamf Pro
   user group reports "would leave the policy with no targets at all" and skips.
   The policy would still have reached everyone in that user group. It fails
   closed, so nothing is written wrongly — but the message is untrue and the
   operation is blocked.

2. **The report omits `jss_users` and `jss_user_groups` from "Scope Targets".**
   `Generate_Self_Service_Policy_Report.sh` lines 308-311 collect computers,
   computer groups, buildings and departments. A policy targeted at people
   rather than Macs reports a thinner scope than it has.

3. **The report omits them from "Scope Exclusions" too** (lines 336-341). This
   one bites the directory's driving use case directly: after excluding a Jamf
   Pro user group from every Self Service policy, re-running the report shows
   no sign of the change. The column that should verify the work is blank.

### Added

- `Add_` / `Remove_Policy_Scope_Exclusion.sh` take `--user-group <name>` and
  `--user-group-id <n>`, writing `scope/exclusions/jss_user_groups`. This is
  the directory's driving use case: report every Self Service policy, then
  exclude one Jamf Pro user group from all of them. Non-Self-Service policies
  are skipped as before unless `--include-non-self-service` is given.
- A **preflight** on both, modelled on `Set_Policy_Category.sh`: the group is
  looked up by id or name before the backup directory is created, and a group
  the server does not know stops the run with exit 1. Without it Jamf would
  answer 201 and store nothing. `--user-group` is resolved to its id there,
  because `jss_user_groups` is addressed by `<id>`; the name never reaches an
  XPath, XML or an awk regex, which is why its character set can allow the
  leading `*` and the spaces real Jamf Pro group names carry.
- The confirmation token on both now carries the user-group dimension, so
  excluding a group and excluding a computer group against the same CSV cannot
  share a token. Spaces are folded to `_` as the limitation and trigger scripts
  already do: `APPLY-2-none-none-TESTING_-_Microsoft_OneDrive`.

### Fixed

- `CountScopeTargets` counts all six target containers. Was four; see the
  defect note above.
- `Generate_Self_Service_Policy_Report.sh` reports `jss_users` and
  `jss_user_groups` in both the "Scope Targets" and "Scope Exclusions" columns.
- Report column labels follow the Jamf Pro UI, which is what the person reading
  the CSV is looking at: `jss_users`/`jss_user_groups` are "Users"/"User
  Groups"; the directory-service `users`/`user_groups` are "Directory
  Users"/"Directory User Groups". Previously the directory containers were
  labelled "Users"/"User Groups", which is what the UI calls the other pair.

### Changed

- `tests/lib-harness.sh`: 127 checks to 136. Two existing `CountScopeTargets`
  assertions moved 4 to 5 and 3 to 4, because the fixture gained a target and
  the function stopped ignoring it. New group D7b/D7c covers insert and remove
  on `exclusions/jss_user_groups` with the same group id present as a
  deployment target.
- `tests/e2e.sh`: 117 checks to 129. New section 3b covers the unknown-group
  refusal, the two-flag usage error, add by id, add by name, and removal from
  `exclusions/jss_user_groups` leaving `scope/jss_user_groups` intact.
- `tests/mock/mock_jamf.py`: serves `GET /JSSResource/usergroups/id/{id}` and
  `/usergroups/name/{name}`, 200 with the group or 404, so the coming
  `--user-group` preflight is reachable from `tests/e2e.sh`. The name form
  returns a body carrying `<id>`, because that is what the caller reads out of
  it.
- `tests/fixtures/policy-101.xml`: carries all ten exclusion containers, as
  live Jamf Pro returns them, plus `jss_users` and `jss_user_groups` as
  deployment targets. The same user group id now appears as a target, which is
  what makes the section-binding case testable. Both suites stay green at
  127/127 and 117/117 — the fixture change is what exposes defect 1 rather
  than causing it.

### Validated live — thirteen of the fifteen scripts

Run against Jamf Pro 11.32.0 on disposable `ZZ-LIVETEST-*` policies only; the
instance is back to its original 17 policies.

| Area | Result |
|---|---|
| Report | 17 policies read, 11 Self Service, 13-column RFC 4180 CSV |
| Exclusions, incl. the new `--user-group` | 18/18 |
| Targets, category, enable/disable, Self Service, bad secret | 27/30 — the three were bad assertions in the test, see below |
| Triggers | 14/14 |

**`general/trigger` is recomputed by Jamf Pro.** A disabled policy with no
triggers read `USER_INITIATED`; after `--trigger startup` it read `EVENT`; after
removing that trigger it read `USER_INITIATED` again. Nothing here needs to
write it, and the trigger scripts are right to read and report it only. This
was the largest open question in `TESTING.md` and the answer is the one that
requires no code change.

Confirmed live, each on a real policy:

- A targets write leaves every pre-existing target in place and does not touch
  `<exclusions>` — the container-replace hazard behind hard rule 1.
- Removing the only target is `REFUSED` without `--allow-empty-scope`.
- `Set_Policy_Category.sh` moves `general/category` and leaves
  `self_service/self_service_categories` alone; the policy name survives.
- Enable and disable leave exactly one `<enabled>` element.
- `Set_Policy_Self_Service.sh --hide` leaves the Self Service categories list
  intact; `--show` restores visibility.
- `Add_Policy_Trigger.sh` refuses an automatic trigger on an **enabled** policy
  unless `--allow-auto-trigger` is given, and skips a policy carrying a
  different custom event.
- A wrong client secret exits 1, names the credentials rather than the URL, and
  leaves no backup directory behind.

Three assertions failed in the first writers run and all three were defects in
the test, not the scripts: one XPath used `and`, which returns a boolean rather
than a count, and two followed from a dry run that correctly changed nothing
because the enabled-policy trigger guard had refused it — leaving no
confirmation token for the apply step to use.

### Verified for the coming preflight

`Add_Policy_Scope_Exclusion.sh` will refuse a group that does not exist rather
than letting Jamf discard the write silently. The endpoints that check it,
wire-tested 2026-09-12:

| Request | Answer |
|---|---|
| `GET /JSSResource/usergroups/id/2` | 200 |
| `GET /JSSResource/usergroups/id/99999` | 404 |
| `GET /JSSResource/usergroups/name/TESTING%20-%20Microsoft%20OneDrive` | 200, `<id>` 2 |
| `GET /JSSResource/usergroups/name/NoSuchGroupHere` | 404 |

Spaces must be percent-encoded in the `name/` form, the same constraint
`Set_Policy_Category.sh` already documents for `categories/name/`. The name
lookup returns the group's `<id>`, which is what `jss_user_groups` is addressed
by — Jamf fills in the `<name>` child itself on read-back.

---

## 2026-09-12 — TESTING.md; harness portable

### Added

- `TESTING.md`: the four validation layers (static, library harness, end to
  end, pair diff), every check group and what it proves, the mock endpoint
  table, the fixture roles, what a green run does not prove, the checklist
  for a new script, and a dated record of results. The root `TESTPLAN.md`
  and `VALIDATION.md` point here.

### Fixed

- `tests/lib-harness.sh` extracted `DescribeTriggers` from an absolute path
  under one user's home, so it failed on any other checkout. Now relative to
  the library path it already computes.
- The harness rewrote `tests/fixtures/ids.csv` on every run with the same
  bytes. It reads the checked-in fixture now.

---

## 2026-09-12 — full review: fourteen defects fixed, test suites added

A multi-agent review of all sixteen files against Jamf's current OpenAPI
specs and developer docs, a stock-Tahoe runtime test, and a comment audit.
Every endpoint and every XML element the scripts use matched the specs and
none is on the deprecation register; the defects were all in the scripts.

### Fixed — would have produced wrong results

- **`Set_Policy_Triggers.sh` could never verify a Self Service policy.** Its
  `DescribeTriggers` re-added the "Self Service" prefix that `GetPolicyTriggers`
  already adds when the XML carries `<self_service>`, so the full policy read
  "Self Service, Self Service, …" and the edited `<general>` fragment never
  matched: every apply run logged FAILED plus a restore command after a
  successful write. The prefix is now normalised.
- **Remove scripts failed open on read-back.** `CountScopeEntry` prints 0 for
  an empty or non-XML body, and 0 is what a removal reads as success, so a
  timed-out or 401 verify GET reported UPDATED. Every GET now goes through
  `FetchPolicyXML`, which accepts only an HTTP 200 whose body parses; the same
  guard now precedes the pre-check, so a proxy's HTML page can no longer read
  as "already gone".
- **Ctrl-C did not stop an apply run.** The trap only revoked the token; the
  loop resumed, minted a fresh one and kept writing. Signal traps now `exit
  130`; the EXIT trap still revokes.
- **Custom events could be repointed or cleared without being named.**
  `Add_Policy_Trigger.sh --custom-event` overwrote a different event;
  `Set_Policy_Triggers.sh --no-custom-event` cleared every event in the CSV,
  and `--custom-event ""` did the same silently with an identical confirmation
  token. Add_ now skips a policy carrying a different event;
  `--no-custom-event` is replaced by `--clear-custom-event <name>`, which only
  clears that name and skips the policy whole on a mismatch; an empty name is
  a usage error.
- **Backups were overwritten on multi-value runs.** The scope scripts call
  `ProcessPolicy` once per value, and the second pass rewrote
  `policy-<id>-before.xml` with the state after the first PUT. Write-once now.
- **The printed restore command could not work.** No Authorization header and
  no timeouts; Basic auth on the Classic API ended in Jamf Pro 11.17. It now
  carries `-H "Authorization: Bearer $TOKEN"` and the curl timeouts.
- **Report "LDAP Groups" column was always empty.** The XPath read a `<name>`
  child that the schema does not have: `limit_to_users/user_groups/user_group`
  is a bare string. Fixed, with the extractor taking the tag name.
- **Report silently dropped unreadable policies.** No status check on the
  per-policy GET. Unreadable policies are now named on stderr, counted, and
  the script exits 1.
- **`ReplaceElementInSection` appended a duplicate** for any element shape it
  did not recognise (an open tag with an attribute, say). It now refuses.
- **`RemoveScopeEntry` regex escape** omitted `(`, `)` and `$`; a group named
  `Marketing (US)` could match the wrong entry. Every ERE metacharacter is
  escaped now. The targets bound also tolerates a self-closing
  `<limitations/>`.
- **Policy names with `&` printed as `&amp;`** in every log line and report
  column. `GetPolicyName` and `DecodeXMLEntities` in the library.

### Fixed — would have misled or annoyed

- Backup directory and `run.log` were created before authentication, so every
  wrong-secret attempt left an empty directory behind. Token first now.
- `Set_Policy_Category.sh` accepted `/` in a name but its preflight URL only
  encoded spaces; a slash now points the caller at `--category-id`.
- Report script: no `--help`, a Braille spinner that byte-sliced to garbage
  without a UTF-8 locale (launchd, a Jamf policy), a stray suffix-less mktemp
  file, signal 9 in the trap list, and a "not found" error when a tenant had
  no Self Service policies. `--output <file>`, ASCII spinner only on a TTY,
  a proper temp directory, header written up front.
- `Add_Policy_Scope_Limitation.sh --user-group` read-back failure now names
  Jamf product issue PI-005747, which can hide user-group limitations from
  the API after a successful write.
- CSV reader strips a UTF-8 byte-order mark (Excel "CSV UTF-8").
- Keep-alive comment overstated the docs: the endpoint is undocumented for
  client-credentials tokens, not documented as inapplicable.
- shellcheck is clean across all sixteen files (was 13 findings), and the
  Exclusion pair no longer differs by blank lines.

### Also fixed, found while building the test suite and reading `ref_repos/`

- **A flag given last with no value hung every script.** `shift 2` with one
  positional left fails without shifting in bash 3.2, so the parser saw the
  same flag forever (`Enable_Policy.sh --csv x.csv --delay` never returned).
  Every value-taking flag now exits 3 with "`--delay` needs a value".
- **Bounded retry on 429 and transport failures.** `RetryableRequest` in the
  library wraps every policy GET and PUT: up to three attempts, 1 s then 2 s
  apart, honouring a numeric `Retry-After`. Never on 5xx, matching Jamf's own
  CLI. A PUT always carries a complete element, so repeating it is harmless.
- **User-group limitation read-back checks both places.** Jamf's `jamf-cli`
  writes policy user-group limitations to `scope/limit_to_users` (bare
  strings) and calls `limitations/user_groups` a server-side mirror. The
  writers still send `limitations/user_groups`; the pre-check and read-back
  for `--user-group <name>` now count a group in either place, so a mirror
  that has not caught up is no longer reported as a failed write.
- **Token failures say which of three things is wrong**: no HTTP response
  (URL, DNS, TLS), credentials rejected (400/401), or a 200 with no token
  (API client disabled or without a role). A missing `expires_in` warns and
  assumes five minutes instead of silently doing so.
- **HTTP statuses carry a hint** in FAILED lines: 000, 401, 403, 404, 409
  (the Classic API's "required field missing", inside an HTML page), 429,
  502, 503, 504.
- Usage texts: exit 1 now also lists the run-could-not-start causes, 130 is
  documented, and the three trigger scripts mention the `recurring-check-in`
  spelling the library accepts.
- Report: `set -u`, and the deep-link assignment no longer forks an `echo`.
- `ref_repos/` (third-party clones, one of which carries its own
  `.claude/settings.json` with hooks) is gitignored, like `vendor/` at the
  repo root. Never open it as a project root.

### Verified against production code in `ref_repos/`, no change needed

Jamf's `jamf-cli` (last commit 2026-09-11) confirms, with wire checks: a
Classic PUT is a partial update at the leaf level but replaces a supplied list
container in full; 201 says nothing (an unknown element is silently dropped);
read-back is the proof; `computer_groups` under `limitations` is silently
discarded; a policy with no targets never runs. Nothing anywhere settles
whether `general/trigger` is recomputed. Hard rule 1's wording was corrected:
the whole-`<general>` PUT is for a complete restore point, not because a
fragment would drop the name.

### Added

- **The report is CSV now, not TSV.** Every field double-quoted (RFC 4180),
  quotes doubled, CRLF rows, so names with commas, semicolons or quotes
  survive Excel and the round trip back into a writer's `--csv`. Default
  file name ends in `.csv`; `.gitignore` covers `*.csv` and `*.tsv` output
  and un-ignores `tests/fixtures/`.
- `tests/lib-harness.sh` — 127 checks of the library against fixtures.
- `tests/e2e.sh` and `tests/mock/mock_jamf.py` — every script, dry run then
  apply, against a local mock of the Jamf Pro and Classic API surface these
  scripts use; 117 checks including the 404, non-XML, signal, bad-secret and
  write-once-backup paths. Both suites run under a stock PATH.
- Comment coverage: every shared block in the fourteen writers and every
  non-obvious pipeline now says what it does and why.

### Verified against Jamf docs, no change needed

- `GET`/`PUT /JSSResource/policies/id/{id}`, `POST /api/v1/oauth/token`,
  `POST /api/v1/auth/invalidate-token`, `GET /api/v1/auth`: all current.
- Every policy element written exists at the documented nesting. The schema
  settles two standing-state items: exclusion users are `<user><name>`, and
  user groups in limitations and exclusions carry both `<id>` and `<name>`.
- Minimum API role: Read Policies, Update Policies, Read Categories.

### Known, not changed

- `CheckAndRenewAPIToken` probes `/api/v1/auth` before every request, which
  roughly doubles the request count of an apply run. Correct, just slow; a
  retry-on-401 design would halve it. Left for a deliberate change.
- Each writer parses the same policy XML many times per policy. CPU only.
- The per-policy skeleton is duplicated across the fourteen writers by
  design (hard rule 7). Every shared fix in this entry was applied to all
  fourteen with a literal block replace and verified by count.

---

## 2026-09-12 — trigger scripts and Self Service visibility

Five scripts: `Add_Policy_Trigger.sh`, `Remove_Policy_Trigger.sh`,
`Rename_Policy_Trigger.sh`, `Set_Policy_Triggers.sh`,
`Set_Policy_Self_Service.sh`. Fifteen in the directory now.

### Why triggers needed four scripts, not three

"Add, remove or modify a trigger" does not map onto the data. A policy's
triggers are six booleans plus one string:

| | Add | Remove | Modify |
|---|---|---|---|
| Six booleans | set true | set false | **nothing to modify** — on or off is the whole state |
| `trigger_other` | set the name | clear the name | rename it |

So "modify" is only meaningful for the custom event, which is
`Rename_Policy_Trigger.sh`. Separately, making a mixed fleet consistent is a
real job that add-one-at-a-time does badly, which is `Set_Policy_Triggers.sh`:
declarative, every trigger named is on and every one not named is off.

### The custom event is deliberately outside `--set`

A declarative `--set` that also cleared `trigger_other` would wipe a custom
event because someone forgot to mention it. `jamf policy -event <name>` matching
no policy is a **normal, successful** outcome for the jamf binary, not an error,
so every caller of that event would stop working silently — nothing in any log.
`Set_Policy_Triggers.sh` therefore requires `--custom-event` or
`--no-custom-event` to touch it, leaves it alone otherwise, and prints a note
naming any policy where it left one in place.

For the same reason `Remove_Policy_Trigger.sh --custom-event <name>` and
`Rename_Policy_Trigger.sh --from <name>` skip a policy whose event is something
else rather than clearing or repointing it. Only the named event moves.

### Refusing an automatic trigger on an enabled policy

Turning on Recurring Check-in for a policy that is *enabled* runs it on every Mac
in scope at the next check-in. Same hazard as `Enable_Policy.sh`, same treatment:
refused unless `--allow-auto-trigger`. A *disabled* policy is never refused,
which gives a safe ordering for a risky change — disable, set triggers, review,
enable. `Remove_Policy_Trigger.sh` rejects the flag outright.

`Set_Policy_Triggers.sh` only counts a trigger it would newly arm. Leaving one
already on does not trip the refusal, or the guard would fire on runs that
change nothing.

### `<general><trigger>` is read, never written

The legacy summary field, `EVENT` or `USER_INITIATED`. The docs describe its
relationship to the booleans loosely and Jamf maintains it itself, so writing it
would be guessing. Left alone; reported when it moves during a write, so the
first real run settles whether Jamf Pro recomputes it. Added to standing state
in CLAUDE.md.

### Set_Policy_Self_Service.sh is one script, not a pair

`--show` and `--hide` are the same write with a different value. A pair would be
two files differing in one character. The scope scripts are pairs because add
and remove are genuinely different XML operations against a list; this is a
scalar.

It is also the one script that **rejects** `--include-non-self-service`. Every
other script here skips policies that are not in Self Service; this one sets
that flag, so skipping on it would make `--show` a no-op on exactly the policies
it exists to act on.

A policy with no `<self_service>` element fails rather than getting one
synthesised. Under the full-enclosing-element rule a synthesised element is PUT
as the complete truth for that element, so it would land with no display name
and no icon.

Hiding is not disabling — a hidden policy keeps its triggers and still runs.
Said in the script header, the usage text, the run header and the README,
because it is the thing most likely to be assumed.

### Verified

Trigger element names and `use_for_self_service` checked against the Classic API
policy schema on 2026-09-12.

Offline, against a fixture carrying both a `<general><category>` and a
`<self_service><self_service_categories><category>`:

- one boolean on, siblings untouched; `trigger_other` set from a self-closing
  `<trigger_other/>`; rename over a populated one
- all six booleans chained through `ReplaceElementInSection` in one pass —
  exactly one of each element afterwards, `<general>` child count 21 before and
  21 after, name and category intact
- the `<self_service>` slice does not stop early at `<self_service_categories>`;
  display name, category id, `display_in` and `feature_in` all survive a hide;
  hide-then-show is **byte-identical** to the original element
- payloads carry only their own enclosing element, never `<scope>` or `<general>`
- twenty argument gates across the five scripts, and all fourteen writer tokens
  distinct

`shellcheck -x` clean on all five. Nothing has run against live Jamf Pro.

---

## 2026-09-12 — Enable_Policy.sh / Disable_Policy.sh 1.0.0

Ninth and tenth scripts. Flip `general/enabled` for every policy in a CSV. A
disabled policy keeps its scope, category, triggers and Self Service entry and
does none of it; the pair undoes itself.

### The library helper was wrong for leaf elements

`ReplaceElementInSection` was written for `<category>`, which `xmllint --format`
renders as a block:

```xml
<category>
  <id>7</id>
</category>
```

`<enabled>` is a leaf — `<enabled>true</enabled>`, one line. None of the
function's patterns matched that, so the element looked **absent** and the
"absent" branch appended a second copy before `</general>`. Result, confirmed
against a fixture before a line of the new scripts was written:

```xml
<enabled>true</enabled>     <- original, first
...
<enabled>false</enabled>    <- appended
```

Well-formed XML, accepted by `xmllint`, and Jamf takes one of them. The PUT
would have answered `201` and the read-back would have reported the value that
was never changed — a silent no-op wearing a success.

Fixed by adding a one-line-leaf branch to the function, ahead of the existing
block and self-closing branches. The new branch fires only on a pattern the old
function ignored, so `Set_Policy_Category.sh` is unaffected; re-verified against
the category fixtures anyway, plus the scope suites, since the file is shared.

Both new scripts also count `<enabled>` in the edited `<general>` and refuse to
send a payload that does not carry exactly one. Belt and braces, because this
class of defect produces a success message rather than an error.

### Enabling is not the harmless direction

Disabling can only stop things. Enabling a policy with an automatic trigger —
Recurring Check-in, Startup, Login, Logout, Network State Change, Enrollment
Complete, or a custom event — starts it executing on every Mac in scope at the
next trigger, with nobody opening Self Service. That is the same shape as the
empty-target case, so it gets the same treatment: refused by default, overridden
by `--allow-auto-trigger`.

`Disable_Policy.sh` **rejects** that flag rather than accepting it as a no-op,
matching how each writer already refuses the flags belonging to another pair.
A flag that is silently inert is worse than one that errors.

New library helpers: `GetPolicyEnabled`, `GetPolicyTriggers` (a one-line summary
of everything that can make a policy run) and `PolicyHasAutomaticTrigger`.
`GetPolicyTriggers` is one `awk` pass rather than an `xmllint` call per trigger,
and tracks sections for the usual reason — `<self_service_categories>` is nested
inside `<self_service>` and must not be mistaken for it.

### The token hashes the CSV

Every other writer puts its group or user into the confirmation token, which
binds the token to an intent. These two take no such argument; the CSV is the
whole instruction. So the token carries `md5` of the policy ID list truncated to
eight characters: `ENABLE-3-4a61320c`. A dry-run token from one CSV will not
apply a different CSV with the same row count.

### Verified

`<general><enabled>` and the exact trigger element names checked against the
Classic API policy schema (`PUT /policies/id/{id}`) on 2026-09-12, not assumed.

Offline: enable, disable, self-closing `<enabled/>`, the element absent
entirely; `<general>` child count 21 before and 21 after, with name, frequency,
category, site and trigger intact; payload carries `<general>` only, never
`<scope>` or `<self_service>`; both argument gates and the confirm-token gate;
token digest changing with CSV content and not with row count; all nine writer
prefixes distinct. `shellcheck -x` clean on both, with no new findings anywhere
in the set.

Nothing has run against live Jamf Pro.

---

## 2026-09-12 — Set_Policy_Category.sh 1.0.0

Batch-refiles the policies in a CSV under a different category. Eighth script;
the first that is not a scope change.

### Which "category"

A policy carries two unrelated fields that share an element name:

| Field | What it is |
|---|---|
| `general/category` | What the policy is filed under in the admin UI — one value |
| `self_service/self_service_categories` | Where the item appears in Self Service — a list, `display_in` and `feature_in` per entry |

"Which category a policy is assigned to" is the first. The report script already
has separate columns for both, and a policy filed under `Apps & Utilities` can
display under `Productivity` in Self Service. Changing the Self Service display
categories is a list operation — an add/remove pair like the scope scripts — and
is not built.

### A replace, not an append

Every previous writer adds or removes an entry in a list. A policy has exactly
one category, so this one swaps a value and discards the old. That needed a new
library primitive, `ReplaceElementInSection`, which handles a populated block, a
self-closing `<category/>`, and the element being absent entirely. It is
section-bounded like the scope functions, and for the same class of reason:
`<category>` appears under `<general>` *and* under `<self_service_categories>`,
and reaching the wrong one would rewrite a Self Service display category while
appearing to file the policy.

`<general>` is sent complete, byte-identical except for the category — a bare
`<general><category>` payload could drop the policy's name, trigger and every
other general setting, exactly as a bare scope fragment drops exclusions.

### The category is checked once, before anything is touched

`PreflightCategory` resolves `/JSSResource/categories/id/<n>` or `/name/<name>`
and aborts the whole run on anything but a 200. One API call against a typo that
would otherwise refile part of the fleet under a category that does not exist.
This adds **Read Categories** to the API role requirements.

`--no-category` skips the preflight and writes ID `-1`, which is how Jamf Pro
represents an unassigned category. That representation is unverified; read-back
covers it.

### Ampersands are escaped, not banned

Every earlier script rejects characters that cannot survive interpolation. That
would have been wrong here: Jamf category names routinely contain `&`
("Apps & Utilities"), so `&` is allowed and XML-escaped for the payload, with
`&` substituted **first** rather than last — the reverse of the decode order —
or the ampersands introduced by the `<` and `>` substitutions would be escaped
twice. Quotes and angle brackets are still rejected.

Verification compares decoded strings from `GetPolicyCategory` rather than
building an XPath predicate around the name, which sidesteps XPath quoting
entirely. `GetPolicyCategory` decodes entities so a change reads as
`Apps & Utilities -> Productivity` in the log rather than showing `&amp;`.

### Reporting

The dry run reports a transition, not just a destination, which is what makes a
bulk run reviewable before it happens:

```
WOULD SET 412 (Install Chrome): Apps & Utilities -> Productivity
```

### Notes

- Verified with `bash -n` and `shellcheck` across all nine files. Offline tests
  under `/bin/bash` 3.2.57: a populated category replaced; a self-closing
  `<category/>`; the element absent entirely; siblings (`name`, `trigger`)
  surviving all three; exactly one `<category>` in the result each time; the
  section bound holding even when the *whole* policy rather than just
  `<general>` is passed in, with the Self Service category and its `display_in`
  flag untouched; and entity decoding. The scope suites were re-run unchanged.
- Argument gates exercised: zero selectors, two selectors, a non-numeric ID, a
  quote in a name, and an ampersand in a name being accepted rather than
  rejected. All seven write scripts produce distinct confirmation tokens.
- README's introduction and prerequisites were stale from the three-script era
  and now describe all eight scripts and the Read Categories privilege.
- Still not run against live Jamf Pro.

---

## 2026-09-12 — target scripts

`Add_Policy_Scope_Target.sh` and `Remove_Policy_Scope_Target.sh`. Third and
final pair: the set now covers all three parts of a policy's scope.

| Pair | Section | Criteria |
|---|---|---|
| Target | direct children of `<scope>` | computer group ID, computer ID |
| Limitation | `<limitations>` | username, user group name or ID |
| Exclusion | `<exclusions>` | computer group ID, username |

### Users are not targets

Verified before building, against the Classic API policy schema and published
scope XML: a policy's targets are `computers`, `computer_groups`, `buildings`
and `departments`, plus the `all_computers` flag. `<users>` exists only under
`<limitations>` and `<exclusions>`. Jamf Pro scopes a policy to machines and
then narrows by person. Both target scripts refuse `--username`,
`--user-group` and `--user-group-id` with a pointer to the limitation pair.

This is the second time the "same criteria as the other scripts" request did
not survive contact with the scope model — the first was computer groups as
limitations. The refusals exist because the flag vocabulary is now shared
across six scripts and reaching for the wrong one is easy.

### Targets have no wrapper element

`<computer_groups>` and `<computers>` appear twice in a scope: once as targets
directly under `<scope>`, and once inside `<exclusions>`. Passing `scope` as
the section to the existing library functions would have matched both and
appended the new target to the exclusions list too.

The library now takes `targets` as a section value and bounds that region to
everything between `<scope>` and whichever of `<limitations>` or `<exclusions>`
comes first. `CountScopeEntry` drops the section segment from its XPath for the
same reason. The insertion also gained an `inserted` guard on the container
rules, so a second matching container later in the document cannot produce a
duplicate.

### Removing the last target is refused by default

The one change in this set that fails **quietly**. A policy with no targets
still exists, still looks configured, and simply stops reaching any Mac —
nothing errors and nothing looks wrong. `Remove_Policy_Scope_Target.sh` counts
what the removal would leave (`CountScopeTargets`: computers, computer groups,
buildings, departments) and refuses at zero unless `--allow-empty-scope` is
passed. A policy set to All Computers is exempt, since it keeps reaching every
Mac regardless. Refusals count under `Skipped/refused:` and do not set a
failure exit code — a refusal is the script working.

The add script has the mirror note: on a policy already scoped to All
Computers it logs that the new target changes nothing in practice.

### Notes

- Verified with `bash -n` and `shellcheck` across all eight files. `shellcheck`
  earned its place here: it caught two unreachable lines left behind when the
  remove script was derived from the add script, which `bash -n` accepted.
- Offline tests under `/bin/bash` 3.2.57, against a scope carrying the same
  container names at target level and inside exclusions: adding a group target
  leaves exclusions untouched; adding a computer to a populated `<computers>`;
  adding into an empty `<buildings/>`; counts distinguishing target from
  exclusion for the same ID; removing a target group while an exclusion group
  survives; removing a group that exists *only* as an exclusion correctly
  finding nothing in targets; and an emptied target list being detected. The
  limitation and exclusion suites were re-run unchanged.
- Every argument gate exercised, and all six write scripts confirmed to produce
  distinct confirmation tokens.
- Still not run against live Jamf Pro.

---

## 2026-09-12 — limitation scripts, and the library grew scope surgery

`Add_Policy_Scope_Limitation.sh` and `Remove_Policy_Scope_Limitation.sh`, plus
the refactor that made adding them cheap.

### Computer groups are not limitations

The request was for the limitation equivalent of the exclusion pair, keyed on
"group ID or username". Jamf Pro does not allow that: a policy's scope is
limited by **user, user group, network segment and iBeacon**. A computer group
can be a target or an exclusion, never a limitation. Both new scripts refuse
`--group-id` with a message naming the exclusion scripts instead, because
reaching for it out of habit is the obvious mistake once four scripts share a
flag vocabulary.

The three criteria that are valid here:

| Flag | Writes into | Matches on |
|---|---|---|
| `--username` | `limitations/users/user` | `name` |
| `--user-group` | `limitations/user_groups/user_group` | `name` |
| `--user-group-id` | `limitations/user_groups/user_group` | `id` |

`--user-group` and `--user-group-id` are refused together: they address one
entry by two keys, and accepting both would add the group twice.

### The unsettled part, and why it is safe to ship anyway

This estate uses Entra through a Cloud Identity Provider, not LDAP, and there
is no read-only Jamf access from here (see the repo CLAUDE.md constraint), so
whether a user group in a policy's scope carries an ID, a name or both is
unconfirmed. `--user-group` by name is the default assumption.

Shipping on an assumption is acceptable *here specifically* because the
read-back check already in the design turns a wrong guess into a reported
failure with a restore command rather than a false success. The same property
covered the unverified `<users>` element shape in the exclusion scripts. The
README carries the one curl command that settles it.

### Library: scope surgery generalised

Four write scripts would have meant four copies of the insertion and removal
awk, so those moved into the library with the scope *section* as a parameter:

- `CountScopeEntry   section container entry match_element value`
- `InsertScopeEntry  scope section container new_node`
- `RemoveScopeEntry  scope section container entry match_element value`

`CountExistingExclusion` is gone, replaced by `CountScopeEntry`; both exclusion
scripts were updated to call the library versions and each lost around 80
lines.

The section parameter is not decoration. `<users>` and `<user_groups>` exist
under **both** `<limitations>` and `<exclusions>`, and the same person can
legitimately be a limitation and an exclusion on one policy. Touching the wrong
section is the main way these scripts could quietly corrupt a policy, and it is
now one argument rather than a hardcoded guard repeated four times.

### Regex metacharacters in group names

`RemoveScopeEntry` interpolates the match value into an awk regex. Entra group
names routinely contain a dot, which would match any character — a removal of
`Corp.Marketing` could have taken out `CorpXMarketing`. Metacharacters are now
escaped before the match. The test set covers exactly that pair.

Usernames allow letters, digits and `. _ - @`; group names also allow spaces.
The set stays narrow because the value reaches an XPath predicate, an awk regex
and XML, and no quoting scheme survives a value containing a quote character.

### Tokens

`ADD-LIMIT-…` and `REMOVE-LIMIT-…`, distinct from the exclusion scripts'
`APPLY-…` and `REMOVE-…`, so a token cannot be pasted from one pair into the
other. Spaces in a group name become underscores so the token is one shell
word. Verified: all four scripts produce different tokens for the same CSV, and
a limitation script rejects an exclusion token.

### Notes

- Verified with `bash -n` and `shellcheck` across all five files. Offline tests
  under `/bin/bash` 3.2.57: a user added to limitations leaves the same
  username in exclusions untouched; a user group added to an empty
  `<user_groups/>`; counts addressing the right section for a person present in
  both; removal from limitations only; removal of an absent entry returning
  non-zero; the `Corp.Marketing` versus `CorpXMarketing` case; and an
  exclusions regression proving the older path still adds and removes computer
  groups with targets intact.
- Every argument gate was exercised: `--group-id` refusal, both group keys at
  once, no criteria, a quote in a group name, and token mismatch.
- Still not run against live Jamf Pro.

---

## 2026-09-12 — extracted scripts/lib/jamf-api-common.sh

The duplication noted in the entry below was removed the same day rather than
left to the "if a fourth script appears" threshold. Three copies of the OAuth
block was already one too many: a fix to token renewal would have had to be
made three times, and the copies had already started to drift — the report
script's credential prompts used `read` without `-r` while the two write
scripts used `read -r`.

### What moved

| Moved to the library | Why |
|---|---|
| `curl_timeouts`, `token_renewal_buffer`, token state | Identical in all three |
| `GetJamfProAPIToken`, `APITokenValidCheck`, `CheckAndRenewAPIToken`, `InvalidateAPIToken` | Identical in all three |
| `ResolveJamfProCredentials` | New name for the credential block that was inline in all three |
| `ReadPolicyIDsFromCSV` | Identical in both write scripts |
| `CountExistingExclusion` | Identical in both write scripts |

### What deliberately stayed

Argument parsing, `usage`, `log_line`, the scope surgery functions and the
per-policy loop. They read as shared but they are not: the add and remove
scripts differ in exactly those places, and hoisting them would have meant
parameterising the differences into the library — more coupling, not less.

### Mechanics

Each script resolves the library relative to its own path and refuses to start
without it:

```bash
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
JAMF_API_COMMON="${SCRIPT_DIR}/lib/jamf-api-common.sh"
```

That means `lib/` has to travel with a script that is copied elsewhere. The
error message says so. `$0` does not resolve symlinks, so a symlinked script
would look for `lib/` next to the symlink; none of these are symlinked today.

Sourcing the library defines functions and defaults and does nothing else — no
network call, no credential read, until something is called.

### Effect

1762 lines across three scripts became 1529 across three scripts and one
library. The report script alone went from 440 lines to 295.

### Notes

- No behaviour change intended. Verified after the refactor: both confirm-token
  gates still produce the right tokens (`APPLY-3-42-none`, `REMOVE-3-42-none`),
  the CSV and username validation gates still fire, every library function
  resolves from every script, the missing-library path exits with the intended
  message, and the report's header/format/argument counts are still 13/13/13.
  The report's Self Service category extraction was re-run against the fixture.
- One incidental improvement: the report script's credential prompts now use
  `read -r`, which removed its two `SC2162` shellcheck findings.
- Still not run against live Jamf Pro.

---

## 2026-09-12 — Remove_Policy_Scope_Exclusion.sh 1.0.0

Partner to the add script. Removes a scope exclusion — a computer group by ID,
a user by username, or both — from every policy listed in a CSV. Same
arguments, same credential sources, same dry-run-plus-token safety model, same
full-scope PUT, same read-back verification.

### Four behavioural differences

- A policy that does not carry the exclusion is a success, not a failure. It is
  counted under `Not excluded:` and left alone, so a CSV can be re-run safely.
- Read-back requires the exclusion to be **absent**; the add script requires it
  to be present. A PUT that returns 201 and leaves the entry in place is
  reported as a failure with the restore command.
- The confirmation token is `REMOVE-<count>-<group>-<user>`, so an add token
  cannot be pasted into a removal.
- Removing the last entry leaves an empty container (`<computer_groups/>`),
  which is what Jamf Pro itself writes for an empty exclusion list.

### Removal buffers whole entries

`RemoveExclusionFromScope` buffers each `<computer_group>` or `<user>` block and
discards it only when the complete block matches. This is the part that had to
be got right: once `xmllint --format` has run, the `<id>` and the element that
owns it are on separate lines, so a line-at-a-time filter could delete one
entry's `<id>` and leave a malformed block behind. Buffering also makes the
match exact — group `7` is never confused with group `77`, which an unanchored
substring match would get wrong.

The `<exclusions>` guard matters as much as it does in the add script, and for a
sharper reason: `<users>` appears under `<limitations>` as well, and the same
person can legitimately be both a limitation and an exclusion on one policy.
Removing one must not disturb the other. That case is in the test set.

### Notes

- Verified with `bash -n` and `shellcheck` (one pre-existing SC2181 style note,
  inherited from the add script's structure). Removal was tested offline under
  `/bin/bash` 3.2.57 against: two exclusions where one is removed; an absent id
  (returns non-zero, reported as nothing to do); the `7` versus `77` prefix
  collision; removing the only exclusion; and the same username present under
  both `<limitations>` and `<exclusions>`. Targets survived every case.
- Not run against live Jamf Pro.

### Known duplication

The two write scripts share roughly 500 of their 660 lines — argument parsing,
credentials, token handling, the CSV reader, the per-policy GET/PUT/verify
loop. They were kept standalone so either can be handed to someone on its own,
and the shared parts are byte-identical so a `diff` shows only the real
differences. The auth block now exists in three files in this directory. If a
fourth script appears, extract `scripts/lib/jamf-api-common.sh` rather than
copying it again.

---

## 2026-09-12 — verified: Classic API is the only option for policies

No code change. Recording the answer so it does not get re-researched.

Both scripts read and write policies through the Classic API
(`/JSSResource/policies`). Checked against Jamf's live OpenAPI specs via the
Jamf documentation MCP, Jamf Pro 11.28.1.

**The modern Jamf Pro API has no policy endpoints.** Everything policy-shaped
in it is something else:

| Endpoint | What it is |
|---|---|
| `GET`/`PUT` `/v1/policy-properties` | Global policy settings, the server-wide object |
| `GET /v1/onboarding/eligible-policies` | Read-only list for onboarding configuration |
| `/v2/patch-policies/*` | Patch policies, a different object |

Per-policy `GET`/`POST`/`PUT`/`DELETE` and the whole `<scope>` element exist
only in the Classic spec.

**Classic `/policies` is not deprecated.** The deprecation register lists the
computer inventory endpoints (11.15.0, one-year window), the old `/auth*`
endpoints, `/inventory-preload`, `/settings/obj/policyProperties`,
`/v1/cloud-azure/defaults/mappings` and
`/v1/computer-inventory-collection-settings`. Policies are not on it, and the
computer-inventory notice is explicitly narrow — "the computers endpoints",
not the Classic API as a whole.

Two supporting details:

- The spec for `PUT /policies/id/{id}` documents exactly one success response,
  **201 Created**. `Add_Policy_Scope_Exclusion.sh` accepts 200 or 201.
- Classic is now published through the Platform API Gateway as its own spec,
  alongside Blueprints and Device Groups. Jamf is carrying it forward into the
  new gateway rather than sunsetting it.

What would change this: real policy endpoints in the modern API. The scope
object would then be JSON with addressable sub-resources, and the full-scope
PUT in `Add_Policy_Scope_Exclusion.sh` — which exists only because Classic
replaces the content of any element you send — would no longer be needed.
Nothing announced.

Sources: developer.jamf.com `/jamf-pro/docs/privileges-and-deprecations`,
`/jamf-pro/docs/deprecation-of-classic-api-computer-inventory-endpoints`,
`/jamf-pro/docs/getting-started-2`, and the Classic and Jamf Pro API OpenAPI
specs themselves.

---

## 2026-09-12 — Add_Policy_Scope_Exclusion.sh 1.0.0

New script. Adds a scope exclusion — a computer group by ID, a user by
username, or both — to every policy listed in a CSV. The report script finds
the policies; this one changes them.

### Safety

This is the repository's first script here that writes to production policies,
so it follows the destructive-script rule: dry-run by default, and a real run
needs `--apply` **and** `--confirm` with a token derived from the run itself
(`APPLY-<policy count>-<group>-<user>`). The token changes with the CSV, the
group or the username, so an apply command cannot be pasted from an old run
against a new list. The dry run prints the exact command.

Also, per policy: a full `policy-<id>-before.xml` backup before any write, a
skip if the exclusion is already present (re-running is safe), and a skip for
anything that is not a Self Service policy unless
`--include-non-self-service` is passed — a stray ID in a CSV should not
silently rescope a background policy.

### The PUT sends the complete scope

The one decision worth recording. Jamf Pro's Classic API replaces the content
of any element a request supplies, so a PUT carrying a bare
`<exclusions><computer_groups>` with a single group in it can drop every other
exclusion already on the policy. Rather than rely on merge granularity, the
script GETs the policy, inserts the new node into the formatted `<scope>` with
awk, and PUTs the whole scope back byte-identical except for the addition.
Targets, limitations and every other exclusion type survive because they are
sent back exactly as they arrived.

The insertion handles five shapes, all tested: a populated container, an empty
`<computer_groups/>`, a container absent from an otherwise populated
`<exclusions>`, a self-closing `<exclusions/>`, and no `<exclusions>` element
at all. The `<exclusions>` guard matters — `<users>` appears under both
`<limitations>` and `<exclusions>`, and a user exclusion must not land in the
limitations list.

### Verification is read-back, not status code

A Classic API PUT answers 201 whether or not the element landed where intended,
so the script re-GETs the policy and counts the exclusion before reporting
success. A PUT that returns 201 but fails read-back is reported as a failure
with the restore command for that policy.

### Input handling

- CSV: policy ID in the first column, comma or tab separated. Header rows,
  blank lines and `#` comments are skipped by ignoring any first column that is
  not all digits, which also means the report script's TSV can be fed in
  directly.
- `--group-id` must be digits. A non-numeric ID would be sent as-is and create
  a scope entry matching nothing.
- `--username` is restricted to letters, digits and `. _ - @`. The name is
  interpolated into both an XPath predicate and XML; no quoting scheme survives
  a username containing a quote character, and Jamf usernames do not need one.

### Notes

- Smart and static computer groups share one ID space and one scope element, so
  `--group-id` covers both. Nothing in the script needs to know which it is.
- Classic API is not optional here: the Jamf Pro API has no policy endpoints.
  Authentication is still the modern API (OAuth client credentials).
- Requires **Update Policies** on the API role in addition to **Read Policies**.
- Verified with `bash -n` and `shellcheck`. The insertion, the CSV parser and
  every argument and confirm-token gate were tested offline under `/bin/bash`
  3.2.57. **No part of this has run against live Jamf Pro** — in particular the
  `<users>` element name for user exclusions is taken from the Classic API
  policy schema and has not been confirmed against a real policy. The
  read-back check is what will catch it if it is wrong: the run will report a
  failure rather than a false success.

### Repository

- Added `.gitignore` for `exclusion-backups-*/` and `*.tsv`. Backups and
  reports name internal computer groups, buildings and users.

---

## 2026-09-12 — later

### Added

- **Three Self Service category columns: SS Categories (Display), SS Categories
  (Featured), Featured on Main Page.** The report already carried the policy's
  own `Category`; it said nothing about where the item actually surfaces in
  Self Service. Those are unrelated fields — a policy in `Apps & Utilities`
  can display under `Productivity`.

- **`ExtractSelfServiceCategories`** — walks `<self_service_categories>` one
  `<category>` at a time with an indexed XPath predicate and returns the names
  whose named flag is true. `ExtractNameList` could not be reused directly:
  each category carries its own `display_in` and `feature_in`, and a flat match
  of every `<name>` would lose which name went with which flag. It does reuse
  `ExtractNameList` for the per-index name, so entity decoding stays in one
  place. The node count comes from XPath `count()`, validated as digits before
  it reaches the loop condition.

- `feature_on_main_page` is read separately. It is a policy-level flag, not a
  category, and is unrelated to a category's `feature_in`. Absent elements
  report `false`; an item in no category reports `None`, so a blank cell still
  means a parse failure rather than an empty setting.

### Notes

- The report is now 13 columns. Header, format string and argument list were
  checked against each other — 13/13/13 — because they are three separate
  literals that drift silently: a short argument list does not error, it just
  writes empty trailing fields.
- Verified with `bash -n` and `shellcheck`, no new findings. Extraction tested
  offline under `/bin/bash` 3.2.57 against a policy with three categories
  (mixed flags, an encoded `R&amp;D`) and against a policy with no
  `<self_service_categories>` element at all.
- Still not run against the live Jamf Pro instance.

---

## 2026-09-12

### Added

- **Three scope columns: Scope Targets, Scope Limitations, Scope Exclusions.**
  This is what the workstream exists for. The policy XML already contained the
  full `<scope>` element on every request; the script was throwing it away and
  reporting only name, category and Self Service display name. Extracting it
  costs no extra API calls.

  Types collected: computer groups, computers, buildings and departments as
  targets; users, user groups, `limit_to_users` LDAP groups, network segments
  and iBeacons as limitations; all eight exclusion types. Empty target scope is
  reported as `No targets`, empty limitations and exclusions as `None`, so a
  blank cell always means a parse problem rather than an empty scope.

- **`ExtractNameList`** — joins every `<name>` matched by an XPath into one
  string. `xmllint --xpath` concatenates matched text nodes with no delimiter
  and separates matched *elements* with a newline, so neither raw form is
  usable. The function matches the elements, rewrites the tags into `; `
  separators, collapses the newlines, and decodes XML entities. `&amp;` is
  decoded last, otherwise an encoded `&amp;lt;` decodes twice and produces `<`.

- **`AppendScopeItem`** — labels a non-empty list and joins it to the running
  column with ` | `, skipping empties. Without it, a policy scoped only to
  buildings would have produced `Groups:  | Computers:  | Buildings: 123 Main St`.

### Changed

- **Authentication is now OAuth client credentials, not username and password.**
  `POST /api/v1/oauth/token` with `grant_type=client_credentials`, parsed with
  `plutil -extract access_token raw -`. The script now wants an API Client ID
  and secret; `jamfpro_user` and `jamfpro_password` are gone, as are the
  `python -c 'import json'` fallbacks for macOS 11 and earlier.

  This also removes the credential from every Classic API call. Previously, when
  `NoBearerToken` was set, each of the several-hundred per-policy requests sent
  `curl -su user:password`.

- **Token renewal re-requests rather than keep-alives.** `/api/v1/auth/keep-alive`
  extends tokens issued by `/api/v1/auth/token`; it is not the renewal path for
  a client-credentials token. The script now records `expires_in` at issue,
  renews 90 seconds before expiry, and still falls back to a fresh token if
  `/api/v1/auth` stops returning 200. `expires_in` is validated as digits before
  it reaches arithmetic — a malformed response would otherwise abort the run
  inside `$(( ))`.

- **The token is invalidated on exit.** `POST /api/v1/auth/invalidate-token`,
  wired into the existing trap alongside the spinner kill, so an interrupted run
  does not leave a live token behind.

- **Every `curl` call carries `--connect-timeout 15 --max-time 30`.** Repo-wide
  constraint; an unbounded request here means a hung report with a spinner still
  turning.

- **Credentials can come from the environment** (`JAMF_PRO_URL`,
  `JAMF_PRO_CLIENT_ID`, `JAMF_PRO_CLIENT_SECRET`) as well as from the script
  header and `com.github.jamfpro-info.plist`. The secret never has to be written
  to disk.

### Fixed

- **Policy names containing `%` corrupted the report.** The row was written as
  `printf "$JamfProID\t$PolicyName\t..."` — the data was the format string. A
  policy named `R&D 100% Pilot` consumed the following field as a conversion.
  Now `printf "%s\t%s..."` with the values as arguments. Scope names made this
  worse, not better: group names are far likelier to contain a percent sign than
  policy names.

- **The write success check was always true.** `if [[ $? -eq 0 ]]` ran after a
  variable assignment, which succeeds unconditionally, so the
  `ERROR! Failed to read policy record` branch was unreachable. It now checks
  that the policy ID was actually parsed out of the response, and reports the
  requested ID rather than the empty parsed one.

### Removed

- **The `NoBearerToken` code path.** It existed for Jamf Pro 10.34.2 and earlier,
  which could not use bearer tokens against the Classic API. That is nine years
  of releases ago and the path only worked with Basic auth, which no longer
  exists in this script.

### Notes

- Script remains bash 3.2 clean (`/bin/bash` on macOS is 3.2.57 through Tahoe 26)
  and calls no `/usr/bin/python3`.
- Verified with `bash -n` and `shellcheck -x -s bash`. Shellcheck's remaining
  output is pre-existing informational findings inherited from the upstream
  script — unquoted `$HOME` in `defaults read`, `read` without `-r`, `local`
  combined with command substitution, and the intentional early expansion of
  `$SPIN_PID` inside `trap`.
- Scope extraction was tested offline against a constructed policy XML covering
  multi-entry lists, encoded entities (`R&amp;D`), a percent sign in a group
  name, and empty scope elements. It has not yet been run against the live Jamf
  Pro instance.

---

## Before 2026-09-12

The script came in as a community Jamf Pro reporting script, in the style and
credential convention (`com.github.jamfpro-info.plist`, `GetJamfProAPIToken` /
`APITokenValidCheck` / `CheckAndRenewAPIToken`) of Rich Trouton's Jamf Pro
scripts. It authenticated with a Jamf Pro username and password, reported ID,
enabled state, name, category, Self Service display name and URL, and did not
look at policy scope.
