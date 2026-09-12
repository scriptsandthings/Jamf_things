# Jamf Pro Self Service policy tools

These scripts report and update Jamf Pro Self Service policies in bulk. The
report shows which groups can see each item, along with its targets, limitations
and exclusions. The writer scripts use that CSV to update scope, category,
status, triggers and Self Service visibility.

Every script uses `scripts/lib/jamf-api-common.sh` for authentication,
credentials, CSV parsing and XML updates. Keep `scripts/lib/` with the scripts
if you copy them elsewhere.

## Prerequisites

Create an API Client in Jamf Pro:

1. `Settings > System > API Roles and Clients > API Roles` — create a role with
   **Read Policies**. Add **Update Policies** for any of the writer scripts,
   and **Read Categories** as well for `Set_Policy_Category.sh`, which checks
   the category exists before it touches a policy.
2. `Settings > System > API Roles and Clients > API Clients` — create a client,
   assign that role, enable it, generate a secret. Copy the secret at creation;
   Jamf Pro will not show it again.

The scripts require `xmllint` and `plutil`, both included with macOS. They run
under the system `/bin/bash` 3.2 and do not require Python or Homebrew.

## Credentials

Credentials are checked in this order. For each setting, the first non-empty
value wins.

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

The script prompts for anything still missing. Client secrets are read without
echoing them or adding them to shell history.

## Run it

```bash
./scripts/Generate_Self_Service_Policy_Report.sh
./scripts/Generate_Self_Service_Policy_Report.sh --output ~/Desktop/self-service.csv
```

When run in a terminal, the script shows a spinner and the policy count. It
prints the report path when finished:

```
Report being generated. File location will appear below once ready.
Checking 412 policies for Self Service policies ...

Self Service policies found: 137 of 412
Report on Self Service policies available here: /var/folders/.../T/self-service-report.AbC123/self-service-policies-20260912-121500.csv
```

If a policy cannot be read, the script names it on stderr, includes it in the
failure count and exits 1. Without `--output`, it writes the report to a new
temporary directory. Run with `--help` to list the columns.

Runtime is roughly one API call per policy, serially. Several hundred policies
takes a few minutes.

Every field is double-quoted per RFC 4180, so names containing commas,
semicolons or quotes survive a round trip through Numbers or Excel. The same
CSV can be passed to any writer with `--csv`.

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

The three scope columns come from the policy's `<scope>` element. Types are
separated by `|`; names within a type are separated by `;`:

```
Groups: All Managed Macs; R&D Pilot | Computers: ACME-MBP-001 | Buildings: 123 Main St
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

Three columns show where the item appears in Self Service. They come from
`<self_service_categories>`, where each category has two flags:

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

`scripts/Add_Policy_Scope_Exclusion.sh` adds exclusions to every policy listed
in a CSV. It accepts a computer group ID, a Jamf Pro user group name or ID, a
username, or any combination of them.

It needs **Update Policies** on the API role in addition to **Read Policies**.
`--user-group` also needs **Read Static User Groups** and **Read Smart User
Groups** for its preflight.

### Excluding a user group from every Self Service policy

Non-Self-Service policies are skipped unless
`--include-non-self-service` is supplied:

```bash
./scripts/Generate_Self_Service_Policy_Report.sh --output policies.csv
./scripts/Add_Policy_Scope_Exclusion.sh --csv policies.csv \
    --user-group 'Contractors'
```

For exclusion scripts, `--user-group` refers to a Jamf Pro user group under
Users > User Groups, stored as `jss_user_groups`. For limitation scripts, the
same flag refers to a directory group resolved through LDAP or a Cloud Identity
Provider.

The script checks that the group exists before writing. An unknown group stops
the run with exit 1 and does not create a backup directory. Jamf Pro 11.32.0
returns 201 for an unknown group but does not store the exclusion, so the
preflight and read-back checks are required.

Re-run the report afterwards to confirm; the exclusion appears in the
**Scope Exclusions** column as `User Groups: Contractors`.

### Dry run and apply

```bash
# See what would change. Writes nothing.
./scripts/Add_Policy_Scope_Exclusion.sh --csv policies.csv --group-id 77

