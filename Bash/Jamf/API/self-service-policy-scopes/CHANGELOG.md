# Changelog

All notable changes to the scripts, library and tests in this directory.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Entries are dated, newest first; the per-script SCRIPT_VERSION constants are
not bumped for review fixes.

---

## 2026-09-12 — unified test runner and expanded mock coverage

### Added

- **`tests/run-all.sh`** runs all four layers in order and returns one exit code.
  When `JAMF_PRO_*` variables are missing, layer 4 is clearly reported as
  SKIPPED. Earlier defects passed layers 1–3 before live validation found them,
  so an offline pass validates only the local model.
- **`tests/install-hooks.sh`** installs a `pre-push` hook that runs layers 1–3
  and blocks failed pushes. It warns when `scripts/` is newer than the last
  successful live run. The warning does not block because live validation
  requires a reachable server and credentials. A successful `every-flag.sh`
  run now stamps `tests/live/.last-success`; the machine-specific file is
  gitignored.
- **Four mock parity fixes.** The mock now returns a category body for
  `Set_Policy_Category.sh` preflight, can return 429 on PUT as well as GET,
  models the `limit_to_users` union, and models a 409 with a partial apply. Two
  new `tests/e2e.sh` sections cover server-side resolution and PUT-side 429.
- **Fixture coverage.** `policy-101.xml` now populates `jss_users` in targets and
  exclusions, distinguishing Jamf Pro users from directory users.
  `policy-202.xml` now documents that its unrealistic shape is intentional.

### Fixed

- **Corrected the documented lint command.** `shellcheck -x` cannot follow
  `# shellcheck source=lib/jamf-api-common.sh` because the path is relative to
  the script. It therefore reported `SC1091` and many `SC2154` findings for
  library variables. Adding `--source-path=scripts` produces zero findings.
  Updated `CLAUDE.md`, `TESTING.md`, and `run-all.sh`.
- Corrected stale check counts in `README.md`, `CLAUDE.md`, and `TESTING.md`:
  the harness has 137 checks and the end-to-end suite has 135, rather than 136
  and 129.

---

## 2026-09-12 — all flags validated against live Jamf Pro; five defects fixed

`tests/live/every-flag.sh` runs 161 checks: all 29 flags across the 15 scripts,
plus every refusal path, against the homelab instance with an independent curl
oracle. The macOS run uses `env -i` and a stock PATH, validating Jamf behavior,
bash 3.2, and BSD compatibility. The earlier Debian run validated Jamf behavior
only: it required `plutil` and `md5` shims, and GNU `sed`/`awk` hid the portability
issues that the stock PATH check is meant to expose.

A self-hosted lldap directory service was added to the homelab instance first.
Without it, `limitations/user_groups` cannot hold entries and three of these
five defects cannot be reproduced.

### Fixed

- **A 409 can partially apply, but every writer treated it as a complete
  failure.** A policy contained a directory group that was later deleted. A
  PUT that resent the complete `<scope>` for an unrelated change returned 409,
  applied the change, and dropped the unresolvable entry. The writers returned
  before read-back on every non-2xx response, so they reported FAILED without
  reporting the dropped entry. A fleet-wide run could therefore strip stale
  directory groups while reporting only failures. A 409 now logs a WARNING
  with the backup path and continues to read-back. Other non-2xx responses
  still return early. The identical block was updated in all fourteen writers.

- **`Remove_Policy_Scope_Limitation.sh --user-group` never removed the group.**
  Jamf returned 201 and the script reported success, but the group remained.
  `limit_to_users/user_groups` is the source and `limitations/user_groups` a
  mirror Jamf regenerates from it; the stored set is their union, so an add
  works from either side but a removal only sticks when the entry is gone from
  both. The writer edited only the mirror. `RemoveLimitToUsersGroup` now strips
  the source entry too, gated on removal by name because the source stores no
  ids.

- **The logout trigger is retired and cannot be written.** A PUT carrying
  `<trigger_logout>true</trigger_logout>` is answered 201 and discarded while a
  `trigger_startup` in the same request lands; a GET never returns the element.
  The help text claimed it was "accepted because the API still carries it".
  `ResolveTriggerElement` no longer maps it, `TRIGGER_FLAG_NAMES` drops it, and
  `ExplainRetiredTrigger` prints the reason for the rejection.
  `Set_Policy_Triggers.sh` now owns five booleans instead of six.
  `DescribeTriggers` still recognises the element so archived backups still read.

- **`Set_Policy_Self_Service.sh --show --hide` silently took the last flag.**
  `Set_Policy_Category.sh` refuses `--category-id` with `--no-category`; this
  now counts selectors the same way.

- **`Set_Policy_Category.sh` left an empty backup directory and log after a
  mistyped category.** `PreflightCategory` ran after `mkdir`. It now runs first,
  matching the exclusion pair's `PreflightUserGroup` and early authentication.

### Added

- `tests/live/every-flag.sh`. Teardown finds fixtures by listing the instance.
  It cannot use a variable because `mkpolicy` runs inside `$( )`, and subshell
  assignments do not survive. Listing also removes fixtures left by a crashed
  earlier run.

