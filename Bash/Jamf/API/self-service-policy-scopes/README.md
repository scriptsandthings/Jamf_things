# Self Service policy scopes

`scripts/Generate_Self_Service_Policy_Report.sh` walks every policy in Jamf Pro,
keeps the ones flagged as Self Service policies, and writes a CSV report of what
they are and **who they are scoped to**.

The scope columns are the point. Jamf Pro's own policy list will tell you a
policy exists; it will not tell you, across 400 policies in one view, which
groups see which Self Service item and which groups are excluded.

All fifteen scripts source `scripts/lib/jamf-api-common.sh` and will refuse to run
without it, so keep `lib/` beside them when copying a script somewhere else. The
library holds what is identical everywhere — the OAuth token lifecycle,
credential resolution, the CSV reader and the XML surgery helpers. Argument
parsing and the per-policy work stay in each script, where they differ.

## Prerequisites

An **API Client**, not a user account. In Jamf Pro:

1. `Settings > System > API Roles and Clients > API Roles` — create a role with
   **Read Policies**. Add **Update Policies** for any of the writer scripts,
   and **Read Categories** as well for `Set_Policy_Category.sh`, which checks
   the category exists before it touches a policy.
2. `Settings > System > API Roles and Clients > API Clients` — create a client,
   assign that role, enable it, generate a secret. Copy the secret at creation;
   Jamf Pro will not show it again.

Locally: `xmllint` and `plutil`, both base macOS. No Python, no Homebrew bash —
the scripts are bash 3.2 clean and run under `/bin/bash`.

## Credentials

Three sources, checked in this order. First non-empty value wins.

```bash
# 1. Already set in the calling shell as jamfpro_url, jamfpro_client_id and
#    jamfpro_client_secret (a wrapper script may export them). No script in
#    this directory carries a filled-in header; do not add one and commit it.

# 2. A preference file
defaults write $HOME/Library/Preferences/com.github.jamfpro-info jamfpro_url https://your.jamfcloud.com
defaults write $HOME/Library/Preferences/com.github.jamfpro-info jamfpro_client_id <client-id>
defaults write $HOME/Library/Preferences/com.github.jamfpro-info jamfpro_client_secret <client-secret>

# 3. Environment variables
export JAMF_PRO_URL=https://your.jamfcloud.com
export JAMF_PRO_CLIENT_ID=<client-id>
export JAMF_PRO_CLIENT_SECRET=<client-secret>
```

Anything still missing is prompted for. The secret prompt is `read -s`, so it
does not echo and does not land in shell history.

## Run it

```bash
./scripts/Generate_Self_Service_Policy_Report.sh
./scripts/Generate_Self_Service_Policy_Report.sh --output ~/Desktop/self-service.csv
```

It prints a spinner (only when stdout is a terminal), the policy count it is
working through, and finally the path to the report:

```
Report being generated. File location will appear below once ready.
Checking 412 policies for Self Service policies ...

Self Service policies found: 137 of 412
Report on Self Service policies available here: /var/folders/.../T/self-service-report.AbC123/self-service-policies-20260912-121500.csv
```

A policy that cannot be read (a 404, a token hiccup, a proxy error page) is
named on stderr and counted at the end, and the script exits 1 -- it never
presents a report with silently missing rows as complete. Without `--output`
the report lands in a fresh temp directory; `--help` lists the columns.

Runtime is roughly one API call per policy, serially. Several hundred policies
takes a few minutes.

Open the CSV in Numbers or Excel. Every field is double-quoted (RFC 4180),
so names with commas, semicolons or quotes survive the round trip, and the
report can be fed straight back to any writer as its `--csv`.

## Report columns

