# Self Service policy scopes

`scripts/Generate_Self_Service_Policy_Report.sh` walks every policy in Jamf Pro,
keeps the ones flagged as Self Service policies, and writes a TSV report of what
they are and **who they are scoped to**.

The scope columns are the point. Jamf Pro's own policy list will tell you a
policy exists; it will not tell you, across 400 policies in one view, which
groups see which Self Service item and which groups are excluded.

## Prerequisites

An **API Client**, not a user account. In Jamf Pro:

1. `Settings > System > API Roles and Clients > API Roles` — create a role with
   **Read Policies**. Nothing else is needed; the script only reads.
2. `Settings > System > API Roles and Clients > API Clients` — create a client,
   assign that role, enable it, generate a secret. Copy the secret at creation;
   Jamf Pro will not show it again.

Locally: `xmllint` and `plutil`, both base macOS. No Python, no Homebrew bash —
the script is bash 3.2 clean and runs under `/bin/bash`.

## Credentials

Three sources, checked in this order. First non-empty value wins.

```bash
# 1. Hardcoded at the top of the script (jamfpro_url, jamfpro_client_id,
#    jamfpro_client_secret). Convenient, and the reason this repo's .gitignore
#    matters -- do not commit a filled-in copy.

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
```

It prints a spinner, the policy count it is working through, and finally the
path to the report:

```
Report being generated. File location will appear below once ready.
Checking 412 policies for Self Service policies ...

Report on Self Service policies available here: /var/folders/.../T/tmp.AbC123.tsv
```

Runtime is roughly one API call per policy, serially. Several hundred policies
takes a few minutes.

Open the TSV in Numbers or Excel, or `column -t -s $'\t'` it in a terminal.

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
Groups: All Managed Macs; R&D Pilot | Computers: ACME-MBP-001 | Buildings: 123 Main St
```

- **Targets** — `All Computers` when scoped to everything, otherwise computer
  groups, individual computers, buildings, departments. `No targets` when a
  policy is scoped to nothing at all (it will never run; worth investigating).
- **Limitations** — users, user groups, LDAP groups (Jamf Pro's "limit to users
  in groups", stored outside the limitations element), network segments,
  iBeacons. `None` when unlimited.
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

## Known limits

- **Names, not IDs.** The scope columns carry display names. Two groups with the
  same name are indistinguishable in the report.
- **Smart groups are not expanded.** A target of `Groups: All Managed Macs`
  tells you the group is scoped, not which Macs are currently in it.
- **Serial, one request per policy.** Jamf's guidance is a maximum of five
  concurrent connections; this uses one and is correspondingly slow on a large
  instance. That is the safe trade.
- **Classic API.** Policies are read from `/JSSResource/policies`. That is still
  supported — the Classic API deprecation that closed in March 2026 covered
  `/JSSResource/computers*` only. Authentication is the modern Jamf Pro API.
- **Report location is a temp file.** `mktemp` output, so it survives the run
  but not indefinitely. Copy it somewhere real if it matters.

## Files

```
scripts/Generate_Self_Service_Policy_Report.sh   The script
README.md                                        This file
CHANGELOG.md                                     What changed, when, why
```

Reports are written to a temp directory and do not belong in this repository —
they name internal computer groups, buildings and users.