# The dry run ends by printing the exact apply command, including a token
# derived from the policy count and the exclusion:
./scripts/Add_Policy_Scope_Exclusion.sh --csv policies.csv --group-id 77 \
    --apply --confirm APPLY-42-77-none-none
```

The confirmation token changes with the CSV and exclusion arguments. Spaces in
group names become underscores:
`APPLY-2-none-none-TESTING_-_Microsoft_OneDrive`.

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

### Update sequence

1. Fetches `/JSSResource/policies/id/<id>` and fails on a non-200 response.
2. Skips policies that are not in Self Service unless
   `--include-non-self-service` is set.
3. Skips it if the exclusion is already there. Re-running is safe.
4. Writes `policy-<id>-before.xml` to the backup directory.
5. Sends the complete `<scope>` element, changed only by the new node. The
   Classic API replaces any supplied element, so sending a partial exclusion
   tree can remove existing scope data.
6. Reads the policy back and confirms that the exclusion is present.

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

`scripts/Remove_Policy_Scope_Exclusion.sh` takes the same arguments as the add
script. It uses the same CSV format, credentials, dry-run behavior, backups,
Self Service filter, full-scope PUT and read-back check.

```bash
# Dry run
./scripts/Remove_Policy_Scope_Exclusion.sh --csv policies.csv --group-id 77

# Apply. Note the token says REMOVE, so an add token cannot be reused here.
./scripts/Remove_Policy_Scope_Exclusion.sh --csv policies.csv --group-id 77 \
    --apply --confirm REMOVE-42-77-none
```

Removal differs in four ways:

- A policy without the exclusion is counted
  under `Not excluded:` and left alone.
- Read-back requires the exclusion to be gone; the add script requires
  it to be present.
- Entries are matched by exact ID or username. Removal buffers each
  `<computer_group>` or `<user>` block and discards it only if the whole block
  matches, because once `xmllint` has formatted the XML the id and the element
  that owns it are on different lines — a line-at-a-time filter could delete one
  entry's `<id>` and leave a malformed block behind. It also means group `7` is
  never confused with group `77`.
- Removing the last entry leaves an empty container (`<computer_groups/>`),
  which is what Jamf Pro itself writes for an empty exclusion list.

Removal only touches `exclusions`. `<users>` appears under `<limitations>` too,
and a user excluded from the policy and a user the policy is limited to can be
the same person — removing one must not disturb the other.

## Adding and removing limitations

`scripts/Add_Policy_Scope_Limitation.sh` and
`scripts/Remove_Policy_Scope_Limitation.sh` use the same workflow for
limitations.

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

Jamf Pro limits policy scope by user, user group, network segment and iBeacon.
A computer group can be a target or exclusion, but not a limitation. Both
limitation scripts reject `--group-id` and point to the exclusion scripts.

### Three criteria

| Flag | Writes | Matches on |
|---|---|---|
| `--username <name>` | `limitations/users/user` | `name` |
| `--user-group <name>` | `limitations/user_groups/user_group` | `name` |
| `--user-group-id <n>` | `limitations/user_groups/user_group` | `id` |

`--user-group` and `--user-group-id` address the same entry by different keys
and cannot be combined; the script refuses rather than adding the group twice.

This environment uses Entra through a Cloud Identity Provider rather than LDAP.
It has not been confirmed whether a user group in policy scope contains an ID,
a name, or both. Use `--user-group` by name unless your tenant shows otherwise.
If Jamf does not retain the value, read-back fails and the script prints the
restore command.

To check your tenant, inspect a policy that already has a user-group limitation:

```bash
curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/xml" \
  "$JAMF_PRO_URL/JSSResource/policies/id/<id>" \
  | xmllint --xpath '/policy/scope/limitations' - | xmllint --format -