| Column | Content |
|---|---|
| Jamf Pro ID Number | Policy ID |
| Self Service Policy | Always `true` — non-Self-Service policies are filtered out |
| Policy Enabled | `true` / `false` |
| Policy Name | Policy name in Jamf Pro |
| Category | Policy category |
| Self Service Display Name | What the user actually sees in Self Service |
| **SS Categories (Display)** | Self Service categories the item appears under |
| **SS Categories (Featured)** | Self Service categories the item is featured in |
| **Featured on Main Page** | `true` / `false` — the policy-level Self Service main page flag |
| **Scope Targets** | Who it is scoped to |
| **Scope Limitations** | Who it is limited to within that scope |
| **Scope Exclusions** | Who is excluded |
| Jamf Pro URL | Direct link to the policy |

The three scope columns are built from the policy's `<scope>` element. Each is a
`|`-separated list of labelled types, and each type is a `;`-separated list of
names:

```
Groups: All Managed Macs; R&D Pilot | Computers: ORG-MBP-001 | Buildings: 123 S Elm St
```

- **Targets** — `All Computers` when scoped to everything, otherwise computer
  groups, individual computers, buildings, departments. `No targets` when a
  policy is scoped to nothing at all (it will never run; worth investigating).
- **Limitations** — users, user groups, LDAP groups (Jamf Pro's "limit to users
  in groups", stored outside the limitations element as bare
  `<user_group>Name</user_group>` strings), network segments, iBeacons. `None`
  when unlimited.
- **Exclusions** — computer groups, computers, buildings, departments, users,
  user groups, network segments, iBeacons. `None` when nothing is excluded.

## Self Service categories

Three columns describe where the item shows up in Self Service. They come from
`<self_service_categories>`, where each category carries its own two flags:

```xml
<category><name>Productivity</name><display_in>true</display_in><feature_in>false</feature_in></category>
```

- **SS Categories (Display)** — categories with `display_in` true, semicolon
  separated. `None` when the item is in no category.
- **SS Categories (Featured)** — categories with `feature_in` true. Usually a
  subset of the display list, but Jamf Pro sets the two flags independently, so
  a category can be featured without being displayed.
- **Featured on Main Page** — the `feature_on_main_page` policy-level flag. Not
  a category, and unrelated to being featured *in* one.

The policy's own `Category` column and its Self Service categories are separate
fields. A policy can sit in `Apps & Utilities` for admin organisation and display
under `Productivity` in Self Service.

## Adding exclusions

`scripts/Add_Policy_Scope_Exclusion.sh` adds a scope exclusion — a computer
group by ID, a user by username, or both — to every policy listed in a CSV.
The report above produces the list; this applies the change to it.

It needs **Update Policies** on the API role in addition to **Read Policies**.

### It is dry-run by default

```bash
# See what would change. Writes nothing.
./scripts/Add_Policy_Scope_Exclusion.sh --csv policies.csv --group-id 77

# The dry run ends by printing the exact apply command, including a token
# derived from the policy count and the exclusion:
./scripts/Add_Policy_Scope_Exclusion.sh --csv policies.csv --group-id 77 \
    --apply --confirm APPLY-42-77-none
```

The token changes if the CSV, the group or the username changes, so an apply
command cannot be pasted from an old run against a new list.

### CSV format

Policy ID in the first column, comma or tab separated. A header row, blank
lines and `#` comments are skipped — anything whose first column is not all
digits is ignored, so the report CSV from the other script can be fed in
directly.

```csv
Jamf Pro ID Number,Policy Name
412,Install Chrome
87,Install Zoom
```

### What it does per policy

1. `GET /JSSResource/policies/id/<id>`. A non-200 is a failure, not an empty policy.
2. Skips the policy unless it is a Self Service policy. `--include-non-self-service`
   overrides. A stray ID in a CSV should not silently rescope a background policy.
3. Skips it if the exclusion is already there. Re-running is safe.
4. Writes `policy-<id>-before.xml` to the backup directory.
5. `PUT`s the **complete `<scope>` element**, byte-identical except for the added
   node. This is the important part: Jamf Pro's Classic API replaces the content
   of any element a request supplies, so a PUT carrying a bare
   `<exclusions><computer_groups>` with one group in it can drop every other
   exclusion on the policy. Sending the whole scope removes the question.