- The mock now models Jamf's server-side resolution. It previously stored every
  PUT unchanged, so the writers' read-back failure branch was unreachable and
  the retired logout trigger passed 129/129 before and after removal. It now
  reproduces: a valid directory group stored and mirrored; an invalid one
  dropped with the rest of the request still applied and a 409 returned;
  `limitations/users` stored unvalidated; `exclusions/users` silently
  discarded; `jss_user_groups` name filled in server-side; `trigger_logout`
  stripped. `DIRECTORY_GROUPS` keeps `CorpXMarketing` resolvable because fixture
  101 uses it to prove that removing `Corp.Marketing` does not remove it. The
  unresolvable case uses a separate name so the tests stay independent.

### Changed

- Corrected an e2e assertion: a Jamf Pro user group ID cannot become a directory
  limitation. The assertion passed only because the mock stored every PUT
  unchanged.

- Updated `CLAUDE.md`, `README.md`, `TESTING.md`, and `LIVE-VALIDATION.md` where
  they contradicted observed behavior. The main correction: handling of an
  unresolvable scope entry depends on directory state and container. Groups are
  validated, users are not, and an unresolvable group returns 409 when a
  directory is configured.

### Still open

- Whether an **Entra** group arriving through a Cloud Identity Provider resolves
  by name. The homelab resolves through LDAP; same container, same code path,
  different directory.
- PI-005747, not observed on this instance.
- A real 429, never provoked.

---

## 2026-09-12 — scope container map wire-checked against live Jamf Pro 11.32.0

First validation against a real Jamf Pro server. The run was read-only except
for two temporary `ZZ-LIVETEST-probe*` policies, both deleted afterward.

### Added

- `CLAUDE.md`: the full ten-container scope map, matching each container to its
  UI menu label from `GET /JSSResource/policies/id/13`. Jamf returns every
  container even when empty.
- `CLAUDE.md`: the three "Add" menus recorded verbatim — Deployment Targets
  offers four kinds, Limitations four, Exclusions ten.

### Discovered

- **`jss_user_groups` and `user_groups` are different containers**, as are
  `jss_users` and `users`. The UI's "User Groups" is `jss_user_groups`, a Jamf
  Pro object addressed by `<id>`; "Directory Service User Groups" is
  `user_groups`, resolved against LDAP or a Cloud Identity Provider at scope
  time. The previous four-row table in `CLAUDE.md` collapsed both pairs into
  one row each and omitted the `jss_*` containers entirely.
- **Jamf silently discards some unresolvable scope entries.** A PUT carrying
  four exclusion entries answered success and stored three of them. An invented
  username in `exclusions/users`, an invented name in `exclusions/jss_users`,
  and a Jamf Pro user group id placed in `exclusions/user_groups` were all
  dropped without an error. As with `self_service_categories`, read-back rather
  than HTTP status determines whether a write succeeded.
- **`limitations/user_groups` is a no-op on a tenant with no directory
  service.** There is no directory in which to resolve the group, so the write
  is discarded. `Add_Policy_Scope_Limitation.sh --user-group` therefore cannot
  be positively validated on the homelab instance; its read-back will correctly
  report FAILED after a 201.
- **The exclusion pair could not exclude a user group.** It accepted only
  `--group-id` (a computer group) and `--username`. No reason for the omission
  was recorded, while `CLAUDE.md` listed user groups as valid exclusions. The
  pair now accepts `--user-group` and `--user-group-id`, writing
  `jss_user_groups`.

### Defects from missing `jss_*` containers

All three defects existed from the first commit because the scripts did not
model `jss_users` and `jss_user_groups` as deployment target and exclusion
containers.

1. **`CountScopeTargets` under-counts.** It sums `computers`,
   `computer_groups`, `buildings` and `departments` only. A policy scoped to a
   Jamf Pro user group has targets it does not see. Demonstrated against
   `tests/fixtures/policy-101.xml`, which now carries five targets:

   ```
   computers 1 · computer_groups 3 · jss_user_groups 1  -> real total 5
   CountScopeTargets reports: 4
   ```

   This caused a false refusal at `Remove_Policy_Scope_Target.sh:323`:
   removing the last computer group from a policy that also targets a Jamf Pro
   user group reported "would leave the policy with no targets at all" and
   skipped the change, even though the policy would still reach that user group.

2. **The report omits `jss_users` and `jss_user_groups` from "Scope Targets".**
   `Generate_Self_Service_Policy_Report.sh` lines 308-311 collect computers,
   computer groups, buildings and departments. A policy targeted at people
   rather than Macs reports a thinner scope than it has.

3. **The report omitted them from "Scope Exclusions"** (lines 336-341). After
   excluding a Jamf Pro user group from every Self Service policy, the report's
   verification column remained blank.

### Added