```

### Character set

Usernames allow letters, digits and `. _ - @`; group names also allow spaces.
Other characters are rejected because the values are used in XPath, awk and
XML. Regex metacharacters such as `.` are escaped before matching.

## Adding and removing targets

`scripts/Add_Policy_Scope_Target.sh` and `scripts/Remove_Policy_Scope_Target.sh`
change which computers a policy applies to. They use the same CSV, credentials,
dry-run behavior, backups and verification as the other scope scripts.

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

Jamf also supports buildings and departments as targets, but these scripts do
not expose them.

### Users are not targets

Targets are computers, computer groups, buildings or departments. User and
user-group filters are limitations. The target scripts reject `--username`,
`--user-group` and `--user-group-id` and point to the limitation scripts.

### Removing the last target is refused by default

A policy with no targets remains configured but reaches no Macs.
`Remove_Policy_Scope_Target.sh` counts the computers, computer groups, buildings
and departments that would remain and refuses to remove the last target:

```
REFUSED  412 (Install Chrome): removing this target would leave the policy with
         no targets at all. --allow-empty-scope overrides.
```

A policy set to All Computers is exempt because it still reaches every Mac.
Refusals are counted under `Skipped/refused:` and do not change the exit code.

If a policy already targets All Computers, the add script reports that the new
target has no practical effect.

### Targets have no wrapper element

`<computer_groups>` and `<computers>` appear twice in a scope: once as targets
directly under `<scope>`, and once under `<exclusions>`. Targets have no wrapper
element. The library therefore limits target updates to the area between
`<scope>` and the first `<limitations>` or `<exclusions>` element. Tests cover
adding and removing targets without changing exclusions.

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

Pass exactly one of `--category-id`, `--category-name` or `--no-category`.

### Two different fields are called "category"

| Field | What it is | This script |
|---|---|---|
| `general/category` | What the policy is filed under in the admin UI | sets this |
| `self_service_categories` | Where the item appears in Self Service, a list with `display_in` and `feature_in` per entry | leaves alone |

These fields are independent. A policy filed under `Apps & Utilities` can
display under `Productivity` in Self Service. The report includes both fields.
These scripts do not update Self Service display categories.

### This is a replace, not an append

A policy has one category, so setting it replaces the old one. The dry run
shows both values:

```
WOULD SET 412 (Install Chrome): Apps & Utilities -> Productivity
```

### The category is checked once, first

Before reading any policy, the script confirms that the category exists at
`/JSSResource/categories/id/<n>` or `/name/<name>`. This requires Read
Categories in addition to Read Policies and Update Policies.

`--no-category` skips the check and writes ID `-1`, which is how Jamf Pro
represents an unassigned category.

### Ampersands

`--category-name` accepts `&` and escapes it in XML. Quotes and angle brackets
are rejected.

The script sends the complete `<general>` element with only the category
changed. Sending a partial `<general>` element could remove the policy name,
triggers and other settings.

## Enabling and disabling policies

`Enable_Policy.sh` and `Disable_Policy.sh` change `general/enabled` for every
policy in a CSV. Disabling a policy preserves its scope, category, triggers and
Self Service settings.

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

Each result includes the policy's triggers:

```
WOULD DISABLE 412 (Install Chrome): enabled true -> false; runs on: Self Service
```

A policy already in the requested state is reported as `ALREADY` and skipped.

### Automatic triggers

Enabling a policy with an automatic trigger can run it on every Mac in scope at
the next check-in, startup, login, network change, enrollment completion or
custom event.

`Enable_Policy.sh` refuses those unless you pass `--allow-auto-trigger`:

```
REFUSED  412 (Install Chrome): runs automatically (Self Service, Recurring
         Check-in); enabling it would execute it on every targeted Mac.
         --allow-auto-trigger overrides.
```

`Disable_Policy.sh` rejects `--allow-auto-trigger` because the flag does not
apply when disabling a policy.

### The confirmation token hashes the CSV

Enable and disable tokens include a digest of the policy IDs because the CSV is
the complete change request:

```
ENABLE-3-4a61320c
       │ └─ first 8 of md5(policy IDs)
       └─── row count
