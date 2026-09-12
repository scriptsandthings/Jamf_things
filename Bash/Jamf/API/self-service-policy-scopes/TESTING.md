# Testing

How every file in this directory is validated, what each check proves, and
what none of them can prove. `README.md` says how to run the scripts;
`CHANGELOG.md` says why they are the way they are; this file says why you can
trust them. The repo-wide `TESTPLAN.md` and `VALIDATION.md` at the root point
here for this workstream.

**Nothing in `tests/` touches a Jamf Pro tenant.** The suites talk to a local
mock, and the mock is an assumption about Jamf, not proof. See "What the
suites do not prove" before treating a green run as a live-run substitute.

## Quick run

From this directory:

```bash
# 1. Static: syntax and lint, every shipped script and the library
bash -n scripts/*.sh scripts/lib/*.sh && shellcheck -x -s bash scripts/*.sh scripts/lib/*.sh

# 2. Library functions against XML and CSV fixtures (127 checks)
env -i HOME=/nonexistent PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash tests/lib-harness.sh

# 3. Every script end to end against the mock Jamf Pro (117 checks)
tests/e2e.sh

# 4. Pair drift: only semantic lines may differ between an Add_ and its Remove_
diff scripts/Add_Policy_Scope_Target.sh     scripts/Remove_Policy_Scope_Target.sh
diff scripts/Add_Policy_Scope_Limitation.sh scripts/Remove_Policy_Scope_Limitation.sh
diff scripts/Add_Policy_Scope_Exclusion.sh  scripts/Remove_Policy_Scope_Exclusion.sh
diff scripts/Enable_Policy.sh               scripts/Disable_Policy.sh
diff scripts/Add_Policy_Trigger.sh          scripts/Remove_Policy_Trigger.sh
```

Run all four after any change under `scripts/`. Steps 2 and 3 print one
`PASS` or `FAIL` line per check and a `TOTAL pass=N fail=M` line, and exit 1
on any failure. `KEEP=1 tests/e2e.sh` leaves the work directory in place so
the per-script output files, backups and the mock's request log can be read.

Expected on a clean tree, as of 2026-09-12:

| Step | Result |
|---|---|
| Static | `bash -n` silent, `shellcheck` no findings, 16 scripts + 1 library |
| Library harness | `TOTAL pass=127 fail=0` |
| End to end | `TOTAL pass=117 fail=0` |
| Pair diffs | semantic and comment lines only |

### Why the odd environment

Both suites run the code under `/bin/bash` (3.2.57) with
`PATH=/usr/bin:/bin:/usr/sbin:/sbin` and no `HOME`. This dev box has Homebrew
GNU `sed` and `awk` ahead of the BSD ones; a Mac running a Jamf policy does
not. A BSD incompatibility (the `sed -i ''` form, `awk` regex classes, `date`
flags) only shows up when the GNU tools cannot mask it, so the harness forces
the stock toolchain. The e2e driver itself may run under any shell; it spawns
each script under the stock environment.

### Prerequisites

Base macOS supplies everything the scripts need: `bash` 3.2, `curl`,
`xmllint`, `plutil`, `md5`, BSD `sed`/`awk`. The mock needs `python3` on the
test machine only; `defusedxml` is used for parsing if installed and the
standard library otherwise. `shellcheck` comes from Homebrew. Nothing that
ships calls `python3` (repo rule: on Macs it may be a Command Line Tools
installer stub).

## Layer 1 — static checks

`bash -n` catches syntax; `shellcheck -x -s bash` has earned its place by
catching unreachable code that `bash -n` accepted when a `Remove_` script was
derived from an `Add_`. Intentional findings are suppressed inline with a
comment saying why (`# shellcheck disable=SC2016  # the literal \$TOKEN is
what the scripts print`), never globally.

The pair diff is a static invariant, not a test: each `Remove_` was derived
from its `Add_` by a transform, and `Enable_`/`Disable_` and
`Add_`/`Remove_Policy_Trigger.sh` the same way. A `diff` between a pair
should show only the lines that mean something different. Drift there means a
fix landed on one side of a pair and not the other.

## Layer 2 — library harness (`tests/lib-harness.sh`)