- `Add_` / `Remove_Policy_Scope_Exclusion.sh` now accept `--user-group <name>`
  and `--user-group-id <n>`, writing `scope/exclusions/jss_user_groups`. This
  supports reporting all Self Service policies and excluding one Jamf Pro user
  group from the resulting set. Non-Self-Service policies remain skipped unless
  `--include-non-self-service` is given.
- Both scripts now preflight the group, following `Set_Policy_Category.sh`: it is
  looked up by id or name before the backup directory is created, and a group
  the server does not know stops the run with exit 1. Without it Jamf would
  answer 201 and store nothing. `--user-group` is resolved to its id there,
  because `jss_user_groups` uses `<id>`. The name never enters XPath, XML, or an
  awk regex, so leading `*` and spaces are allowed.
- The confirmation token now includes the user-group value, so
  excluding a group and excluding a computer group against the same CSV cannot
  share a token. Spaces are folded to `_` as the limitation and trigger scripts
  already do: `APPLY-2-none-none-TESTING_-_Microsoft_OneDrive`.

### Fixed

- `CountScopeTargets` counts all six target containers. Was four; see the
  defect note above.
- `Generate_Self_Service_Policy_Report.sh` reports `jss_users` and
  `jss_user_groups` in both the "Scope Targets" and "Scope Exclusions" columns.
- Report column labels now follow the Jamf Pro UI: `jss_users`/`jss_user_groups`
  are "Users"/"User Groups"; directory `users`/`user_groups` are "Directory
  Users"/"Directory User Groups". Previously the directory containers used
  the labels for the other pair.

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
  deployment targets. The same user group ID now appears as a target, making
  the section-binding case testable. Both suites remain green at 127/127 and
  117/117; the fixture change exposes defect 1.

### Validated live — thirteen of the fifteen scripts

Run against Jamf Pro 11.32.0 on disposable `ZZ-LIVETEST-*` policies only; the
instance is back to its original 17 policies.

| Area | Result |
|---|---|
| Report | 17 policies read, 11 Self Service, 13-column RFC 4180 CSV |
| Exclusions, incl. the new `--user-group` | 18/18 |
| Targets, category, enable/disable, Self Service, bad secret | 27/30; three test-assertion defects corrected below |
| Triggers | 14/14 |

`general/trigger` is recomputed by Jamf Pro. A disabled policy with no
triggers read `USER_INITIATED`; after `--trigger startup` it read `EVENT`; after
removing that trigger it read `USER_INITIATED` again. The trigger scripts
correctly read and report this field without writing it. No code change was
needed.

Confirmed on live policies:

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

Three assertions failed in the first writers run because of test defects. One
XPath used `and`, which returns a boolean instead of a count. Two followed a dry
run that the enabled-policy trigger guard correctly refused, so no confirmation
token existed for the apply step.

### Verified for the coming preflight

`Add_Policy_Scope_Exclusion.sh` will refuse an unknown group before Jamf can
discard the write. These lookup endpoints were wire-tested on 2026-09-12:

| Request | Answer |
|---|---|
| `GET /JSSResource/usergroups/id/2` | 200 |
| `GET /JSSResource/usergroups/id/99999` | 404 |
| `GET /JSSResource/usergroups/name/TESTING%20-%20Microsoft%20OneDrive` | 200, `<id>` 2 |
| `GET /JSSResource/usergroups/name/NoSuchGroupHere` | 404 |

Spaces must be percent-encoded in the `name/` form, as documented for
`Set_Policy_Category.sh` and `categories/name/`. The lookup returns the group's
`<id>`, which addresses `jss_user_groups`; Jamf fills in `<name>` on read-back.

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

A multi-agent review covered all sixteen files, Jamf's current OpenAPI specs and
developer docs, a stock-Tahoe runtime test, and comments. Every endpoint and XML
element matched the specs, and none appears in the deprecation register. All
defects were in the scripts.

### Functional fixes

- **`Set_Policy_Triggers.sh` could not verify a Self Service policy.** Its
  `DescribeTriggers` re-added the "Self Service" prefix that `GetPolicyTriggers`
  already adds for `<self_service>`, so the full policy read "Self Service,
  Self Service, …" and never matched the edited `<general>` fragment. Every
  successful write was reported as FAILED with a restore command. The prefix is
  now normalized.
- **Remove scripts failed open on read-back.** `CountScopeEntry` prints 0 for
  an empty or non-XML body, and 0 is what a removal reads as success, so a
  timed-out or 401 verification GET reported UPDATED. Every GET now uses
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
  is a bare string. The extractor now reads the bare tag value.
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
  column. Added `GetPolicyName` and `DecodeXMLEntities` so policy names
  containing `&` render correctly in logs and reports.

### Usability fixes

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

### Additional fixes

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
- **Token failures distinguish three causes**: no HTTP response
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
- `ref_repos/` is gitignored like the root `vendor/` directory. It contains
  third-party clones, including one with its own `.claude/settings.json` hooks,
  and must not be opened as a project root.

### Verified against production code in `ref_repos/`, no change needed