6. Reads the policy back and confirms the exclusion is present. A 201 is not
   proof; only the read-back is.

### Restoring

Each modified policy leaves a full `policy-<id>-before.xml`. To put one back:

```bash
curl --connect-timeout 15 --max-time 30 -X PUT \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/xml" \
  --data-binary @exclusion-backups-.../policy-412-before.xml \
  "$JAMF_PRO_URL/JSSResource/policies/id/412"
```

### Options

| Flag | Effect |
|---|---|
| `--csv <file>` | Required. Policy IDs. |
| `--group-id <n>` | Exclude this computer group. Smart and static groups share one ID space and one scope element, so either works. |
| `--username <name>` | Exclude this user. Letters, digits and `. _ - @` only — the name goes into both an XPath predicate and XML, and restricting the character set is what keeps both safe. |
| `--apply` | Write. Without it nothing is modified. |
| `--confirm <token>` | Required with `--apply`. |
| `--backup-dir <dir>` | Default `./exclusion-backups-YYYYmmdd-HHMMSS`. |
| `--log <file>` | Default `<backup-dir>/run.log`. |
| `--delay <seconds>` | Pause between policies. Default 0. |
| `--include-non-self-service` | Do not skip non-Self-Service policies. |

Exit codes: `0` all policies correct or updated, `1` at least one failed,
`2` no usable rows in the CSV, `3` usage error.

## Removing exclusions

`scripts/Remove_Policy_Scope_Exclusion.sh` is the partner to the add script and
takes the same arguments. Everything above — the CSV format, the credential
sources, the dry-run default, the backups, the Self Service guard, the
full-scope PUT, the read-back check — behaves identically.

```bash
# Dry run
./scripts/Remove_Policy_Scope_Exclusion.sh --csv policies.csv --group-id 77

# Apply. Note the token says REMOVE, so an add token cannot be reused here.
./scripts/Remove_Policy_Scope_Exclusion.sh --csv policies.csv --group-id 77 \
    --apply --confirm REMOVE-42-77-none
```

Four differences:

- **A policy without the exclusion is a success, not a failure.** It is counted
  under `Not excluded:` and left alone.
- **Read-back requires the exclusion to be gone**, where the add script requires
  it to be present.
- **The entry is matched by exact id or username.** Removal buffers each
  `<computer_group>` or `<user>` block and discards it only if the whole block
  matches, because once `xmllint` has formatted the XML the id and the element
  that owns it are on different lines — a line-at-a-time filter could delete one
  entry's `<id>` and leave a malformed block behind. It also means group `7` is
  never confused with group `77`.
- **Removing the last entry leaves an empty container** (`<computer_groups/>`),
  which is what Jamf Pro itself writes for an empty exclusion list.

Removal only touches `exclusions`. `<users>` appears under `<limitations>` too,
and a user excluded from the policy and a user the policy is limited to can be
the same person — removing one must not disturb the other.

## Adding and removing limitations

`scripts/Add_Policy_Scope_Limitation.sh` and
`scripts/Remove_Policy_Scope_Limitation.sh` are the limitation equivalents of
the exclusion pair. Same CSV, same credentials, same dry-run default, same
backups, same Self Service guard, same full-scope PUT, same read-back check.

```bash
# Limit policies to an Entra group arriving through the Cloud Identity Provider
./scripts/Add_Policy_Scope_Limitation.sh --csv policies.csv --user-group "Corp Marketing Staff"

# The dry run prints the token; spaces become underscores in it
./scripts/Add_Policy_Scope_Limitation.sh --csv policies.csv --user-group "Corp Marketing Staff" \
    --apply --confirm ADD-LIMIT-42-Corp_Marketing_Staff-none

# Take it back off
./scripts/Remove_Policy_Scope_Limitation.sh --csv policies.csv --user-group "Corp Marketing Staff"
```

### Computer groups are not limitations

