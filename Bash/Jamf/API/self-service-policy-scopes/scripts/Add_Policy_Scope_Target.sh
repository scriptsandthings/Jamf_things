#!/bin/bash

# Adds a scope target -- a computer group by ID, a computer by ID, or both -- to
# every Jamf Pro policy listed in a CSV file. Partner to
# Remove_Policy_Scope_Target.sh (same arguments, same safety model). Sibling
# of Add_Policy_Scope_Exclusion.sh and Add_Policy_Scope_Limitation.sh, which
# take different selectors because the scope sections take different entry
# types.
#
# Targets are who the policy applies TO. A policy's scope targets are computers,
# computer groups, buildings and departments. Users are NOT targets: Jamf Pro
# scopes policies to machines and then narrows by user with a limitation. If you
# want a policy to apply only to certain people, that is
# Add_Policy_Scope_Limitation.sh.
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
# This script MODIFIES PRODUCTION POLICIES, and a target is the setting that
# decides whether a policy runs on a Mac at all. It is dry-run by default. A real
# run needs both --apply and --confirm with the token the dry run prints.

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
Add a scope target to the Jamf Pro policies listed in a CSV.

Usage:
  Add_Policy_Scope_Target.sh --csv <file> [--group-id <n>] [--computer-id <n>] [options]

Required:
  --csv <file>             CSV of policy IDs. The policy ID is the first column.
                           A header row, blank lines and lines beginning with #
                           are skipped. Comma or tab separated.

At least one of:
  --group-id <n>           Computer group to target, by Jamf Pro ID. Works for
                           both smart and static groups -- they share an ID space
                           and the same scope element.
  --computer-id <n>        Individual computer to target, by Jamf Pro ID.

Note: users are not targets. Jamf Pro scopes a policy to machines and then
narrows by user with a limitation -- see Add_Policy_Scope_Limitation.sh.
Buildings and departments are also valid targets but are not wired up here; ask
if you need them.

Options:
  --apply                  Actually write. Without it, nothing is modified.
  --confirm <token>        Required with --apply. The dry run prints the token.
  --backup-dir <dir>       Where to write per-policy backups.
                           Default: ./target-backups-YYYYmmdd-HHMMSS
  --log <file>             Log file. Default: <backup-dir>/run.log
  --delay <seconds>        Pause between policies. Default: 0
  --include-non-self-service
                           Also modify policies that are not Self Service
                           policies. Off by default: this script exists for the
                           Self Service workflow, and a CSV with a stray ID in
                           it should not silently rescope a background policy.
  --help                   This text.

Exit codes:
  0  every policy in the CSV already had the target or was updated
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
group_id=""
computer_id=""
apply_changes="no"
confirm_token_supplied=""
backup_dir=""
log_file=""
inter_policy_delay=0
include_non_self_service="no"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--csv)         csv_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--group-id)    group_id="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--computer-id) computer_id="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--apply)       apply_changes="yes"; shift ;;
		--confirm)     confirm_token_supplied="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--backup-dir)  backup_dir="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--log)         log_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--delay)       inter_policy_delay="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--include-non-self-service) include_non_self_service="yes"; shift ;;
		--help|-h)     usage; exit 0 ;;
		--username|--user-group|--user-group-id)
			# Muscle memory from the limitation scripts.
			echo "ERROR! $1 is not valid here. Users are not scope targets."
			echo "       Jamf Pro scopes a policy to machines -- computers, computer groups,"
			echo "       buildings, departments -- and narrows by user with a limitation."
			echo "       Did you mean Add_Policy_Scope_Limitation.sh?"
			exit 3
			;;
		*)             echo "ERROR! Unknown argument: $1"; echo; usage; exit 3 ;;
	esac
done

if [[ -z "$csv_file" ]]; then
	echo "ERROR! --csv is required."; echo; usage; exit 3
fi

if [[ ! -f "$csv_file" ]]; then
	echo "ERROR! CSV not found: $csv_file"; exit 3
fi

if [[ -z "$group_id" ]] && [[ -z "$computer_id" ]]; then
	echo "ERROR! Give at least one of --group-id or --computer-id."; echo; usage; exit 3
fi

# A non-numeric ID would be sent to Jamf Pro as-is and create a scope entry that
# matches nothing.
if [[ -n "$group_id" ]]; then
	case "$group_id" in
		''|*[!0-9]*) echo "ERROR! --group-id must be a number: $group_id"; exit 3 ;;
	esac
fi

# Same reason as --group-id.
if [[ -n "$computer_id" ]]; then
	case "$computer_id" in
		''|*[!0-9]*) echo "ERROR! --computer-id must be a number: $computer_id"; exit 3 ;;
	esac
fi

# ''|*[!0-9]* rejects the empty string and anything containing a non-digit:
# the portable bash 3.2 integer test.
case "$inter_policy_delay" in
	''|*[!0-9]*) echo "ERROR! --delay must be a whole number of seconds."; exit 3 ;;
esac