Jamf's `jamf-cli` (last commit 2026-09-11) and wire checks confirm that a
Classic PUT partially updates leaf elements but fully replaces a supplied list
container. A 201 does not prove the element was accepted; unknown elements are
silently dropped, so read-back is required. Jamf also discards
`computer_groups` under `limitations`, and policies without targets never run.
No source settles whether Jamf recomputes `general/trigger`. Hard rule 1 now
states that the complete `<general>` PUT provides a full restore point; a
fragment would not drop the name.

### Added

- **The report now uses CSV instead of TSV.** It emits RFC 4180 CSV: every field
  is double-quoted, embedded quotes are doubled, and rows use CRLF. Names with
  commas, semicolons or quotes survive Excel and a round trip into a writer's
  `--csv`. The default filename ends in `.csv`; `.gitignore` covers `*.csv` and
  `*.tsv` output and un-ignores `tests/fixtures/`.
- `tests/lib-harness.sh` — 127 checks of the library against fixtures.
- `tests/e2e.sh` and `tests/mock/mock_jamf.py` — every script, dry run then
  apply, against a local mock of the Jamf Pro and Classic API surface these
  scripts use; 117 checks including the 404, non-XML, signal, bad-secret and
  write-once-backup paths. Both suites run under a stock PATH.
- Added comments for every shared block in the fourteen writers and every
  non-obvious pipeline.

### Verified against Jamf docs, no change needed

- `GET`/`PUT /JSSResource/policies/id/{id}`, `POST /api/v1/oauth/token`,
  `POST /api/v1/auth/invalidate-token`, `GET /api/v1/auth`: all current.
- Every policy element written exists at the documented nesting. The schema
  settles two standing-state items: exclusion users are `<user><name>`, and
  user groups in limitations and exclusions carry both `<id>` and `<name>`.
- Minimum API role: Read Policies, Update Policies, Read Categories.

### Known, not changed

- `CheckAndRenewAPIToken` probes `/api/v1/auth` before every request, roughly
  doubling the request count of an apply run. A retry-on-401 design would halve
  it. No change was made.
- Each writer parses the same policy XML many times per policy. CPU only.
- The per-policy skeleton remains duplicated across the fourteen writers under
  hard rule 7. Each shared fix was applied to all fourteen by literal block
  replacement and verified by count.

---

## 2026-09-12 — trigger scripts and Self Service visibility

Five scripts: `Add_Policy_Trigger.sh`, `Remove_Policy_Trigger.sh`,
`Rename_Policy_Trigger.sh`, `Set_Policy_Triggers.sh`,
`Set_Policy_Self_Service.sh`. Fifteen in the directory now.

### Trigger script split

A policy's triggers are six booleans and one string:

| | Add | Remove | Modify |
|---|---|---|---|
| Six booleans | set true | set false | not applicable (boolean state) |
| `trigger_other` | set the name | clear the name | rename it |

Only the custom event can be modified, so `Rename_Policy_Trigger.sh` handles
that case. `Set_Policy_Triggers.sh` normalizes a mixed fleet declaratively:
named triggers are enabled and unnamed triggers are disabled.

### Custom events remain outside `--set`

A declarative `--set` that cleared `trigger_other` could remove an omitted custom
event. `jamf policy -event <name>` returns success when no policy matches, so
callers would stop working without an error.
`Set_Policy_Triggers.sh` therefore requires `--custom-event` or
`--no-custom-event` to touch it, leaves it alone otherwise, and prints a note
naming any policy where it left one in place.

Likewise, `Remove_Policy_Trigger.sh --custom-event <name>` and
`Rename_Policy_Trigger.sh --from <name>` skip a policy whose event is something
else rather than clearing or repointing it. Only the named event moves.

### Automatic triggers on enabled policies

Enabling Recurring Check-in on an enabled policy runs it on every Mac in scope
at the next check-in. As in `Enable_Policy.sh`, the script refuses this unless
`--allow-auto-trigger` is passed. A disabled policy is allowed, supporting the
sequence: disable, set triggers, review, enable. `Remove_Policy_Trigger.sh`
rejects the flag.

`Set_Policy_Triggers.sh` only counts a trigger it would newly arm. Leaving one
already on does not trip the refusal, or the guard would fire on runs that
change nothing.

### `<general><trigger>` is read, never written

This legacy summary field contains `EVENT` or `USER_INITIATED`. The docs do not
define its relationship to the booleans precisely, and Jamf maintains it. The
scripts leave it unchanged and report when it moves during a write. It was also
added to the standing state in `CLAUDE.md`.

### `Set_Policy_Self_Service.sh`

`--show` and `--hide` perform the same scalar write with different values, so
they share one script. Scope list additions and removals remain separate scripts
because they use different XML operations.

This script rejects `--include-non-self-service`. Other scripts skip policies
outside Self Service; this script controls that setting, so the same behavior
would make `--show` ineffective for hidden policies.

A policy with no `<self_service>` element fails rather than getting one
synthesised. Under the full-enclosing-element rule a synthesised element is PUT
as the complete truth for that element, so it would land with no display name
and no icon.

Hiding does not disable a policy. A hidden policy keeps its triggers and still
runs. This appears in the script header, usage text, run header, and README.

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