Jamf Pro limits a policy's scope by **user, user group, network segment and
iBeacon**. A computer group can be a target or an exclusion, never a
limitation. Passing `--group-id` to either limitation script is refused with a
message pointing at the exclusion pair, because reaching for it out of muscle
memory is the obvious mistake.

### Three criteria

| Flag | Writes | Matches on |
|---|---|---|
| `--username <name>` | `limitations/users/user` | `name` |
| `--user-group <name>` | `limitations/user_groups/user_group` | `name` |
| `--user-group-id <n>` | `limitations/user_groups/user_group` | `id` |

`--user-group` and `--user-group-id` address the same entry by different keys
and cannot be combined; the script refuses rather than adding the group twice.

**Which key to use is not settled.** This estate uses Entra through a Cloud
Identity Provider rather than LDAP, and there is no read-only Jamf access from
here to confirm whether a user group in a policy's scope carries an ID, a name,
or both. `--user-group` (by name) is the default assumption. The read-back
check is what makes that safe to try: if the shape is wrong, the run reports a
failure and prints the restore command instead of claiming success.

To settle it in about thirty seconds, put one policy that already has a user
group limitation through the report script, or dump its scope directly:

```bash
curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/xml" \
  "$JAMF_PRO_URL/JSSResource/policies/id/<id>" \
  | xmllint --xpath '/policy/scope/limitations' - | xmllint --format -
```

### Character set

A username allows letters, digits and `. _ - @`. A user group name also allows
spaces, because Entra group names have them. Both are interpolated into an
XPath predicate, an awk regex and XML, so the set stays narrow — no quoting
scheme survives a value containing a quote character. Regex metacharacters that
do get through, notably `.`, are escaped before the awk match, so a group named
`Corp.Marketing` cannot take out `CorpXMarketing`.

## Adding and removing targets

`scripts/Add_Policy_Scope_Target.sh` and `scripts/Remove_Policy_Scope_Target.sh`
change who a policy applies **to**. Same CSV, credentials, dry-run default,
backups, Self Service guard, full-scope PUT and read-back check as the other
pairs.

```bash
./scripts/Add_Policy_Scope_Target.sh --csv policies.csv --group-id 9
./scripts/Add_Policy_Scope_Target.sh --csv policies.csv --group-id 9 \
    --apply --confirm ADD-TARGET-42-9-none

./scripts/Remove_Policy_Scope_Target.sh --csv policies.csv --group-id 9
```

| Flag | Writes into |
|---|---|
| `--group-id <n>` | `scope/computer_groups` — smart or static |
| `--computer-id <n>` | `scope/computers` |

Buildings and departments are also valid targets. They are not wired up; ask if
you need them.

### Users are not targets

Jamf Pro scopes a policy to **machines** — computers, computer groups,
buildings, departments — and then narrows by person with a limitation. Passing
`--username`, `--user-group` or `--user-group-id` to either target script is
refused with a pointer to the limitation pair.

### Removing the last target is refused by default

This is the one change in the whole set that fails quietly. A policy with no
targets still exists, still looks configured in the UI, and simply stops
reaching any Mac. So `Remove_Policy_Scope_Target.sh` counts what the removal
would leave behind — computers, computer groups, buildings and departments
together — and refuses when the answer is zero:

```
REFUSED  412 (Install Chrome): removing this target would leave the policy with
         no targets at all. --allow-empty-scope overrides.
```

A policy set to **All Computers** is exempt from the check, because it keeps
reaching every Mac whether or not anything is listed. Refusals are counted
under `Skipped/refused:` and the exit code stays 0 — a refusal is the script
working, not failing.

The add script has the mirror-image note: if a policy is already scoped to All
Computers it logs that the new target changes nothing in practice, rather than
silently making a scoping mistake look successful.

### Targets have no wrapper element

`<computer_groups>` and `<computers>` appear **twice** in a scope — once as
targets, directly under `<scope>`, and once inside `<exclusions>`. Targets have
no enclosing element of their own, so the library treats the target region as
everything between `<scope>` and whichever of `<limitations>` or `<exclusions>`
comes first. Without that bound, adding a target group would have appended to
the exclusions list as well. The test set covers it in both directions,
including removing a group that exists only as an exclusion, which correctly
finds nothing in targets.

