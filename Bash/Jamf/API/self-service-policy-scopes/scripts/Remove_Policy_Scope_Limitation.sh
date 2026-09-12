#!/bin/bash

# Removes a scope limitation -- a user by username, or a user group by name or
# by ID -- from every Jamf Pro policy listed in a CSV file. Partner to
# Add_Policy_Scope_Limitation.sh; same arguments, same safety model.
#
# Computer groups are NOT valid limitations. Jamf Pro limits a policy's scope by
# user, user group, network segment and iBeacon. If you want to keep a computer
# group out of a policy, that is an exclusion -- use Add_Policy_Scope_Exclusion.sh.
#
# UNVERIFIED: whether a user group in a policy's scope carries <id>, <name> or
# both on this instance (Entra through a Cloud Identity Provider, not LDAP).
# --user-group by name is the assumption. The first real run settles it, and
# README.md carries the one curl that checks a policy's <limitations> directly.
#
# Authentication is OAuth client credentials against the Jamf Pro API. The policy
# read and write themselves are Classic API, because the Jamf Pro API has no
# policy endpoints.
#
# Prerequisites, in Jamf Pro:
#   Settings > System > API Roles and Clients
#     1. Create an API Role with "Read Policies" AND "Update Policies".
#     2. Create an API Client, assign that role, enable it, generate a secret.
#
# This script MODIFIES PRODUCTION POLICIES. It is dry-run by default. A real run
# needs both --apply and --confirm with the token the dry run prints.

# -u only. No -e on purpose: the library functions signal failure with a
# non-zero status and every caller checks it and logs FAILED for that policy.
# -e would abort the whole run on the first policy that cannot be edited.
set -u

SCRIPT_VERSION="1.0.0"

# Set default exit code
exitCode=0

# Shared Jamf Pro API helpers: curl defaults, the OAuth token lifecycle,
# credential resolution, the CSV reader and the scope entry functions.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
JAMF_API_COMMON="${SCRIPT_DIR}/lib/jamf-api-common.sh"

if [[ ! -f "$JAMF_API_COMMON" ]]; then
	echo "ERROR! Missing ${JAMF_API_COMMON}"
	echo "       This script is not standalone; keep lib/ next to it."
	exit 1
fi

# shellcheck source=lib/jamf-api-common.sh
. "$JAMF_API_COMMON"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
	cat <<'EOF'
Remove a scope limitation from the Jamf Pro policies listed in a CSV.

Usage:
  Remove_Policy_Scope_Limitation.sh --csv <file> [--username <name>]
                                    [--user-group <name>] [--user-group-id <n>] [options]

Required:
  --csv <file>             CSV of policy IDs. The policy ID is the first column.
                           A header row, blank lines and lines beginning with #
                           are skipped. Comma or tab separated.

At least one of:
  --username <name>        User to un-limit, by username. Allowed characters:
                           letters, digits, and . _ - @
  --user-group <name>      User group to un-limit, by name. Allowed characters:
                           letters, digits, spaces, and . _ - @
                           This is the option for an Entra group arriving
                           through a Cloud Identity Provider.
  --user-group-id <n>      User group to un-limit, by Jamf Pro ID. Use this only
                           if you have confirmed your instance records an ID for
                           the group in a policy's scope; otherwise use
                           --user-group.

Note: computer groups cannot be limitations. Jamf Pro limits by user, user
group, network segment and iBeacon. To keep a computer group out of a policy,
use Remove_Policy_Scope_Exclusion.sh instead.

Options:
  --apply                  Actually write. Without it, nothing is modified.
  --confirm <token>        Required with --apply. The dry run prints the token.
  --backup-dir <dir>       Where to write per-policy backups.
                           Default: ./limitation-backups-YYYYmmdd-HHMMSS
  --log <file>             Log file. Default: <backup-dir>/run.log
  --delay <seconds>        Pause between policies. Default: 0
  --include-non-self-service
                           Also modify policies that are not Self Service
                           policies. Off by default: this script exists for the
                           Self Service workflow, and a CSV with a stray ID in
                           it should not silently rescope a background policy.
  --help                   This text.

Exit codes:
  0  every policy in the CSV was already clear of the limitation or was updated
  1  at least one policy failed, or the run could not start: library
     missing, no API token, or the backup directory not writable
  2  nothing to do (no usable rows in the CSV)
  3  usage error
  130  interrupted by a signal; the token is revoked and nothing further is written
EOF
}