```

The token cannot be reused with a different CSV, even if it has the same row
count.

### One `<enabled>`, verified

The shared XML helper handles leaf elements such as
`<enabled>true</enabled>`. Both scripts also verify that the payload contains
exactly one `<enabled>` element and confirm the final value with a read-back.

## Changing triggers

A policy stores triggers as six fields under `<general>`: five booleans and one
custom-event string.

| Field | Flag name | What fires it |
|---|---|---|
| `trigger_checkin` | `checkin` | Recurring Check-in, roughly every 15 minutes |
| `trigger_startup` | `startup` | Boot |
| `trigger_login` | `login` | User login |
| `trigger_network_state_changed` | `network-state-change` | Network change |
| `trigger_enrollment_complete` | `enrollment-complete` | End of enrolment |
| `trigger_other` | `--custom-event` | `jamf policy -event <name>` |

Jamf Pro no longer supports a logout trigger. In Jamf Pro 11.32.0, a PUT with
`<trigger_logout>true</trigger_logout>` returns 201 but discards the field.
`--trigger logout` and `--set logout` are therefore rejected.

Four scripts cover individual and declarative trigger changes:

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

Turning on an automatic trigger for an enabled policy can run it on every Mac in
scope. `Add_Policy_Trigger.sh` and `Set_Policy_Triggers.sh` require
`--allow-auto-trigger` for that change:

```
REFUSED  412 (Install Chrome): policy is enabled; adding Recurring Check-in
         would run it on every targeted Mac. --allow-auto-trigger overrides.
```

A disabled policy can be changed without that flag. To change triggers without
starting the policy, disable it first and enable it after review.

`Remove_Policy_Trigger.sh` rejects `--allow-auto-trigger` because removing a
trigger cannot start a policy.

### Only the named custom event is touched

`Remove_Policy_Trigger.sh --custom-event installChrome` only clears an exact
match. `Rename_Policy_Trigger.sh --from` follows the same rule.
`Add_Policy_Trigger.sh --custom-event` skips policies that already have a
different event and points to the rename script. A policy can have only one
custom event.

### `--set` does not include the custom event

`Set_Policy_Triggers.sh` turns off every boolean trigger not named in `--set`.
It leaves `trigger_other` alone unless one of these options is supplied:

```bash
--custom-event <event>         set it, on policies with none or already that name
--clear-custom-event <event>   clear it, only where it is exactly that name
neither                        leave it, and say so in the output
```

Each result prints the full before and after state:

```
WOULD SET 412 (Install Chrome): enabled=false
              Self Service, Login, Custom: installChrome
           -> Self Service, Recurring Check-in, Startup, Custom: installChrome
         note: 412 (Install Chrome) keeps custom event 'installChrome'.
               Pass --clear-custom-event 'installChrome' to clear it.
```

### Renaming a custom event breaks its callers, silently

`jamf policy -event <old>` exits successfully when no policy matches. A
LaunchDaemon, Setup Manager step, script or runbook using the old event can stop
working without an error. Find those callers before renaming. These scripts
only update Jamf Pro.

### `<general><trigger>` is not written

The scripts leave the legacy summary field (`EVENT` or `USER_INITIATED`) alone.
Jamf Pro maintains it alongside the boolean fields used by the admin UI. A
script reports the field if Jamf changes it during a write.

## Showing and hiding in Self Service

`Set_Policy_Self_Service.sh` writes `self_service/use_for_self_service` — the
flag that decides whether a policy appears in Self Service at all.

```bash
./scripts/Set_Policy_Self_Service.sh --csv policies.csv --hide
./scripts/Set_Policy_Self_Service.sh --csv policies.csv --show \
    --apply --confirm SELF-SERVICE-SHOW-3-4a61320c