## Changing a policy's category

`scripts/Set_Policy_Category.sh` refiles the policies in a CSV under a
different category.

```bash
./scripts/Set_Policy_Category.sh --csv policies.csv --category-name "Productivity"
./scripts/Set_Policy_Category.sh --csv policies.csv --category-name "Productivity" \
    --apply --confirm SET-CATEGORY-42-Productivity

./scripts/Set_Policy_Category.sh --csv policies.csv --category-id 7
./scripts/Set_Policy_Category.sh --csv policies.csv --no-category
```

Exactly one of `--category-id`, `--category-name` or `--no-category`. Two would
be ambiguous about which wins; none would be a no-op that still looks like it
ran.

### Two different fields are called "category"

| Field | What it is | This script |
|---|---|---|
| `general/category` | What the policy is filed under in the admin UI | sets this |
| `self_service_categories` | Where the item appears in Self Service, a list with `display_in` and `feature_in` per entry | leaves alone |

They are unrelated. A policy filed under `Apps & Utilities` can display under
`Productivity` in Self Service, and the report script has separate columns for
both. Changing Self Service display categories is a list operation — an
add/remove pair like the scope scripts — and is not built yet.

### This is a replace, not an append

A policy has exactly one category, so setting it discards the old one. The dry
run reports the change as a transition rather than just the new value, which is
what makes a bulk run reviewable:

```
WOULD SET 412 (Install Chrome): Apps & Utilities -> Productivity
```

### The category is checked once, first

Before any policy is read, the script confirms the category exists
(`/JSSResource/categories/id/<n>` or `/name/<name>`). One API call spent there
beats discovering a typo after part of the fleet has been refiled. This needs
**Read Categories** on the API role in addition to Read and Update Policies.

`--no-category` skips the check and writes ID `-1`, which is how Jamf Pro
represents an unassigned category.

### Ampersands

`&` is allowed in `--category-name`, because Jamf category names routinely
contain one, and it is XML-escaped for the payload. Quotes and angle brackets
are rejected — no escaping scheme makes them safe across an XML payload and a
shell argument at once.

Note that the `<general>` element is sent complete, byte-identical except for
the category, for the same reason the scope scripts send the whole `<scope>`: a
PUT carrying a bare `<general><category>` could drop the policy's name, trigger
and every other general setting.

## Enabling and disabling policies

`Enable_Policy.sh` and `Disable_Policy.sh` flip `general/enabled` for every
policy in a CSV. A disabled policy keeps everything it has — scope, category,
triggers, its Self Service entry — and does none of it. Nothing here is
destructive, and the two scripts undo each other.

```bash
# See what would change
./scripts/Disable_Policy.sh --csv policies.csv

# Apply. The dry run prints the token.
./scripts/Disable_Policy.sh --csv policies.csv \
    --apply --confirm DISABLE-3-4a61320c

# Put them back
./scripts/Enable_Policy.sh --csv policies.csv \
    --apply --confirm ENABLE-3-4a61320c
```

Each line reports what the policy runs on, because that is what is being
switched:

```
WOULD DISABLE 412 (Install Chrome): enabled true -> false; runs on: Self Service
```

A policy already in the target state is reported as `ALREADY` and left alone, so
re-running after a partial failure is safe.

### Enabling is the direction that can bite

Disabling can only stop things. Enabling can start them: a policy with an
automatic trigger — Recurring Check-in, Startup, Login, Logout, Network State
Change, Enrollment Complete, or a custom event — begins executing on every Mac
in its scope at the next trigger, with nobody opening Self Service.

`Enable_Policy.sh` refuses those unless you pass `--allow-auto-trigger`:

```
REFUSED  412 (Install Chrome): runs automatically (Self Service, Recurring
         Check-in); enabling it would execute it on every targeted Mac.
         --allow-auto-trigger overrides.
```