log_line() {
	# $1 = message. Goes to stdout and, once it exists, the log file.
	local message="$1"
	echo "$message"
	if [[ -n "${log_file:-}" ]] && [[ -f "${log_file}" ]]; then
		echo "$(date '+%Y-%m-%d %I:%M:%S %p') ${message}" >> "$log_file"
	fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

csv_file=""
username=""
user_group_name=""
user_group_id=""
apply_changes="no"
confirm_token_supplied=""
backup_dir=""
log_file=""
inter_policy_delay=0
include_non_self_service="no"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--csv)           csv_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--username)      username="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--user-group)    user_group_name="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--user-group-id) user_group_id="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--apply)         apply_changes="yes"; shift ;;
		--confirm)       confirm_token_supplied="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--backup-dir)    backup_dir="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--log)           log_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--delay)         inter_policy_delay="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--include-non-self-service) include_non_self_service="yes"; shift ;;
		--help|-h)       usage; exit 0 ;;
		--group-id)
			# Muscle memory from the exclusion scripts. Say why rather than
			# writing a computer group into a limitation, which Jamf Pro would
			# either reject or silently ignore.
			echo "ERROR! --group-id is not valid here. Computer groups cannot be limitations."
			echo "       Jamf Pro limits a policy's scope by user, user group, network segment"
			echo "       and iBeacon. Did you mean --user-group, or Remove_Policy_Scope_Exclusion.sh?"
			exit 3
			;;
		*)               echo "ERROR! Unknown argument: $1"; echo; usage; exit 3 ;;
	esac
done

if [[ -z "$csv_file" ]]; then
	echo "ERROR! --csv is required."; echo; usage; exit 3
fi

if [[ ! -f "$csv_file" ]]; then
	echo "ERROR! CSV not found: $csv_file"; exit 3
fi

if [[ -z "$username" ]] && [[ -z "$user_group_name" ]] && [[ -z "$user_group_id" ]]; then
	echo "ERROR! Give at least one of --username, --user-group or --user-group-id."; echo; usage; exit 3
fi

if [[ -n "$user_group_name" ]] && [[ -n "$user_group_id" ]]; then
	echo "ERROR! Use --user-group or --user-group-id, not both."
	echo "       They address the same entry by different keys; writing both would"
	echo "       add the group twice."
	exit 3
fi

# Values are interpolated into an XPath predicate, into an awk regex and into
# XML. Restricting the character set is what keeps all three safe -- no quoting
# scheme survives a value containing a quote character.
if [[ -n "$username" ]]; then
	if ! echo "$username" | grep -Eq '^[A-Za-z0-9._@-]+$'; then
		echo "ERROR! --username may contain only letters, digits and . _ - @"
		echo "       Got: $username"
		exit 3
	fi
fi

if [[ -n "$user_group_name" ]]; then
	if ! echo "$user_group_name" | grep -Eq '^[A-Za-z0-9 ._@-]+$'; then
		echo "ERROR! --user-group may contain only letters, digits, spaces and . _ - @"
		echo "       Got: $user_group_name"
		exit 3
	fi
fi

# An ID is interpolated the same way as the names above; digits only keeps it
# safe, and a non-number could never match a real Jamf Pro ID anyway.
if [[ -n "$user_group_id" ]]; then
	case "$user_group_id" in
		''|*[!0-9]*) echo "ERROR! --user-group-id must be a number: $user_group_id"; exit 3 ;;
	esac
fi

# ''|*[!0-9]* rejects the empty string and anything containing a non-digit:
# the portable bash 3.2 integer test.
case "$inter_policy_delay" in
	''|*[!0-9]*) echo "ERROR! --delay must be a whole number of seconds."; exit 3 ;;
esac

if [[ -z "$backup_dir" ]]; then
	backup_dir="./limitation-backups-$(date '+%Y%m%d-%H%M%S')"
fi

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------

# Fills jamfpro_url, jamfpro_client_id and jamfpro_client_secret from, in
# order: a value already exported by the caller, the com.github.jamfpro-info
# preference file, the JAMF_PRO_URL / JAMF_PRO_CLIENT_ID /
# JAMF_PRO_CLIENT_SECRET environment variables, or an interactive prompt.
# Blocks on a TTY when nothing is set, so unattended runs need the
# preference file or the environment. See the library.
ResolveJamfProCredentials

# ---------------------------------------------------------------------------
# Per-policy work
# ---------------------------------------------------------------------------

policies_total=0
policies_updated=0
policies_already=0
policies_skipped=0
policies_failed=0