The ninth and tenth scripts set `general/enabled` for every policy in a CSV. A
disabled policy retains its scope, category, triggers, and Self Service entry.
The two operations reverse each other.

### The library helper was wrong for leaf elements

`ReplaceElementInSection` was written for `<category>`, which `xmllint --format`
renders as a block:

```xml
<category>
  <id>7</id>
</category>
```

`<enabled>` is a leaf — `<enabled>true</enabled>`, one line. The function treated
the element as absent and appended a second copy before `</general>`, as
confirmed with a fixture:

```xml
<enabled>true</enabled>     <- original, first
...
<enabled>false</enabled>    <- appended
```

The result is well-formed XML accepted by `xmllint`, but Jamf chooses one value.
The PUT would return `201`, while read-back could report the unchanged value.

Added a one-line leaf branch before the existing block and self-closing branches.
It matches only the previously ignored shape. `Set_Policy_Category.sh` was
re-verified against category fixtures, and the scope suites were rerun because
the helper is shared.

Both scripts count `<enabled>` in the edited `<general>` and refuse payloads that
do not contain exactly one.

### Enabling safety

Enabling a policy with an automatic trigger — Recurring Check-in, Startup,
Login, Logout, Network State Change, Enrollment Complete, or a custom event —
runs it on every Mac in scope at the next trigger without a Self Service action.
The script refuses this by default; `--allow-auto-trigger` overrides the guard.

`Disable_Policy.sh` rejects that flag because it has no effect there, matching
the other writers' handling of flags that belong to another pair.

New library helpers: `GetPolicyEnabled`, `GetPolicyTriggers` (a one-line summary
of everything that can make a policy run) and `PolicyHasAutomaticTrigger`.
`GetPolicyTriggers` is one `awk` pass rather than an `xmllint` call per trigger,
and tracks section boundaries so nested `<self_service_categories>` is not
mistaken for `<self_service>`.

### The token hashes the CSV

Other writers put their group or user in the confirmation token. These scripts
have no such argument, so the token contains the first eight characters of the
policy ID list's `md5`: `ENABLE-3-4a61320c`. A dry-run token cannot apply a
different CSV with the same row count.

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

### Category fields

A policy carries two unrelated fields that share an element name:

| Field | What it is |
|---|---|
| `general/category` | What the policy is filed under in the admin UI — one value |
| `self_service/self_service_categories` | Where the item appears in Self Service — a list, `display_in` and `feature_in` per entry |

This script changes `general/category`. The report has separate columns for
both fields because a policy filed under `Apps & Utilities` can appear under
`Productivity` in Self Service. Changing Self Service display categories would
require separate add/remove list operations and is not implemented.

### Replacement behavior

Because a policy has one category, this script replaces the old value. It uses
`ReplaceElementInSection`, which handles a populated block, a self-closing
`<category/>`, and an absent element. The helper is section-bounded because
`<category>` appears under both `<general>` and `<self_service_categories>`;
only `general/category` may change.

`<general>` is sent complete and differs only in the category. A bare
`<general><category>` payload could drop the policy name, trigger, and other
general settings.

### Category preflight

`PreflightCategory` resolves `/JSSResource/categories/id/<n>` or `/name/<name>`
and aborts the run unless the response is 200. This prevents a typo from
partially refiling the fleet and adds **Read Categories** to the API role.

`--no-category` skips the preflight and writes ID `-1`, which is how Jamf Pro
represents an unassigned category. That representation is unverified; read-back
covers it.

### Ampersands are escaped, not banned

Jamf category names commonly contain `&` ("Apps & Utilities"), so `&` is
allowed and XML-escaped for the payload. XML encoding replaces `&` first to
avoid re-encoding the entities introduced for `<` and `>`. Quotes and angle
brackets are still rejected.

Verification compares decoded strings from `GetPolicyCategory` instead of
building an XPath predicate around the name. `GetPolicyCategory` decodes
entities so a change reads as
`Apps & Utilities -> Productivity` in the log rather than showing `&amp;`.

### Reporting

The dry run reports both the source and destination:

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

`Add_Policy_Scope_Target.sh` and `Remove_Policy_Scope_Target.sh` complete
coverage of all three scope sections.

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

The scripts explicitly refuse these flags because all six scripts share a flag
vocabulary, making it easy to select criteria from the wrong scope section.

### Targets have no wrapper element

`<computer_groups>` and `<computers>` appear twice in a scope: once as targets
directly under `<scope>`, and once inside `<exclusions>`. Passing `scope` as
the section to the existing library functions would have matched both and
appended the new target to the exclusions list too.

The library accepts `targets` as a section value and bounds that region to
everything between `<scope>` and whichever of `<limitations>` or `<exclusions>`
comes first. `CountScopeEntry` drops the section segment from its XPath for the
same reason. The insertion also gained an `inserted` guard on the container
rules, so a second matching container later in the document cannot produce a
duplicate.

### Last-target guard