`Disable_Policy.sh` **rejects** `--allow-auto-trigger` rather than accepting it
and doing nothing, so nobody can pass it and believe a guard applied.

### The confirmation token hashes the CSV

The other writers put the group or user into the token, which binds it to what
you meant to do. These two have no such argument — the CSV is the whole
instruction — so the token carries a digest of the policy ID list instead:

```
ENABLE-3-4a61320c
       │ └─ first 8 of md5(policy IDs)
       └─── row count
```

A token from a dry run of one CSV will not apply a different CSV, even one with
the same number of rows.

### One `<enabled>`, verified

`<enabled>` is a leaf — `<enabled>true</enabled>` on one line — where every
other field these scripts write is a block with children. That difference had
teeth: the shared replace helper only recognised block and self-closing forms,
so a leaf looked *absent* and a second `<enabled>` was appended. Two of them in
one `<general>`, original value first, and the PUT would have reported success
while changing nothing. Fixed in the library; both scripts also count the
element before sending and refuse a payload that does not carry exactly one.

As everywhere else here, success is the read-back, not the `201`.

## Changing triggers

A policy's triggers are **seven separate fields** under `<general>`, not one
setting: six booleans and one string.

| Field | Flag name | What fires it |
|---|---|---|
| `trigger_checkin` | `checkin` | Recurring Check-in, roughly every 15 minutes |
| `trigger_startup` | `startup` | Boot |
| `trigger_login` | `login` | User login |
| `trigger_logout` | `logout` | Logout — legacy, Jamf Pro's UI no longer exposes it |
| `trigger_network_state_changed` | `network-state-change` | Network change |
| `trigger_enrollment_complete` | `enrollment-complete` | End of enrolment |
| `trigger_other` | `--custom-event` | `jamf policy -event <name>` |

Four scripts, because "add", "remove" and "modify" are three different jobs and
one of them splits in two:

```bash
# One trigger on, one trigger off. Everything else untouched.
./scripts/Add_Policy_Trigger.sh    --csv policies.csv --trigger checkin
./scripts/Remove_Policy_Trigger.sh --csv policies.csv --trigger checkin

# Set the custom event on policies that have none, or clear the named one
./scripts/Add_Policy_Trigger.sh    --csv policies.csv --custom-event installChrome
./scripts/Remove_Policy_Trigger.sh --csv policies.csv --custom-event installChrome

# Rename a custom event
./scripts/Rename_Policy_Trigger.sh --csv policies.csv --from installChrome --to deployChrome

# Declarative: these on, everything else off
./scripts/Set_Policy_Triggers.sh   --csv policies.csv --set checkin,startup
./scripts/Set_Policy_Triggers.sh   --csv policies.csv --set none
```

### Adding a trigger to an enabled policy is refused by default

Turning on an automatic trigger for a policy that is **enabled** puts it into
service on every Mac in its scope at the next trigger, with nobody opening Self
Service. `Add_Policy_Trigger.sh` and `Set_Policy_Triggers.sh` refuse unless you
pass `--allow-auto-trigger`:

```
REFUSED  412 (Install Chrome): policy is enabled; adding Recurring Check-in
         would run it on every targeted Mac. --allow-auto-trigger overrides.
```

A **disabled** policy is never refused — it cannot run whatever its triggers
say. Ordering that gives you a safe path for a risky change: disable, set
triggers, review, enable.

`Remove_Policy_Trigger.sh` rejects `--allow-auto-trigger` rather than accepting
it as a no-op. Removing cannot start anything.

### Only the named custom event is touched

`Remove_Policy_Trigger.sh --custom-event installChrome` skips any policy whose
custom event is something else, rather than clearing it. So does
`Rename_Policy_Trigger.sh --from`, and so does
`Add_Policy_Trigger.sh --custom-event`: a policy that already carries a
*different* event is skipped with a pointer to `Rename_Policy_Trigger.sh`,
because a policy has exactly one custom event and overwriting it would repoint
callers you never named. Clearing or repointing `trigger_other` blindly would
break an unrelated event on any policy in the CSV that happened to have one,
and nothing downstream would show it had gone.