# Processes one policy end to end: GET, guard checks, edit, backup, dry-run
# or PUT, read-back. Arguments: $1 policy ID, plus the kind and value in the
# scripts that take more than one selector. Prints nothing itself; every
# outcome goes through log_line. Increments exactly one of policies_updated,
# policies_already, policies_skipped or policies_failed, writes
# policy-<id>-before.xml and policy-<id>-payload.xml into backup_dir, and
# never exits -- a failure on one policy must not stop the run.
ProcessPolicy() {

	local policy_id="$1"
	local kind="$2"          # user | group-name | group-id
	local value="$3"
	local container
	local entry
	local match_element
	local policy_xml
	local http_code
	local self_service_flag
	local policy_name
	local existing
	local formatted_xml
	local scope_xml
	local new_scope
	local payload
	local verify_xml
	local verify_count

	# Map the kind onto Classic API element names: the container under
	# <limitations>, the per-entry element inside it, and the child element the
	# value is matched on at read-back. The Add_ half of this pair also builds
	# the node to insert. Whether a user group carries <name>, <id> or both is
	# UNVERIFIED (see the header); group-name is the assumption.
	case "$kind" in
		user)
			container="users"
			entry="user"
			match_element="name"
			;;
		group-name)
			container="user_groups"
			entry="user_group"
			match_element="name"
			;;
		group-id)
			container="user_groups"
			entry="user_group"
			match_element="id"
			;;
	esac

	# GET the whole policy. FetchPolicyXML (library) accepts only an HTTP 200
	# whose body parses as XML, so a 404, a 401 after a token hiccup, or a
	# proxy's HTML error page cannot reach the counting below -- xmllint
	# scores a count over garbage as 0, and 0 is what the Remove_ scripts read
	# as "already gone". On failure it prints the reason instead of a body.
	# The token is renewed here, not inside the helper: $( ) is a subshell.
	CheckAndRenewAPIToken
	if ! policy_xml=$(FetchPolicyXML "$policy_id"); then
		log_line "FAILED   ${policy_id}: ${policy_xml}"
		policies_failed=$((policies_failed + 1))
		return
	fi

	# Entity-decoded for the log: a policy named "Foo & Bar" reads as such.
	policy_name=$(GetPolicyName "$policy_xml")
	self_service_flag=$(echo "$policy_xml" | xmllint --xpath '/policy/self_service/use_for_self_service/text()' - 2>/dev/null)

	if [[ "$include_non_self_service" = "no" ]] && [[ "$self_service_flag" != "true" ]]; then
		log_line "SKIPPED  ${policy_id} (${policy_name}): not a Self Service policy. --include-non-self-service overrides."
		policies_skipped=$((policies_skipped + 1))
		return
	fi

	existing=$(CountScopeEntry "$policy_xml" limitations "$container" "$entry" "$match_element" "$value")
	# A user-group limitation lives in two places: limitations/user_groups
	# (what this script writes) and scope/limit_to_users/user_groups, where
	# Jamf's own CLI writes it and which it treats as the source of the
	# mirror. A group named in either place is present, so neither a
	# pre-check nor a read-back is fooled by a mirror that has not caught up.
	# Only --user-group by name can be checked there: entries are bare names.
	if [[ "$container" = "user_groups" ]] && [[ "$match_element" = "name" ]]; then
		existing=$(( existing + $(CountLimitToUsersGroup "$policy_xml" "$value") ))
	fi
	if [[ "$existing" -eq 0 ]]; then
		log_line "ALREADY  ${policy_id} (${policy_name}): limitation is not on this policy, nothing to do."
		policies_already=$((policies_already + 1))
		return
	fi

	# Normalise before line-oriented editing. The API's own formatting is not
	# guaranteed, and the awk insertion is line-based.
	formatted_xml=$(echo "$policy_xml" | xmllint --format - 2>/dev/null)
	if [[ -z "$formatted_xml" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): response did not parse as XML."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# Unanchored on purpose: <scope> occurs once per policy and is not a
	# prefix of any other element name, so the loose range is safe here. The
	# <general> extracts in the other scripts are anchored because <general>
	# is not unique in the same way.
	scope_xml=$(echo "$formatted_xml" | awk '/<scope>/,/<\/scope>/')
	if [[ -z "$scope_xml" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): no <scope> element in the policy."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# The if tests the substitution's status, which is the library function's
	# exit code, so a node that could not be placed is caught here, not later.
	if ! new_scope=$(RemoveScopeEntry "$scope_xml" limitations "$container" "$entry" "$match_element" "$value") ||
	   [[ -z "$new_scope" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): could not remove the limitation from the scope."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# Only <scope> is sent. The Classic API leaves every element the request
	# does not mention untouched, so <general> and <self_service> are not at
	# risk; <scope> itself goes back complete, which is the whole point of
	# editing the formatted copy rather than sending a fragment.
	payload="<?xml version=\"1.0\" encoding=\"UTF-8\"?><policy>${new_scope}</policy>"

	# The payload must survive a parse before it is sent anywhere.
	if ! echo "$payload" | xmllint --noout - 2>/dev/null; then
		log_line "FAILED   ${policy_id} (${policy_name}): generated payload is not well-formed XML."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# The "before" file is written once per policy per run. The scope scripts
	# call this function more than once for the same policy when several values
	# are on the command line, and the second pass must not overwrite the
	# pre-run state with the state after the first PUT -- that would make the
	# first change unrecoverable from the backup. The payload file is the last
	# payload sent, which is the one a failed read-back refers to.
	if [[ ! -e "${backup_dir}/policy-${policy_id}-before.xml" ]]; then
		echo "$formatted_xml" > "${backup_dir}/policy-${policy_id}-before.xml"
	fi
	echo "$payload"       > "${backup_dir}/policy-${policy_id}-payload.xml"

	if [[ "$apply_changes" != "yes" ]]; then
		log_line "WOULD REMOVE ${policy_id} (${policy_name}): ${match_element} ${value} from limitations/${container}"
		policies_updated=$((policies_updated + 1))
		return
	fi

	CheckAndRenewAPIToken

	# PutPolicyXML (library) sends the payload and prints the HTTP status. It
	# retries a 429 (honouring Retry-After) or a curl transport failure up to
	# three times; the payload is a complete element, so a repeat is harmless.
	# It runs in $( ), which is why the token was renewed above, not inside.
	http_code=$(PutPolicyXML "$policy_id" "$payload")

	# The Classic API answers a successful PUT with 201 Created; 200 is
	# accepted as well in case a proxy or a later version normalises it. The
	# status is not success -- the read-back below is.
	if [[ "$http_code" != "201" ]] && [[ "$http_code" != "200" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): PUT returned HTTP ${http_code}$(DescribeHTTPStatus "$http_code")"
		policies_failed=$((policies_failed + 1))
		return
	fi

	# Read back. An accepted PUT is not proof the element landed where intended,
	# and this is the check that proves the entry is gone rather than
	# reporting a false success.
	CheckAndRenewAPIToken
	if ! verify_xml=$(FetchPolicyXML "$policy_id"); then
		# The PUT may well have landed; what failed is proving it. Fail closed
		# rather than count from an empty or non-XML body: xmllint scores that
		# as 0, and 0 is exactly what a removal or a clear reads as success.
		# On failure verify_xml holds the helper's one-line reason.
		log_line "FAILED   ${policy_id} (${policy_name}): PUT returned ${http_code} but the read-back failed: ${verify_xml}"
		log_line "         Check the policy in Jamf Pro before restoring. Backup: ${backup_dir}/policy-${policy_id}-before.xml"
		policies_failed=$((policies_failed + 1))
		return
	fi

	verify_count=$(CountScopeEntry "$verify_xml" limitations "$container" "$entry" "$match_element" "$value")
	# Same two-place rule as the pre-check above.
	if [[ "$container" = "user_groups" ]] && [[ "$match_element" = "name" ]]; then
		verify_count=$(( verify_count + $(CountLimitToUsersGroup "$verify_xml" "$value") ))
	fi

	if [[ "$verify_count" -eq 0 ]]; then
		log_line "UPDATED  ${policy_id} (${policy_name}): removed ${match_element} ${value} from limitations/${container}"
		policies_updated=$((policies_updated + 1))
	else
		log_line "FAILED   ${policy_id} (${policy_name}): PUT returned ${http_code} but the limitation is still present on read-back."
		# The restore command needs a Bearer token: Basic auth stopped working
		# for anything but minting a token in Jamf Pro 11.17, so a bare curl
		# would answer 401. Timeouts are included for the same reason every
		# curl in this directory carries them.
		log_line "         Restore with: curl --connect-timeout 15 --max-time 30 -X PUT -H \"Authorization: Bearer \$TOKEN\" -H \"Content-Type: application/xml\" --data-binary @${backup_dir}/policy-${policy_id}-before.xml \"${jamfpro_url}/JSSResource/policies/id/${policy_id}\""
		log_line "         where TOKEN is an access token from POST ${jamfpro_url}/api/v1/oauth/token (grant_type=client_credentials)."
		policies_failed=$((policies_failed + 1))
	fi

}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

policy_ids=$(ReadPolicyIDsFromCSV "$csv_file")

if [[ -z "$policy_ids" ]]; then
	echo "ERROR! No policy IDs found in ${csv_file}."
	echo "       Expected the policy ID in the first column."
	exit 2
fi

# Count lines. The list is newline separated with no trailing blank, and
# grep -c ^ counts every line where wc -l would need trimming.
policies_total=$(echo "$policy_ids" | grep -c ^)

# The confirmation token is derived from the run, so it cannot be guessed ahead
# of a dry run, reused against a different CSV or a different limitation, or
# pasted in from one of the exclusion scripts.
confirm_token="REMOVE-LIMIT-${policies_total}-${user_group_name:-${user_group_id:-none}}-${username:-none}"
# Group names may contain spaces; the token has to be a single shell word.
confirm_token=$(echo "$confirm_token" | tr ' ' '_')

if [[ "$apply_changes" = "yes" ]] && [[ "$confirm_token_supplied" != "$confirm_token" ]]; then
	echo "ERROR! --apply needs a matching --confirm token."
	echo "       Expected: --confirm ${confirm_token}"
	if [[ -n "$confirm_token_supplied" ]]; then
		echo "       Got:      --confirm ${confirm_token_supplied}"
	fi
	exit 3
fi

# Traps first, then the token, then anything on disk.
#
# The EXIT trap (0) revokes whatever token was issued, however the script ends.
# The signal traps must exit explicitly: a handler that only revoked the token
# would let the per-policy loop resume after Ctrl-C, mint a fresh token on the
# next CheckAndRenewAPIToken, and keep writing to the remaining policies. exit
# fires the EXIT trap, so the token is still revoked. 130 is the conventional
# status for a run ended by a signal.
trap 'InvalidateAPIToken' 0
trap 'exit 130' 1 2 3 15

# Authenticate before creating the backup directory, so a wrong URL or secret
# does not leave an empty backup directory and log behind for every attempt.
GetJamfProAPIToken

# Fatal before any policy is touched; the token is revoked by the EXIT trap.
mkdir -p "$backup_dir" || { echo "ERROR! Cannot create backup directory: $backup_dir"; exit 1; }

# Every log_line also lands in run.log inside the backup directory unless
# --log pointed somewhere else. The file is truncated here so log_line, which
# only appends once the file exists, starts writing from the next call.
if [[ -z "$log_file" ]]; then
	log_file="${backup_dir}/run.log"
fi
: > "$log_file"

# Run header: everything an operator needs to recognise this run in the log.
log_line "Remove_Policy_Scope_Limitation.sh ${SCRIPT_VERSION}"
log_line "Jamf Pro:   ${jamfpro_url}"
log_line "CSV:        ${csv_file} (${policies_total} policy IDs)"
[[ -n "$username" ]]        && log_line "Username:   ${username}"
[[ -n "$user_group_name" ]] && log_line "User group: ${user_group_name} (by name)"
[[ -n "$user_group_id" ]]   && log_line "User group: ${user_group_id} (by ID)"
log_line "Backups:    ${backup_dir}"
if [[ "$apply_changes" = "yes" ]]; then
	log_line "Mode:       APPLY -- policies will be modified"
else
	log_line "Mode:       DRY RUN -- nothing will be modified"
fi
log_line ""

# policy_ids is newline separated; the unquoted expansion is the intended
# word split (bash 3.2 has no readarray).
for policy_id in ${policy_ids}; do

	if [[ -n "$username" ]]; then
		ProcessPolicy "$policy_id" "user" "$username"
	fi

	if [[ -n "$user_group_name" ]]; then
		ProcessPolicy "$policy_id" "group-name" "$user_group_name"
	fi

	if [[ -n "$user_group_id" ]]; then
		ProcessPolicy "$policy_id" "group-id" "$user_group_id"
	fi

	if [[ "$inter_policy_delay" -gt 0 ]]; then
		sleep "$inter_policy_delay"
	fi

done

# Summary. exitCode goes to 1 only when a policy failed; a policy that was
# skipped, refused or already correct is not a failure.
log_line ""
if [[ "$apply_changes" = "yes" ]]; then
	log_line "Updated:          ${policies_updated}"
else
	log_line "Would update:     ${policies_updated}"
fi
log_line "Not limited:      ${policies_already}"
log_line "Skipped:          ${policies_skipped}"
log_line "Failed:           ${policies_failed}"
log_line "Backups and log:  ${backup_dir}"

if [[ "$apply_changes" != "yes" ]] && [[ "$policies_updated" -gt 0 ]]; then
	log_line ""
	log_line "To apply, re-run with --apply --confirm ${confirm_token}"
fi

if [[ "$policies_failed" -gt 0 ]]; then
	exitCode=1
fi

InvalidateAPIToken

exit $exitCode