Sources `scripts/lib/jamf-api-common.sh` directly and calls its functions
against the fixtures, with no HTTP at all. Every XML-surgery function is
exercised against the shape that broke it once. Groups, in file order:

| Group | Functions | What it proves |
|---|---|---|
| readers | `GetPolicyEnabled`, `GetLegacyTrigger`, `GetPolicySelfService`, `GetPolicyCategory`, `GetPolicyTriggerState`, `GetPolicyTriggers`, `PolicyHasAutomaticTrigger`, `CountScopeTargets`, `CountScopeEntry` | Values read from a Self Service policy and an All Computers policy; `&amp;` decoded in the category name; `CountScopeEntry` bound to its section, so group 7 in targets is not group 7 in exclusions and `Corp.Marketing` does not match `CorpXMarketing`. |
| `ReadPolicyIDsFromCSV` | one function | Quoted IDs, padded IDs, blank lines, `#` comments, non-numeric rows dropped, tab-separated report output, UTF-8 BOM with no header. |
| R1–R8 `ReplaceElementInSection` | one function | Leaf (`<enabled>`), block (`<category>`), self-closing leaf and block, absent element appended before the section close, wrong section refused (rc 1), a leaf whose value carries an entity, a block replace that must not swallow the following `<site>` block. R2 runs on the **full** policy so `self_service/self_service_categories/category` must survive a `general/category` replace. Each edit is also checked by `diff` line counts against the before-image: R1 is exactly one line added and one removed. |
| I1–I10 `InsertScopeEntry` | one function | Insert into targets, limitations and exclusions and confirm the other two sections did not receive it; a self-closing container; a self-closing `<exclusions/>`; an `<exclusions>` section that is absent entirely; a targets container that is absent; All Computers stays `true`. Every result is re-parsed by `xmllint --noout`. |
| D1–D9 `RemoveScopeEntry` | one function | Remove from one section and confirm the same entry in another section survives; 7 vs 77 in both directions; `Corp.Marketing` vs `CorpXMarketing` (regex metacharacters escaped); absent entry is rc 1; a removal that would match nothing is rc 1 rather than a silent no-op. D9 prints a note rather than asserting: removal by a raw name containing `&` is unreachable because every writer rejects `&` before the library sees it. |
| `DescribeTriggers` | extracted from `Set_Policy_Triggers.sh` by `sed` and `eval` | The `Self Service` prefix is added once, from the flag, never doubled; a simulated set-triggers loop leaves exactly one of each `trigger_*` element and well-formed XML. |
| Self Service leaf | `ReplaceElementInSection` on `<self_service>` | `use_for_self_service` flips and the categories list is untouched (the `Set_Policy_Self_Service.sh` path). |

The harness reads `tests/fixtures/ids.csv` as checked in. It creates its own
scratch directory under `$TMPDIR` and does not clean it up; the files there
are the before/after images the `diffstat` checks compared.

## Layer 3 — end to end (`tests/e2e.sh` + `tests/mock/mock_jamf.py`)

The driver starts the mock on a random port in 20000–29999 (so two runs, or
two agents, cannot collide), seeds it from `tests/fixtures/policy-*.xml`, then
runs every script under the stock environment with the mock's credentials
(`JAMF_PRO_CLIENT_ID=cid`, `JAMF_PRO_CLIENT_SECRET=sec`, token `tok-1`).
Writers go through `dry_then_apply`: a dry run, the confirmation token
scraped from its output, then `--apply --confirm <token>`. Assertions read the
policy back from the mock with `xmllint --xpath`, so a check passes only if
the write actually landed in the stored XML.

Sections, in run order:

| # | Section | What it proves |
|---|---|---|
| 0 | every script | `--help` exits 0; no arguments exits 3 (usage), except the report, which has no required argument. |
| 1 | report | Exit 1 with two unreadable policies named on stderr (404 with its status hint, 500 as non-XML); header plus three Self Service rows; the non-Self-Service policy left out; policy 429 present after a retry (the mock log shows two GETs); `LDAP Groups` filled from bare `limit_to_users` strings; `&amp;` decoded in names; every row fully quoted with CRLF; the CSV feeds straight back into `Enable_Policy.sh` as `--csv`. |
| 2 | scope targets | Add a group and a computer in one run: both present, the four original groups intact, exclusions untouched, `policy-101-before.xml` written once (it does not contain the first change). Remove them: gone, and the `Remove_` backup holds the pre-run state. Removing the last target of policy 303 is `REFUSED`. Also the static count that all 14 writers print a restore hint with a Bearer token and curl timeouts. |
| 3 | exclusions, limitations | Add and remove a group and a user under `<exclusions>` with `<limitations>` untouched, and the reverse; a group present only in `limit_to_users` reads as `ALREADY`; `--user-group` with `--user-group-id` is a usage error; `Corp.Marketing` removed leaves `CorpXMarketing` and the same name under exclusions. |
| 4 | category | Set by name (already-filed policy is `ALREADY`, another is refiled, its name intact); a `/` in the name is rejected with a message pointing at `--category-id`; `--no-category` sets id `-1`. |
| 5 | enable, disable | Enable and disable land and leave exactly one `<enabled>`; `--allow-auto-trigger` is refused by `Disable_`; a trailing flag with no value exits 3 instead of looping forever (`shift 2` in bash 3.2); `--output` with no value exits 3; a policy answering 429 on alternate GETs is enabled with rc 0 (GET, PUT and read-back each retried). |
| 6 | triggers | `Add_ --custom-event` skips a policy carrying a different event and sets the empty one; `--trigger startup` lands and the mock recomputes `general/trigger` to `EVENT`; `Remove_ --custom-event` clears only the matching policy; `Rename_` repoints; `Set_` rejects an empty `--custom-event` and the retired `--no-custom-event`, skips the whole policy when `--clear-custom-event` names the wrong event, sets checkin+login while clearing the right event, prints the summary with the `Self Service` prefix once, and reports `ALREADY` on a rerun. |
| 7 | Self Service visibility | `--hide` flips `use_for_self_service` and leaves the categories list; `--show` flips it back. |
| 8 | signal | `Disable_Policy.sh` with `--delay 3` killed by SIGTERM after the first policy exits 130 and never reaches the second (SIGTERM, because a background job ignores SIGINT; the trap covers both). |
| 9 | bad secret | A wrong client secret exits 1, the message names the credentials rather than the URL, and no backup directory is created (traps and token come before anything on disk). |

### The mock

`tests/mock/mock_jamf.py` is a `python3` HTTP server, roughly 170 lines,
implementing only what the scripts call:

| Endpoint | Behaviour |
|---|---|
| `POST /api/v1/oauth/token` | `cid`/`sec` → `tok-1`, `expires_in` 3600; anything else 400 `invalid_client`. |
| `GET /api/v1/auth` | 200 with a Bearer `tok-1`, else 401. |
| `POST /api/v1/auth/invalidate-token` | 204. |
| `GET /JSSResource/policies` | Every seeded policy plus two phantoms: 404 "Deleted Meanwhile" and 500 "Behind Bad Proxy". |
| `GET /JSSResource/policies/id/{id}` | Stored XML. ID 404 answers 404 with an HTML body; ID 500 answers **200** with a malformed HTML body (a proxy error page, well-formed HTML would pass the XML check); ID 429 answers 429 with `Retry-After: 1` on every odd request. |
| `PUT /JSSResource/policies/id/{id}` | Requires `Content-Type: application/xml` (else 415) and a parseable body (else 400). Each top-level child in the request replaces the same-named child of the stored policy in full — the documented Classic semantics. Then `general/trigger` is recomputed from the six booleans and `trigger_other`. Answers 201 with `<policy><id>`. |
| `GET /JSSResource/categories/id/{id}`, `.../name/{name}` | 200 for ids 5, 9, 21 (`Apps & Utilities`, `Productivity`, `Utilities`), else 404. |

Every request is logged to stderr, which `e2e.sh` captures in the work
directory as `mock.log`; the retry assertions count lines there.

### Fixtures