### `--set` does not include the custom event

`Set_Policy_Triggers.sh` turns off every boolean you do not name. It does **not**
touch `trigger_other` unless told to, because a name you forgot to mention is
not the same as a switch you left off:

```bash
--custom-event <event>         set it, on policies with none or already that name
--clear-custom-event <event>   clear it, only where it is exactly that name
neither                        leave it, and say so in the output
```

Every line prints the full before and after, since the whole point is that it
changes things you did not name:

```
WOULD SET 412 (Install Chrome): enabled=false
              Self Service, Login, Custom: installChrome
           -> Self Service, Recurring Check-in, Startup, Custom: installChrome
         note: 412 (Install Chrome) keeps custom event 'installChrome'.
               Pass --clear-custom-event 'installChrome' to clear it.
```

### Renaming a custom event breaks its callers, silently

`jamf policy -event <old>` matching no policy is a **normal, successful**
outcome for the jamf binary — not an error. So a LaunchDaemon, a Setup Manager
step, another policy's script or a runbook that calls the old name simply stops
working, with nothing in any log to say why. Find the callers before renaming.
These scripts change Jamf Pro only; they cannot find them for you.

### `<general><trigger>` is not written

The legacy summary field — `EVENT` or `USER_INITIATED` — is left alone. Jamf Pro
maintains it alongside the booleans, and the booleans are what the admin UI
edits. Each script reports the field if it moves during a write, so the first
real run settles whether Jamf recomputes it. See CLAUDE.md, standing state.

## Showing and hiding in Self Service

`Set_Policy_Self_Service.sh` writes `self_service/use_for_self_service` — the
flag that decides whether a policy appears in Self Service at all.

```bash
./scripts/Set_Policy_Self_Service.sh --csv policies.csv --hide
./scripts/Set_Policy_Self_Service.sh --csv policies.csv --show \
    --apply --confirm SELF-SERVICE-SHOW-3-4a61320c
```

One script, both directions: `--show` and `--hide` are the same write with a
different value. The scope scripts are pairs because add and remove are
genuinely different XML operations; this is not.

**Hiding is not disabling.** A hidden policy keeps its triggers and still runs
on them. Use `Disable_Policy.sh` to stop it running.

**Hiding takes a policy out of scope for every other script here.** They all
skip non-Self-Service policies unless given `--include-non-self-service`. That
is intended, and easy to forget a week later.

The round trip is lossless. Only the one flag is written; display name, icon,
description, Self Service categories and `feature_on_main_page` are carried
through untouched, so `--show` after `--hide` restores the entry exactly as it
was. Verified against a fixture: hide then show is byte-identical to the
original `<self_service>` element.

This is also the one script that **rejects** `--include-non-self-service`. It
sets that very flag, so skipping on it would make `--show` a no-op on precisely
the policies it exists to act on.

If a policy has no `<self_service>` element at all, the script fails rather than
building one. A synthesised element would be PUT as the complete truth for that
element, and would arrive with no display name and no icon.

## Known limits

- **Names, not IDs.** The scope columns carry display names. Two groups with the
  same name are indistinguishable in the report.
- **Smart groups are not expanded.** A target of `Groups: All Managed Macs`
  tells you the group is scoped, not which Macs are currently in it.
- **Serial, one request per policy.** Jamf's guidance is a maximum of five
  concurrent connections; this uses one and is correspondingly slow on a large
  instance. That is the safe trade.
- **Classic API.** Policies are read and written through
  `/JSSResource/policies`. Verified 2026-09-12 against Jamf's OpenAPI specs:
  the modern Jamf Pro API has no policy endpoints at all, and Classic
  `/policies` is not on the deprecation register. The computer-inventory
  deprecation that closed in March 2026 covered `/JSSResource/computers*`
  only. Authentication is the modern Jamf Pro API. See CHANGELOG.md.