A policy with no targets remains configured but stops reaching all Macs without
an error. `Remove_Policy_Scope_Target.sh` counts
what the removal would leave (`CountScopeTargets`: computers, computer groups,
buildings, departments) and refuses at zero unless `--allow-empty-scope` is
passed. A policy set to All Computers is exempt, since it keeps reaching every
Mac regardless. Refusals count under `Skipped/refused:` and do not set a
failure exit code.

The add script has the mirror note: on a policy already scoped to All
Computers it logs that the new target changes nothing in practice.

### Notes

- Verified with `bash -n` and `shellcheck` across all eight files. `shellcheck`
  caught two unreachable lines left when the remove script was derived from the
  add script; `bash -n` did not catch them.
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

## 2026-09-12 — limitation scripts and shared scope surgery

Added `Add_Policy_Scope_Limitation.sh` and
`Remove_Policy_Scope_Limitation.sh`, plus a supporting library refactor.

### Computer groups are not limitations

Jamf Pro limits policy scope by **user, user group, network segment and
iBeacon**. A computer group can be a target or an exclusion, but not a
limitation. Both scripts refuse `--group-id` and point to the exclusion scripts
because the four scripts share a flag vocabulary.

The three criteria that are valid here:

| Flag | Writes into | Matches on |
|---|---|---|
| `--username` | `limitations/users/user` | `name` |
| `--user-group` | `limitations/user_groups/user_group` | `name` |
| `--user-group-id` | `limitations/user_groups/user_group` | `id` |

`--user-group` and `--user-group-id` are refused together: they address one
entry by two keys, and accepting both would add the group twice.

### Unverified user-group representation

The stored group representation is unconfirmed because this estate uses Entra
through a Cloud Identity Provider and this environment has no read-only Jamf
access. The scripts default to group name and verify by read-back; a mismatch
reports failure with a restore command. The README includes a confirming curl
command.

### Library: scope surgery generalised

The insertion and removal awk moved into the library with scope section as a
parameter:

- `CountScopeEntry   section container entry match_element value`
- `InsertScopeEntry  scope section container new_node`
- `RemoveScopeEntry  scope section container entry match_element value`

`CountExistingExclusion` is gone, replaced by `CountScopeEntry`; both exclusion
scripts were updated to call the library versions and each lost around 80
lines.

The section parameter is required because `<users>` and `<user_groups>` exist
under **both** `<limitations>` and `<exclusions>`, and the same person can
be both a limitation and an exclusion. Passing the section prevents changes to
the wrong part of the policy without repeating a hardcoded guard in four scripts.

### Regex metacharacters in group names

`RemoveScopeEntry` interpolates the match value into an awk regex. Entra group
names commonly contain a dot, which matches any character. A removal of
`Corp.Marketing` could have taken out `CorpXMarketing`. Metacharacters are now
escaped before the match. The test set covers exactly that pair.

Usernames allow letters, digits, and `. _ - @`; group names also allow spaces.
Values containing quotes remain unsupported because the value enters an XPath
predicate, an awk regex, and XML.

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

The duplicated OAuth block was extracted after three copies had begun to drift.
The report used `read` without `-r`, while the two write scripts used `read -r`.
Token-renewal fixes would also have required three edits.

### What moved

| Moved to the library | Why |
|---|---|
| `curl_timeouts`, `token_renewal_buffer`, token state | Identical in all three |
| `GetJamfProAPIToken`, `APITokenValidCheck`, `CheckAndRenewAPIToken`, `InvalidateAPIToken` | Identical in all three |
| `ResolveJamfProCredentials` | New name for the credential block that was inline in all three |
| `ReadPolicyIDsFromCSV` | Identical in both write scripts |
| `CountExistingExclusion` | Identical in both write scripts |

### What stayed in each script

Argument parsing, `usage`, `log_line`, scope surgery, and the per-policy loop
remain in each script. Add and remove differ in those areas, and moving them
would require extra library parameters.

### Mechanics

Each script resolves the library relative to its own path and refuses to start
without it:

```bash
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
JAMF_API_COMMON="${SCRIPT_DIR}/lib/jamf-api-common.sh"
```

`lib/` must accompany any copied script. `$0` does not resolve symlinks, so a
symlinked script looks for `lib/` next to the symlink. None are currently
symlinked.

Sourcing the library only defines functions and defaults. It does not make a
network call or read credentials.

### Effect

1762 lines across three scripts became 1529 across three scripts and one
library. The report script alone went from 440 lines to 295.

### Notes

- Post-refactor checks covered confirmation tokens (`APPLY-3-42-none` and
  `REMOVE-3-42-none`), CSV and username validation, library resolution,
  missing-library handling, report field counts (13/13/13), and Self Service
  category extraction against the fixture.
- Credential prompts now use `read -r`, resolving two `SC2162` findings.
- Still not run against live Jamf Pro.

---

## 2026-09-12 — Remove_Policy_Scope_Exclusion.sh 1.0.0

Removes a scope exclusion — a computer group by ID,
a user by username, or both — from every policy listed in a CSV. Same
arguments, same credential sources, same dry-run-plus-token safety model, same
full-scope PUT, same read-back verification.

