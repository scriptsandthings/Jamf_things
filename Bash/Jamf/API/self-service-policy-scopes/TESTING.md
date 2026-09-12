# Testing

This file defines the validation layers and their limits. See `README.md` for
usage, `CHANGELOG.md` for design history, and the repository-level `TESTPLAN.md`
and `VALIDATION.md` for the broader test record.

Layers 1–3 do not connect to a Jamf Pro tenant. They use a local mock, which
models Jamf behavior but cannot verify it. See [What the suites do not prove](#what-the-suites-do-not-prove)
before treating an offline pass as equivalent to a live run.

Layer 4 connects only to the designated non-production test instance and only
touches objects it creates with names beginning `ZZ-LIVETEST-*`.
`tests/live/guard.sh` refuses any other host. Results are recorded in
`LIVE-VALIDATION.md`.

## Quick run

Run from this directory:

```bash
# 1. Static: syntax and lint, every shipped script and the library
bash -n scripts/*.sh scripts/lib/*.sh && shellcheck -x --source-path=scripts -s bash scripts/*.sh scripts/lib/*.sh

# 2. Library functions against XML and CSV fixtures (137 checks)
env -i HOME=/nonexistent PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash tests/lib-harness.sh

# 3. Every script end to end against the mock Jamf Pro (135 checks)
tests/e2e.sh

# 4. Every flag against a LIVE Jamf Pro (161 checks).
#    Needs JAMF_PRO_* variables; guard.sh allows only the configured test host.
tests/live/every-flag.sh

# 5. Pair drift: only semantic lines may differ between an Add_ and its Remove_
diff scripts/Add_Policy_Scope_Target.sh     scripts/Remove_Policy_Scope_Target.sh
diff scripts/Add_Policy_Scope_Limitation.sh scripts/Remove_Policy_Scope_Limitation.sh
diff scripts/Add_Policy_Scope_Exclusion.sh  scripts/Remove_Policy_Scope_Exclusion.sh
diff scripts/Enable_Policy.sh               scripts/Disable_Policy.sh
diff scripts/Add_Policy_Trigger.sh          scripts/Remove_Policy_Trigger.sh
```

Run all four layers after changing anything under `scripts/`. Layers 2 and 3
print one `PASS` or `FAIL` per check, end with `TOTAL pass=N fail=M`, and exit 1
after any failure. Set `KEEP=1` for `tests/e2e.sh` to retain its work directory,
including per-script output, backups, and the mock request log.

### Combined runner and pre-push hook

`tests/run-all.sh` executes all four layers in order and returns nonzero if any
layer fails:

```bash
tests/run-all.sh              # layers 1-3, plus layer 4 if the JAMF_PRO_* vars are set
LIVE=skip tests/run-all.sh    # layers 1-3 only, no complaint
LIVE=require tests/run-all.sh # fail if layer 4 cannot run
```

Without credentials, it reports Layer 4 as `SKIPPED` rather than omitting it.
Offline success remains limited to the mock; all five defects found on
2026-09-12 had first passed Layers 1–3.

`tests/install-hooks.sh` installs a `pre-push` hook. The hook runs Layers 1–3
and blocks a push if they fail. If anything under `scripts/` is newer than the
last successful live run, it warns without blocking. A live run requires a
reachable Jamf Pro server and credentials, so the hook does not make either a
condition for pushing. `every-flag.sh` records the timestamp in
`tests/live/.last-success`. That file is gitignored because its state applies
only to the local machine.

The repository does not automate live runs; automation requires stored
credentials and a macOS runner.

Expected results on a clean tree as of 2026-09-12:

| Step | Result |
|---|---|
| Static | `bash -n` silent, `shellcheck` no findings, 16 scripts + 1 library |
| Library harness | `TOTAL pass=137 fail=0` |
| End to end | `TOTAL pass=135 fail=0` |
| Live (layer 4) | `TOTAL pass=161 fail=0` |
| Pair diffs | semantic and comment lines only |

### Test environment

Both suites execute the code with `/bin/bash` 3.2.57,
`PATH=/usr/bin:/bin:/usr/sbin:/sbin`, and no `HOME`. Homebrew GNU `sed` and
`awk` precede the BSD versions on this development machine, while a Mac running
a Jamf policy uses the BSD tools. Removing the GNU tools from the test
environment exposes BSD differences such as `sed -i ''`, `awk` regex classes,
and `date` flags. The e2e driver may run under any shell; it launches each
script in the stock environment.

### Prerequisites

The scripts use only tools included with macOS: bash 3.2, `curl`, `xmllint`,
`plutil`, `md5`, and BSD `sed` and `awk`. The mock needs `python3` only on the
test machine. It uses `defusedxml` when installed and falls back to the Python
standard library. Install `shellcheck` with Homebrew. Shipped scripts never
invoke `python3`; on macOS it may be only a Command Line Tools installer stub.

## Layer 1 — static checks

`bash -n` checks syntax. `shellcheck -x -s bash` also catches unreachable code;
it found such code after a `Remove_` script was derived from an `Add_` script,
even though `bash -n` passed. Suppress intentional findings inline with an
explanation, never globally:

```bash
# shellcheck disable=SC2016  # the literal \$TOKEN is what the scripts print
```

Each `Remove_` script was derived from its `Add_` counterpart. The enable,
disable and trigger pairs follow the same pattern, so their diffs should contain
only intentional behavior or comment changes.

## Layer 2 — library harness (`tests/lib-harness.sh`)

The harness sources `scripts/lib/jamf-api-common.sh` and calls its functions
against fixtures without HTTP. Each XML-editing function is tested against a
shape that previously broke it.

| Group | Functions | Checks |
|---|---|---|
| readers | `GetPolicyEnabled`, `GetLegacyTrigger`, `GetPolicySelfService`, `GetPolicyCategory`, `GetPolicyTriggerState`, `GetPolicyTriggers`, `PolicyHasAutomaticTrigger`, `CountScopeTargets`, `CountScopeEntry` | Reads Self Service and All Computers policies; decodes `&amp;` in a category name; binds `CountScopeEntry` to its section so target group 7 does not match exclusion group 7, and `Corp.Marketing` does not match `CorpXMarketing`. |
| `ReadPolicyIDsFromCSV` | one function | Accepts quoted and padded IDs, blank lines, `#` comments, a tab-separated report, and a UTF-8 BOM without a header; drops non-numeric rows. |
| R1–R8 `ReplaceElementInSection` | one function | Handles a leaf (`<enabled>`), a block (`<category>`), self-closing leaf and block elements, and an absent element appended before the section close; refuses the wrong section with rc 1; handles an entity in a leaf value; replaces a block without consuming the following `<site>` block. R2 uses the full policy so changing `general/category` must preserve `self_service/self_service_categories/category`. Each edit is checked with before-image `diff` line counts; R1 adds exactly one line and removes exactly one line. |
| I1–I10 `InsertScopeEntry` | one function | Inserts into targets, limitations, and exclusions without changing the other two sections; handles a self-closing container, self-closing `<exclusions/>`, a missing `<exclusions>` section, and a missing targets container; preserves All Computers as `true`. Every result passes `xmllint --noout`. |
| D1–D9 `RemoveScopeEntry` | one function | Removes from one section while preserving the same entry elsewhere; distinguishes 7 from 77 in both directions and `Corp.Marketing` from `CorpXMarketing` by escaping regex metacharacters; returns rc 1 for an absent entry or any no-match removal. |
| `DescribeTriggers` | extracted from `Set_Policy_Triggers.sh` with `sed` and `eval` | Adds the `Self Service` prefix once, based on the flag; never doubles it. A simulated set-triggers loop leaves exactly one of each `trigger_*` element and valid XML. |
| Self Service leaf | `ReplaceElementInSection` on `<self_service>` | Flips `use_for_self_service` without changing the categories list, matching the `Set_Policy_Self_Service.sh` path. |

D9 records rather than asserts removal of a raw name containing `&`, because
every writer rejects `&` before the library receives it. D7b and D7c insert and
remove a Jamf Pro user group from `exclusions/jss_user_groups` while preserving
the same group as a deployment target. D7c reformats between operations to match
the scripts' GET-and-format flow before line-oriented awk removal.

The harness reads the checked-in `tests/fixtures/ids.csv`. It creates a scratch
directory under `$TMPDIR` and leaves it in place. Those files are the before and
after images used by the `diffstat` checks.

## Layer 3 — end to end (`tests/e2e.sh` + `tests/mock/mock_jamf.py`)

The driver starts the mock on a random port from 20000 through 29999 so
concurrent runs and agents do not collide. It seeds the mock from
`tests/fixtures/policy-*.xml`, then runs every script under the stock
environment with `JAMF_PRO_CLIENT_ID=cid`, `JAMF_PRO_CLIENT_SECRET=sec`, and
token `tok-1`.

Writers run through `dry_then_apply`: dry run, extract the confirmation token
from output, then run `--apply --confirm <token>`. Assertions fetch the policy
from the mock and inspect it with `xmllint --xpath`; a write check passes only
when the stored XML changed.

| # | Section | Checks |
|---|---|---|
| 0 | every script | `--help` exits 0. Running without arguments exits 3 for usage, except for the report, which takes no required arguments. |
| 1 | report | Exits 1 and names two unreadable policies on stderr: a 404 with its status hint and a 500 returned as non-XML. Produces a header and three Self Service rows; omits the non-Self-Service policy; includes policy 429 after retry, with two GETs in the mock log; fills `LDAP Groups` from bare `limit_to_users` strings; decodes `&amp;` in names; fully quotes every row and uses CRLF; feeds the resulting CSV directly to `Enable_Policy.sh --csv`. |
| 2 | scope targets | Adds a group and computer in one run; preserves both additions, all four original groups, and exclusions. Writes `policy-101-before.xml` once, without the first change. Removes the additions and verifies the `Remove_` backup contains the pre-run state. Refuses removal of policy 303's last target. A static check verifies all 14 writers print a Bearer-token restore hint with curl timeouts. |
| 3 | exclusions, limitations | Adds and removes a group and user under `<exclusions>` without changing `<limitations>`, and vice versa. A group present only in `limit_to_users` returns `ALREADY`. Combining `--user-group` with `--user-group-id` is a usage error. Removing `Corp.Marketing` preserves `CorpXMarketing` and the same name under exclusions. |
| 3b | Jamf Pro user group exclusions | Refuses an unknown group with exit 1 before creating the backup directory, and explains why validation happens first. Combining `--user-group` with `--user-group-id` is a usage error. Adds by ID and name to `exclusions/jss_user_groups`; preserves the `user_groups` directory and computer-group exclusions. Removing the exclusion preserves the same group as a deployment target in `scope/jss_user_groups`. |
| 4 | category | Sets by name; an already-filed policy returns `ALREADY`, another is refiled, and its name remains intact. Rejects `/` in a name with guidance to use `--category-id`. `--no-category` sets ID `-1`. |
| 5 | enable, disable | Enable and disable changes persist and leave one `<enabled>`. `Disable_` refuses `--allow-auto-trigger`. A trailing flag or `--output` without a value exits 3 instead of looping forever under bash 3.2 `shift 2`. A policy returning 429 on alternate GETs is enabled with rc 0 after retries for GET, PUT, and read-back. |
| 6 | triggers | `Add_ --custom-event` skips a policy with a different event and sets the empty policy. `--trigger startup` persists, and the mock recomputes `general/trigger` to `EVENT`. `Remove_ --custom-event` clears only the matching policy. `Rename_` repoints the event. `Set_` rejects empty `--custom-event` and retired `--no-custom-event`; skips the entire policy when `--clear-custom-event` names the wrong event; sets checkin and login while clearing the right event; prints the summary with one `Self Service` prefix; reports `ALREADY` on repeat. |
| 7 | Self Service visibility | `--hide` flips `use_for_self_service` without changing categories; `--show` flips it back. |
| 8 | signal | `Disable_Policy.sh --delay 3`, terminated by SIGTERM after its first policy, exits 130 and never processes the second. A background job ignores SIGINT, so this uses SIGTERM; the trap handles both. |
| 9 | bad secret | A wrong client secret exits 1, names the credentials rather than the URL, and creates no backup directory because traps and token handling run before disk writes. |

### Mock server

`tests/mock/mock_jamf.py` is a minimal `python3` HTTP server implementing only
the endpoints called by the scripts.

| Endpoint | Behavior |
|---|---|
| `POST /api/v1/oauth/token` | Returns `tok-1` with `expires_in` 3600 for `cid`/`sec`; otherwise returns 400 `invalid_client`. |
| `GET /api/v1/auth` | Returns 200 for Bearer `tok-1`; otherwise 401. |
| `POST /api/v1/auth/invalidate-token` | Returns 204. |
| `GET /JSSResource/policies` | Returns all seeded policies plus two phantoms: 404 "Deleted Meanwhile" and 500 "Behind Bad Proxy". |
| `GET /JSSResource/policies/id/{id}` | Returns stored XML. ID 404 returns 404 with HTML. ID 500 returns **200** with malformed HTML to model a proxy error page; well-formed HTML would pass the XML check. ID 429 returns 429 with `Retry-After: 1` on every odd request. |
| `PUT /JSSResource/policies/id/{id}` | Requires `Content-Type: application/xml`, otherwise 415, and a parseable body, otherwise 400. Each top-level request child fully replaces the stored child with the same name, following documented Classic semantics. The server then recomputes `general/trigger` from six booleans and `trigger_other`, and returns 201 with `<policy><id>`. |
| `GET /JSSResource/categories/id/{id}`, `.../name/{name}` | Returns 200 for IDs 5, 9, and 21: `Apps & Utilities`, `Productivity`, and `Utilities`. All others return 404. |
| `GET /JSSResource/usergroups/id/{id}`, `.../name/{name}` | Returns the group for IDs 2, 23, and 77; otherwise 404. The name response body matters because exclusion preflight extracts `<id>` from it and addresses `jss_user_groups` by ID. Names arrive percent-encoded. |

Every request goes to stderr. `e2e.sh` captures it as `mock.log` in the work
directory, and retry assertions count matching lines there.

### Fixtures

| File | Role |
|---|---|
| `policy-101.xml` | Comprehensive fixture containing all ten exclusion containers returned by live Jamf Pro, with `jss_user_groups` both as a deployment target and empty under exclusions so section binding can be tested. It is Self Service, enabled, check-in, custom event `install-foo`, category `Apps & Utilities`, and has a name containing `&amp;`. Targets include groups 7, 77, 78, and `R &amp; D`; limitations contain `Corp.Marketing`, `CorpXMarketing`, and `alice`; exclusions repeat `Corp.Marketing`, group 7, and `alice`; Self Service has one category. Every container supported by the section argument occurs in more than one section. |
| `policy-202.xml` | All Computers, not Self Service, disabled, no triggers, with self-closing `<category/>`, `<computers/>`, and `<exclusions/>`. Covers absent and self-closing shapes. |
| `policy-303.xml` | Self Service, disabled, no triggers, one target group (7), and `Teachers` and `Staff` only under `limit_to_users`. Covers the last-target and mirror-only cases. |
| `policy-429.xml` | Copy of policy 303 with ID 429, giving the rate-limit path a real policy to enable. |
| `ids.csv` | Header, quoted ID, blank line, comment, padded ID, non-numeric row, and tab-separated row. |
| `bom.csv` | UTF-8 BOM without a header. |
| `empty.csv` | Header and rows with no usable ID. |
| `policies.tsv` | Report in the former tab-separated format, proving the reader remains compatible with it. |

Every new fixture must place the same container name in multiple sections. A
fixture with `computer_groups` only under `<scope>` cannot test the section
argument.

At runtime, the e2e driver creates its own ID CSV containing 101, 202, 303,
404, and 500 so every writer receives the phantom IDs.

## What the suites do not prove

The mock follows documented Classic API behavior and the name-resolution
behavior verified over the wire on 2026-09-12. Offline passes validate shell
behavior, XML editing, and control flow. Only Layer 4 validates Jamf itself.

Results for the four questions identified before live testing:

1. **Jamf recomputes `general/trigger`: settled.** A disabled policy without
   triggers initially returned `USER_INITIATED`. After
   `Add_Policy_Trigger.sh --trigger startup`, it returned `EVENT`; after the
   matching removal, it returned `USER_INITIATED`. The trigger writers do not
   need to write this field. If Jamf had behaved differently, all four writers
   would have needed to set both fields to avoid creating policies that never
   fire.
2. **Directory group name resolution: settled for LDAP, open for Entra.** The
   test instance had no directory until an lldap server was added on
   2026-09-12, so
   `limitations/user_groups` could not hold a value and positive writes by
   `Add_`/`Remove_Policy_Scope_Limitation.sh` could not be validated. Both now
   pass with LDAP. Entra groups delivered through a **Cloud Identity Provider**
   remain untested. They use the same container and code path but a different
   directory.
3. **PI-005747: not observed.** Writers still mention it when a user-group
   limitation reports FAILED after a 201.
4. **Real rate limiting: untested.** A single-tenant, self-hosted instance never
   returned 429. Only mock policy 429 covers the retry path.

Layer 4 still does not cover a Cloud Identity Provider, a real 429, a
multi-tenant Jamf Cloud instance, or any Jamf Pro release other than 11.32.0.

## Layer 4 — live validation (`tests/live/every-flag.sh`)

**Status: 161/161 passed.** `LIVE-VALIDATION.md` records the procedure,
directory-service setup, and findings.

The suite covers all 29 flags across all 15 scripts and every refusal path
against a non-production Jamf Pro 11.32.0 instance. `tests/live/guard.sh`
checks results with curl code implemented separately from the scripts under
test.

Run it on macOS under `env -i` with a stock PATH. One pass then validates both
Jamf behavior and bash 3.2/BSD compatibility. An earlier Debian-worker run
validated only Jamf behavior: `/usr/bin/plutil` and `/sbin/md5` required shims,
and GNU `sed` and `awk` conceal the incompatibilities the stock PATH is intended
to expose.

```bash
export JAMF_PRO_URL=https://jamf.example.invalid
export JAMF_PRO_CLIENT_ID=... JAMF_PRO_CLIENT_SECRET=...
tests/live/every-flag.sh
```

`guard.sh` exits 3 for every host except the configured test instance and never
prints a credential. All created objects use the `ZZ-LIVETEST-*` prefix.
Teardown runs on all exits, including Ctrl-C, and confirms cleanup by listing
the instance rather than relying on its own delete loop.

Live testing found five defects, four of which no offline layer exposed: a 409
that partially applies while returning failure, a user-group limitation removal
that removed nothing, the retired logout trigger, a silently resolved
`--show`/`--hide` conflict, and a preflight that left an empty backup directory.
All five are fixed; see `CHANGELOG.md`.

## Adding or changing a script

1. Classify the field as a leaf, block, or self-closing element. Add a harness
   case for that shape using a fixture where it appears. The leaf branch of
   `ReplaceElementInSection` exists because the first leaf encountered looked
   absent and was appended twice.
2. Add any missing endpoint or behavior to the mock. Return failure for
   unsupported cases, and add a phantom ID for each failure mode.
3. Add an e2e section. Section 0 automatically covers `--help` and no arguments.
   Test the rest with `dry_then_apply` and `get_field` assertions against stored
   XML, never the script's success text.
4. For paired scripts, derive the other half and confirm its diff contains only
   semantic differences.
5. Update test counts in this file, `README.md`, and `CLAUDE.md`. Record the
   change and its reason in `CHANGELOG.md`.

## Record of results

| Date | What | Result |
|---|---|---|
| 2026-09-12 | `bash -n` + `shellcheck -x -s bash`, 18 files (16 scripts, library, both suites) | clean |
| 2026-09-12 | `tests/lib-harness.sh` under stock PATH, `/bin/bash` 3.2.57, macOS Tahoe 26 | 136/136 |
| 2026-09-12 | `tests/e2e.sh`, same environment | 129/129 |
| 2026-09-12 | Pair diffs (Target 81, Exclusion 89, Limitation 76, Trigger 103) | semantic and comment lines only |
| 2026-09-12 | Endpoints and XML elements against Jamf's Classic and Jamf Pro API OpenAPI specs | current, none deprecated |
| 2026-09-12 | Scope container map and resolution behavior, verified over the wire | recorded in `CLAUDE.md` |
| 2026-09-12 | First live run on a Debian test host: 13 of 15 scripts, partial flag coverage | 55/55 after fixes; validated Jamf, not BSD compatibility |
| 2026-09-12 | lldap directory service added to the test instance | `limitations/user_groups` resolves for the first time |
| 2026-09-12 | `tests/live/every-flag.sh` on macOS: all 29 flags, all 15 scripts, every refusal path | **161/161** |
| 2026-09-12 | Live findings: 409 partially applies; `limit_to_users` is the source; `trigger_logout` retired | five defects fixed |
| 2026-09-12 | Mock updated for Jamf server-side resolution; one stale e2e assertion corrected | 129/129 |
| — | Entra groups through a **Cloud Identity Provider** | untested; requires a tenant with one |
| — | A real Jamf 429 | never provoked; mock-only |

Add a row after rerunning a suite following a Jamf Pro upgrade, macOS upgrade,
or change under `scripts`. Include failed results. The repository-level
`VALIDATION.md` contains the same rows.