| File | Role |
|---|---|
| `policy-101.xml` | The busy one. Self Service, enabled, check-in and custom event `install-foo`, category `Apps & Utilities`, name with `&amp;`, groups 7, 77, 78 and `R &amp; D` as targets, `Corp.Marketing` and `CorpXMarketing` under limitations, `Corp.Marketing` and group 7 again under exclusions, `alice` under both limitations and exclusions, one Self Service category. Every container that the section argument exists for appears in more than one section. |
| `policy-202.xml` | All Computers, not Self Service, disabled, no triggers, self-closing `<category/>`, `<computers/>` and `<exclusions/>`. The "absent and self-closing" shapes. |
| `policy-303.xml` | Self Service, disabled, no triggers, one target group (7), `Teachers` and `Staff` under `limit_to_users` only. The "last target" and "mirror only" cases. |
| `policy-429.xml` | A copy of 303 with id 429, so the rate-limit path has a real policy to enable. |
| `ids.csv` | Header, quoted ID, blank line, comment, padded ID, non-numeric row, tab-separated row. |
| `bom.csv` | UTF-8 BOM, no header. |
| `empty.csv` | Header and rows with no usable ID. |
| `policies.tsv` | A report in the pre-CSV tab format, to prove the reader still accepts it. |

Any new fixture must carry the same container name in more than one section.
A fixture where `computer_groups` appears only under `<scope>` proves nothing
about the section argument, which is the whole point of the library.

The e2e driver writes its own CSV of IDs (101, 202, 303, 404, 500) at run
time so the phantom IDs reach every writer.

## What the suites do not prove

The mock encodes what the Classic API is documented to do. Green runs prove
the shell, the XML surgery and the control flow. They do not prove Jamf's
behaviour, and four things are settled only by the first live run:

1. **Whether Jamf Pro recomputes `general/trigger`** when a `trigger_*`
   boolean changes. The mock does; nothing here writes it; the trigger scripts
   report it when it moves so the first real run answers this on its own.
2. **Whether Entra groups resolve by name** through the Cloud Identity
   Provider on this tenant. The schema allows `<name>`; the mock accepts any.
3. **PI-005747**: the Classic API can return an empty `<user_groups/>` under
   `<limitations>` for a policy whose UI shows one. `Add_Policy_Scope_Limitation.sh --user-group`
   names the issue if its read-back fails after a 201.
4. **Real rate limiting and token expiry.** The mock's 429 is a fixed
   alternation with `Retry-After: 1`; its token never expires. Live 429
   behaviour and the `/api/v1/auth` probe cadence are untested.

Nothing in this directory has been run against live Jamf Pro. First contact
is the read-only report:

```bash
./scripts/Generate_Self_Service_Policy_Report.sh --output ~/Desktop/self-service.csv
```

then one writer, one policy, dry run first, and a comparison of the backup
against the Jamf Pro UI before the token is confirmed.

## Adding or changing a script

1. Decide whether the field is a leaf, a block or self-closing, and add a
   harness case for that shape against a fixture that has it. The leaf branch
   of `ReplaceElementInSection` exists because the first leaf it met looked
   absent and was appended twice.
2. Give the mock whatever the new script calls that it does not already
   serve, in the same fail-closed style (a phantom ID for each failure mode).
3. Add an e2e section: `--help` and no-args land in section 0 automatically;
   the rest is a `dry_then_apply` plus `get_field` assertions on the stored
   XML, never on the script's own success line.
4. If it is one half of a pair, derive the other half and confirm the pair
   diff shows only semantic lines.
5. Update the check counts in this file, `README.md` and `CLAUDE.md`, and add
   the change to `CHANGELOG.md` with the reason.

## Record of results

| Date | What | Result |
|---|---|---|
| 2026-09-12 | `bash -n` + `shellcheck -x -s bash`, 18 files (16 scripts, library, both suites) | clean |
| 2026-09-12 | `tests/lib-harness.sh` under stock PATH, `/bin/bash` 3.2.57, macOS Tahoe 26 | 127/127 |
| 2026-09-12 | `tests/e2e.sh`, same environment | 117/117 |
| 2026-09-12 | Pair diffs (Target 81, Exclusion 51, Limitation 61, Trigger 103, Enable/Disable 75 differing lines) | semantic and comment lines only |
| 2026-09-12 | Endpoints and XML elements against Jamf's Classic and Jamf Pro API OpenAPI specs | current, none deprecated |
| — | Any script against live Jamf Pro | **not run** |

Add a row here when a suite is rerun after a Jamf Pro upgrade, a macOS
upgrade, or a change to `scripts/`, including negative results. The root
`VALIDATION.md` carries the same rows at repo level.