### Four behavioural differences

- A policy without the exclusion is counted under `Not excluded:` and left
  unchanged, allowing safe reruns.
- Read-back requires the exclusion to be **absent**; the add script requires it
  to be present. A PUT that returns 201 and leaves the entry in place is
  reported as a failure with the restore command.
- The confirmation token is `REMOVE-<count>-<group>-<user>`, so an add token
  cannot be pasted into a removal.
- Removing the last entry leaves an empty container (`<computer_groups/>`),
  which is what Jamf Pro itself writes for an empty exclusion list.

### Removal buffers whole entries

`RemoveExclusionFromScope` buffers each `<computer_group>` or `<user>` block and
discards it only when the complete block matches. After `xmllint --format`, an
`<id>` and its parent entry occupy separate lines; a line filter could remove
the ID and leave malformed XML. Buffering also distinguishes group `7` from
group `77`.

The `<exclusions>` guard is required because `<users>` also appears under
`<limitations>`, and the same person can be both a limitation and an exclusion.
Removing one must not disturb the other. That case is in the test set.

### Notes

- Verified with `bash -n` and `shellcheck` (one pre-existing SC2181 style note,
  inherited from the add script's structure). Removal was tested offline under
  `/bin/bash` 3.2.57 against: two exclusions where one is removed; an absent id
  (returns non-zero, reported as nothing to do); the `7` versus `77` prefix
  collision; removing the only exclusion; and the same username present under
  both `<limitations>` and `<exclusions>`. Targets survived every case.
- Not run against live Jamf Pro.

### Duplication at this point in history

The two write scripts shared roughly 500 of their 660 lines: argument parsing,
credentials, token handling, the CSV reader, and the per-policy GET/PUT/verify
loop. They remained standalone so either could be distributed independently.
Shared blocks were byte-identical so `diff` showed the functional differences.
The auth block then existed in three files; the next entry records its
extraction to `scripts/lib/jamf-api-common.sh`.

---

## 2026-09-12 — verified: Classic API is the only option for policies

No code change.

Both scripts read and write policies through the Classic API
(`/JSSResource/policies`). Checked against Jamf's live OpenAPI specs via the
Jamf documentation MCP, Jamf Pro 11.28.1.

**The modern Jamf Pro API has no policy endpoints.** Related endpoints serve
different objects:

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
- Classic is published through the Platform API Gateway as its own spec
  alongside Blueprints and Device Groups.

Revisit the Classic API requirement if the modern API adds policy endpoints
with addressable JSON scope resources.

Sources: developer.jamf.com `/jamf-pro/docs/privileges-and-deprecations`,
`/jamf-pro/docs/deprecation-of-classic-api-computer-inventory-endpoints`,
`/jamf-pro/docs/getting-started-2`, and the Classic and Jamf Pro API OpenAPI
specs themselves.

---

## 2026-09-12 — Add_Policy_Scope_Exclusion.sh 1.0.0

Adds a scope exclusion — a computer group by ID, a user by
username, or both — to every policy listed in a CSV. The report script finds
the policies; this one changes them.

### Safety

This was the repository's first script that wrote to production policies. It
defaults to dry-run; a real run requires `--apply` **and** `--confirm` with a
token derived from the run
(`APPLY-<policy count>-<group>-<user>`). The token changes with the CSV, the
group or the username, so an apply command cannot be pasted from an old run
against a new list. The dry run prints the exact command.

Before each write, the script creates a full `policy-<id>-before.xml` backup. It
skips existing exclusions for safe reruns and skips policies outside Self
Service unless `--include-non-self-service` is passed, preventing a stray CSV ID
from silently rescoping a background policy.

### Complete-scope PUT

Jamf Pro's Classic API replaces the content of any supplied element. A PUT with
only `<exclusions><computer_groups>` and one group can drop every other existing
exclusion. The script therefore GETs the policy, inserts the new node into the
formatted `<scope>` with awk, and PUTs the complete scope back with only that
addition. Targets, limitations, and other exclusions remain unchanged.

The insertion handles five shapes, all tested: a populated container, an empty
`<computer_groups/>`, a container absent from an otherwise populated
`<exclusions>`, a self-closing `<exclusions/>`, and no `<exclusions>` element
at all. The `<exclusions>` guard matters — `<users>` appears under both
`<limitations>` and `<exclusions>`, and a user exclusion must not land in the
limitations list.

### Read-back verification

A Classic API PUT returns 201 whether or not the element was stored as intended,
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
  `--group-id` covers both.
- Classic API is not optional here: the Jamf Pro API has no policy endpoints.
  Authentication is still the modern API (OAuth client credentials).
- Requires **Update Policies** on the API role in addition to **Read Policies**.
- Verified with `bash -n` and `shellcheck`. The insertion, CSV parser, and
  every argument and confirm-token gate were tested offline under `/bin/bash`
  3.2.57. **No part of this has run against live Jamf Pro** — in particular the
  `<users>` element name for user exclusions is taken from the Classic API
  policy schema and has not been confirmed against a real policy. The
  read-back check will report failure if it is wrong.

### Repository

- Added `.gitignore` for `exclusion-backups-*/` and `*.tsv`. Backups and
  reports name internal computer groups, buildings and users.

---

## 2026-09-12 — Self Service category reporting

### Added

- **Three Self Service category columns: SS Categories (Display), SS Categories
  (Featured), Featured on Main Page.** These supplement the policy's own
  `Category`, which is independent of its Self Service placement. A policy in
  `Apps & Utilities` can display under `Productivity`.

- **`ExtractSelfServiceCategories`** iterates indexed `<category>` nodes and
  returns names whose requested flag is true. It uses `ExtractNameList` for
  entity decoding and validates the XPath node count before iteration.

- `feature_on_main_page` is read separately because it is a policy-level flag,
  unrelated to a category's `feature_in`. Absent elements
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

## 2026-09-12 — scope reporting and OAuth authentication

### Added

- **Three scope columns: Scope Targets, Scope Limitations, Scope Exclusions.**
  The policy XML already contained the full `<scope>` element on every request,
  but the script reported only name, category, and Self Service display name.
  Extraction adds no API calls.

  Types collected: computer groups, computers, buildings and departments as
  targets; users, user groups, `limit_to_users` LDAP groups, network segments
  and iBeacons as limitations; all eight exclusion types. Empty target scope is
  reported as `No targets`, empty limitations and exclusions as `None`, so a
  blank cell always means a parse problem rather than an empty scope.

- **`ExtractNameList`** joins every `<name>` matched by an XPath into one
  string. `xmllint --xpath` concatenates matched text nodes with no delimiter
  and separates matched *elements* with a newline, so neither raw form is
  usable. The function matches the elements, rewrites the tags into `; `
  separators, collapses the newlines, and decodes XML entities. `&amp;` is
  decoded last, otherwise an encoded `&amp;lt;` decodes twice and produces `<`.

- **`AppendScopeItem`** labels a non-empty list and joins it to the running
  column with ` | `, skipping empties. Without it, a policy scoped only to
  buildings would have produced `Groups:  | Computers:  | Buildings: 123 Main St`.

### Changed

- **Authentication now uses OAuth client credentials instead of username and
  password.**
  `POST /api/v1/oauth/token` with `grant_type=client_credentials`, parsed with
  `plutil -extract access_token raw -`. The script now wants an API Client ID
  and secret; `jamfpro_user` and `jamfpro_password` are gone, as are the
  `python -c 'import json'` fallbacks for macOS 11 and earlier.

  This removes credentials from Classic API calls. Previously, with
  `NoBearerToken` set, each of the several hundred per-policy requests sent
  `curl -su user:password`.

- **Token renewal re-requests rather than keep-alives.** `/api/v1/auth/keep-alive`
  extends tokens issued by `/api/v1/auth/token`; it is not the renewal path for
  a client-credentials token. The script now records `expires_in` at issue,
  renews 90 seconds before expiry, and still falls back to a fresh token if
  `/api/v1/auth` stops returning 200. `expires_in` is validated as digits before
  it reaches arithmetic — a malformed response would otherwise abort the run
  inside `$(( ))`.

- **The token is invalidated on exit.** `POST /api/v1/auth/invalidate-token`,
  wired into the existing trap with spinner cleanup, so an interrupted run
  does not leave a live token behind.

- **Every `curl` call carries `--connect-timeout 15 --max-time 30`.** This
  repository-wide requirement prevents a report from hanging with its spinner
  still running.

- **Credentials can come from the environment** (`JAMF_PRO_URL`,
  `JAMF_PRO_CLIENT_ID`, `JAMF_PRO_CLIENT_SECRET`) as well as from the script
  header and `com.github.jamfpro-info.plist`. The secret never has to be written
  to disk.

### Fixed

- **Policy names containing `%` corrupted the report.** The row was written as
  `printf "$JamfProID\t$PolicyName\t..."` — the data was the format string. A
  policy named `R&D 100% Pilot` consumed the next field as a conversion. The
  script now uses `printf "%s\t%s..."` with values as arguments. Group names
  are also likely to contain percent signs.

- **The write success check was always true.** `if [[ $? -eq 0 ]]` ran after a
  variable assignment, which succeeds unconditionally, so the
  `ERROR! Failed to read policy record` branch was unreachable. It now checks
  that the policy ID was actually parsed out of the response, and reports the
  requested ID rather than the empty parsed one.

### Removed

- **The `NoBearerToken` code path.** Removed the Jamf Pro 10.34.2-and-earlier
  Basic-auth fallback, which no longer works in this script.

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

The original was a community Jamf Pro reporting script in the style and
credential convention (`com.github.jamfpro-info.plist`, `GetJamfProAPIToken` /
`APITokenValidCheck` / `CheckAndRenewAPIToken`) of Rich Trouton's Jamf Pro
scripts. It authenticated with a Jamf Pro username and password, reported ID,
enabled state, name, category, Self Service display name and URL, and did not
look at policy scope.