- **Report location is a temp directory** unless `--output` is given, so it
  survives the run but not indefinitely. Copy it somewhere real if it matters.
- **User-group limitations can read back empty.** Jamf product issue
  PI-005747: the Classic API sometimes returns an empty `<user_groups/>` under
  `<limitations>` for a policy whose UI shows one. When that happens
  `Add_Policy_Scope_Limitation.sh --user-group` reports FAILED after a 201 and
  says so; check the policy in Jamf Pro before running the restore command.

## Testing

Nothing here has to touch a tenant to be tested. Two suites, both run under a
stock macOS PATH so a Homebrew GNU tool cannot hide a BSD incompatibility:

```bash
# Library functions against XML fixtures (127 checks)
env -i HOME=/nonexistent PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash tests/lib-harness.sh

# Every script, dry run and apply, against a mock Jamf Pro (117 checks)
tests/e2e.sh
```

`tests/mock/mock_jamf.py` is a small local HTTP server that speaks just enough
of the Jamf Pro API (OAuth token, `/v1/auth`, invalidate) and the Classic API
(`/JSSResource/policies` list, `GET`/`PUT` by ID, categories) for the writers'
full path: dry run, confirmation token, apply, read-back. It applies the
documented Classic `PUT` semantics -- each top-level element supplied replaces
the stored one in full -- and recomputes `general/trigger` from the booleans
the way Jamf Pro is believed to. Policy 404 answers 404 and policy 500 answers
an HTML error page, so the fail-closed paths are exercised too. It needs
`python3` on the machine running the tests; the scripts themselves never do.

Both suites exit 1 on any failure and print one line per check. `TESTING.md`
lists every check by group, describes the mock and the fixtures, and records
dated results.

## Files

```
scripts/Generate_Self_Service_Policy_Report.sh   Report: what is in Self Service and who it is scoped to
scripts/Add_Policy_Scope_Exclusion.sh            Write: add an exclusion to the policies in a CSV
scripts/Remove_Policy_Scope_Exclusion.sh         Write: remove an exclusion from the policies in a CSV
scripts/Add_Policy_Scope_Limitation.sh           Write: add a limitation to the policies in a CSV
scripts/Remove_Policy_Scope_Limitation.sh        Write: remove a limitation from the policies in a CSV
scripts/Add_Policy_Scope_Target.sh               Write: add a target to the policies in a CSV
scripts/Remove_Policy_Scope_Target.sh            Write: remove a target from the policies in a CSV
scripts/Set_Policy_Category.sh                   Write: set the category of the policies in a CSV
scripts/Enable_Policy.sh                         Write: enable the policies in a CSV
scripts/Disable_Policy.sh                        Write: disable the policies in a CSV
scripts/Add_Policy_Trigger.sh                    Write: turn one trigger on for the policies in a CSV
scripts/Remove_Policy_Trigger.sh                 Write: turn one trigger off for the policies in a CSV
scripts/Rename_Policy_Trigger.sh                 Write: rename the custom event on the policies in a CSV
scripts/Set_Policy_Triggers.sh                   Write: set the complete trigger set, declaratively
scripts/Set_Policy_Self_Service.sh               Write: show or hide the policies in a CSV in Self Service
scripts/lib/jamf-api-common.sh                   Shared: auth, credentials, policy fetch, CSV reader, XML surgery, getters
tests/lib-harness.sh                             Library functions against fixtures, stock PATH
tests/e2e.sh                                     Every script end to end against the mock, stock PATH
tests/mock/mock_jamf.py                          Local mock of the Jamf Pro and Classic API surface the scripts use
tests/fixtures/                                  Policy XML and CSV fixtures for both suites
TESTING.md                                       How everything is validated: layers, checks, mock, fixtures, results
README.md                                        This file
CHANGELOG.md                                     What changed, when, why
```

Nothing a run produces belongs in this repository. Reports go to a temp
directory; exclusion backups go to `exclusion-backups-*`, which `.gitignore`
covers. Both name internal computer groups, buildings and users.