```

Use `--show` or `--hide` to set the value.

A hidden policy keeps its triggers and can still run. Use `Disable_Policy.sh`
to stop it.

Other scripts skip a hidden policy unless
`--include-non-self-service` is supplied.

Only `use_for_self_service` changes. Display name, icon, description, categories
and `feature_on_main_page` are preserved. Fixture tests confirm that hiding and
then showing a policy restores the original `<self_service>` element.

This script rejects `--include-non-self-service` because it changes the flag
that option normally bypasses.

If a policy has no `<self_service>` element, the script fails. Creating a new
element would omit settings such as the display name and icon.

## Known limits

- The scope columns contain display names rather than IDs. Two groups with the
  same name are indistinguishable in the report.
- Smart groups are not expanded. A target of `Groups: All Managed Macs`
  tells you the group is scoped, not which Macs are currently in it.
- Requests are serial. Jamf's guidance is a maximum of five
  concurrent connections; this uses one and is correspondingly slow on a large
  instance. That is the safe trade.
- Policies are read and written through the Classic API at
  `/JSSResource/policies`. Verified 2026-09-12 against Jamf's OpenAPI specs:
  the modern Jamf Pro API has no policy endpoints at all, and Classic
  `/policies` is not on the deprecation register. The computer-inventory
  deprecation that closed in March 2026 covered `/JSSResource/computers*`
  only. Authentication is the modern Jamf Pro API. See CHANGELOG.md.
- Reports go to a temporary directory unless `--output` is given. The directory
  is not intended for permanent storage.
- User-group limitations can read back empty. Jamf product issue
  PI-005747: the Classic API sometimes returns an empty `<user_groups/>` under
  `<limitations>` for a policy whose UI shows one. When that happens
  `Add_Policy_Scope_Limitation.sh --user-group` reports FAILED after a 201 and
  says so; check the policy in Jamf Pro before running the restore command.
- A directory service is required for limitations. `limitations/user_groups`
  and `limitations/users` resolve against LDAP or a Cloud Identity Provider. On
  a tenant with neither, every write there is answered `201` and stored nowhere,
  and the writers correctly report FAILED. Exclusions by Jamf Pro user group
  (`--user-group` on the exclusion pair) need no directory — different object.
- A `409` from Jamf may still change the policy. If a policy carries a scope
  entry the server can no longer resolve — typically a directory group deleted
  after it was scoped — a write answers `409`, **applies the change anyway**, and
  **drops the unresolvable entry**. The writers log a WARNING naming the backup
  and still read back, rather than reporting a bare failure. Compare against
  `policy-<id>-before.xml` before continuing; entries you did not name may be
  gone. Wire-checked 2026-09-12.

## Testing

There are three test suites. The first two do not contact a Jamf tenant and run
with the stock macOS toolchain:

```bash
# Library functions against XML fixtures (137 checks)
env -i HOME=/nonexistent PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash tests/lib-harness.sh

# Every script, dry run and apply, against a mock Jamf Pro (135 checks)
tests/e2e.sh

# Every flag of every script against a LIVE Jamf Pro (161 checks). Needs the
# three JAMF_PRO_* variables; tests/live/guard.sh refuses any host but the
# homelab, and everything it creates is named ZZ-LIVETEST-* and deleted.
tests/live/every-flag.sh
```

The live suite uses the same stock PATH and macOS `/bin/bash` 3.2.

`tests/mock/mock_jamf.py` provides the Jamf Pro API and Classic API endpoints
used by the scripts, including OAuth, policy GET/PUT operations and categories.
It models full-element replacement, trigger recomputation, scope validation,
partial updates returned with 409 and the `limit_to_users` union. It also
returns representative 404 and HTML 500 responses. The mock requires Python 3;
the policy scripts do not.

Each suite exits 1 on failure and prints one line per check. `TESTING.md` lists
the checks, fixtures and dated results.

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

Generated reports and backups may contain internal computer groups, buildings
and usernames. Reports go to a temporary directory by default, and `.gitignore`
excludes `exclusion-backups-*`.