if [[ -z "$backup_dir" ]]; then
	backup_dir="./target-backups-$(date '+%Y%m%d-%H%M%S')"
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
	local kind="$2"          # group | computer
	local value="$3"
	local container
	local entry
	local new_node
	local policy_xml
	local http_code
	local self_service_flag
	local policy_name
	local all_computers
	local existing
	local formatted_xml
	local scope_xml
	local new_scope
	local payload
	local verify_xml
	local verify_count

	# Map the kind onto Classic API element names: the container under <scope>
	# and the per-entry element inside it, which CountScopeEntry matches on
	# <id>. The Add_ half of this pair also builds the node to insert.
	if [[ "$kind" = "group" ]]; then
		container="computer_groups"
		entry="computer_group"
		new_node="<computer_group><id>${value}</id></computer_group>"
	else
		container="computers"
		entry="computer"
		new_node="<computer><id>${value}</id></computer>"
	fi

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

	# A policy scoped to All Computers already reaches everything. Adding a
	# target is harmless but changes nothing, and quietly doing it would hide a
	# scoping mistake, so say so.
	all_computers=$(echo "$policy_xml" | xmllint --xpath '/policy/scope/all_computers/text()' - 2>/dev/null)
	if [[ "$all_computers" = "true" ]]; then
		log_line "NOTE     ${policy_id} (${policy_name}): scoped to All Computers, so this target changes nothing in practice."
	fi

	# "targets" is the section with no wrapper element: its entries are direct
	# children of <scope>. See the scope note in the library.
	existing=$(CountScopeEntry "$policy_xml" targets "$container" "$entry" "id" "$value")
	if [[ "$existing" -gt 0 ]]; then
		log_line "ALREADY  ${policy_id} (${policy_name}): target already present, nothing to do."
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
	if ! new_scope=$(InsertScopeEntry "$scope_xml" targets "$container" "$new_node") ||
	   [[ -z "$new_scope" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): could not place the target in the scope."
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
		log_line "WOULD ADD ${policy_id} (${policy_name}): ${new_node} to targets/${container}"
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
	# A 409 is NOT a no-op, and must not short-circuit the read-back.
	#
	# Wire-checked against Jamf Pro 11.32.0 on 2026-09-12. A policy carried a
	# directory user group that was later deleted from the directory, so the
	# server could no longer resolve it. A PUT resending the whole <scope> --
	# which hard rule 1 requires -- to make an UNRELATED change answered 409,
	# applied the requested change anyway, and silently DROPPED the
	# unresolvable entry. Returning here reported FAILED for a write that had
	# landed, and said nothing at all about the entry Jamf destroyed.
	#
	# So 409 falls through to the read-back, which is the only thing that can
	# say what actually happened -- hard rule 2, applied to the case that
	# needs it most. Every other non-2xx really did leave the policy alone and
	# still returns here.
	if [[ "$http_code" = "409" ]]; then
		log_line "WARNING  ${policy_id} (${policy_name}): PUT returned HTTP 409. Jamf rejected part of the request but may have applied the rest, and silently drops any scope entry it cannot resolve -- most often a directory user or group that no longer exists in the directory."
		log_line "         Compare the policy against ${backup_dir}/policy-${policy_id}-before.xml before continuing; entries you did not name may be gone."
	elif [[ "$http_code" != "201" ]] && [[ "$http_code" != "200" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): PUT returned HTTP ${http_code}$(DescribeHTTPStatus "$http_code")"
		policies_failed=$((policies_failed + 1))
		return
	fi

	# Read back. An accepted PUT is not proof the element landed where intended.
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

	verify_count=$(CountScopeEntry "$verify_xml" targets "$container" "$entry" "id" "$value")

	if [[ "$verify_count" -gt 0 ]]; then
		log_line "UPDATED  ${policy_id} (${policy_name}): added id ${value} to targets/${container}"
		policies_updated=$((policies_updated + 1))
	else
		log_line "FAILED   ${policy_id} (${policy_name}): PUT returned ${http_code} but the target is not present on read-back."
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
# of a dry run, reused against a different CSV or a different target, or pasted
# in from one of the exclusion or limitation scripts.
confirm_token="ADD-TARGET-${policies_total}-${group_id:-none}-${computer_id:-none}"

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
log_line "Add_Policy_Scope_Target.sh ${SCRIPT_VERSION}"
log_line "Jamf Pro:   ${jamfpro_url}"
log_line "CSV:        ${csv_file} (${policies_total} policy IDs)"
[[ -n "$group_id" ]]    && log_line "Group ID:    ${group_id}"
[[ -n "$computer_id" ]] && log_line "Computer ID: ${computer_id}"
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

	if [[ -n "$group_id" ]]; then
		ProcessPolicy "$policy_id" "group" "$group_id"
	fi

	if [[ -n "$computer_id" ]]; then
		ProcessPolicy "$policy_id" "computer" "$computer_id"
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
log_line "Already targeted: ${policies_already}"
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
