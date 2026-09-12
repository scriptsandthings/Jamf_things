#!/bin/bash

# Renames the custom event on every Jamf Pro policy listed in a CSV file.
#
# This is the one trigger operation that is genuinely a modify rather than an
# add or a remove. The five boolean triggers have nothing to change -- turning one
# on IS the modification, and Add_Policy_Trigger.sh / Remove_Policy_Trigger.sh
# cover both directions. <general><trigger_other> holds a name, and a name can be
# wrong.
#
# RENAMING A CUSTOM EVENT BREAKS EVERY CALLER OF THE OLD NAME. Anything running
# "jamf policy -event <old>" -- a LaunchDaemon, another policy's script, a Setup
# Manager step, a runbook, a colleague's terminal history -- stops matching. Jamf
# Pro will not warn you and the call fails silently, because "no policy matched
# that event" is a normal, successful outcome for the jamf binary. Find the
# callers before running this.
#
# A policy whose custom event is not --from is skipped, not renamed. Only the
# named event moves.
#
# Authentication is OAuth client credentials against the Jamf Pro API. The policy
# read and write themselves are Classic API, because the Jamf Pro API has no
# policy endpoints.
#
# Prerequisites, in Jamf Pro:
#   Settings > System > API Roles and Clients
#     1. Create an API Role with "Read Policies" and "Update Policies".
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
# credential resolution, the CSV reader and the XML surgery functions.
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
Rename the custom event on the Jamf Pro policies listed in a CSV.

Usage:
  Rename_Policy_Trigger.sh --csv <file> --from <event> --to <event> [options]

Required:
  --csv <file>             CSV of policy IDs. The policy ID is the first column.
                           A header row, blank lines and lines beginning with #
                           are skipped. Comma or tab separated.
  --from <event>           The custom event to rename. A policy whose custom
                           event is something else is skipped, not renamed.
  --to <event>             The new custom event name.

Allowed characters in both: letters, digits, and . _ -

WARNING. Renaming a custom event breaks every caller of the old name.
"jamf policy -event <old>" stops matching, and it fails silently -- matching no
policy is a normal outcome for the jamf binary, not an error. Find the callers
first. This script only changes Jamf Pro; it cannot find or update them.

Only the custom event is touched. The five boolean triggers are add/remove
operations, not renames: use Add_Policy_Trigger.sh and Remove_Policy_Trigger.sh.

Options:
  --apply                  Actually write. Without it, nothing is modified.
  --confirm <token>        Required with --apply. The dry run prints the token.
  --backup-dir <dir>       Where to write per-policy backups.
                           Default: ./trigger-backups-YYYYmmdd-HHMMSS
  --log <file>             Log file. Default: <backup-dir>/run.log
  --delay <seconds>        Pause between policies. Default: 0
  --include-non-self-service
                           Also modify policies that are not Self Service
                           policies. Off by default: this script exists for the
                           Self Service workflow, and a CSV with a stray ID in
                           it should not silently rename a background policy's
                           event.
  --help                   This text.

Exit codes:
  0  every policy in the CSV was renamed, already renamed, or skipped
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
event_from=""
event_to=""
apply_changes="no"
confirm_token_supplied=""
backup_dir=""
log_file=""
inter_policy_delay=0
include_non_self_service="no"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--csv)           csv_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--from)          event_from="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--to)            event_to="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--apply)         apply_changes="yes"; shift ;;
		--confirm)       confirm_token_supplied="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--backup-dir)    backup_dir="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--log)           log_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--delay)         inter_policy_delay="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--include-non-self-service) include_non_self_service="yes"; shift ;;
		--trigger)
			# The boolean triggers have no rename. Refused rather than ignored:
			# accepting it would imply this script can do something it cannot.
			echo "ERROR! --trigger is not renameable. The five boolean triggers are"
			echo "       on or off, so a rename is an add plus a remove:"
			echo "         Remove_Policy_Trigger.sh --trigger <old>"
			echo "         Add_Policy_Trigger.sh    --trigger <new>"
			exit 3
			;;
		--help|-h)       usage; exit 0 ;;
		*)               echo "ERROR! Unknown argument: $1"; echo; usage; exit 3 ;;
	esac
done

if [[ -z "$csv_file" ]]; then
	echo "ERROR! --csv is required."; echo; usage; exit 3
fi

if [[ ! -f "$csv_file" ]]; then
	echo "ERROR! CSV not found: $csv_file"; exit 3
fi

if [[ -z "$event_from" ]] || [[ -z "$event_to" ]]; then
	echo "ERROR! Both --from and --to are required."; echo; usage; exit 3
fi

# Both names go into XML, an XPath predicate and an awk pattern. No quoting
# scheme survives all three, so the character set is narrow. Jamf's own custom
# events are conventionally within it.
for event_value in "$event_from" "$event_to"; do
	if ! echo "$event_value" | grep -Eq '^[A-Za-z0-9._-]+$'; then
		echo "ERROR! Event names may contain only letters, digits and . _ -"
		echo "       Got: $event_value"
		exit 3
	fi
done

if [[ "$event_from" = "$event_to" ]]; then
	echo "ERROR! --from and --to are the same: ${event_from}"
	echo "       Nothing would change."
	exit 3
fi

# ''|*[!0-9]* rejects the empty string and anything containing a non-digit:
# the portable bash 3.2 integer test.
case "$inter_policy_delay" in
	''|*[!0-9]*) echo "ERROR! --delay must be a whole number of seconds."; exit 3 ;;
esac

# The trigger-backups- prefix is shared with the other three trigger scripts;
# the first line of run.log inside names the script that produced the directory.
if [[ -z "$backup_dir" ]]; then
	backup_dir="./trigger-backups-$(date '+%Y%m%d-%H%M%S')"
fi

# The leaf that replaces the existing one in <general>. Never empty here: both
# names are validated non-empty above, so this script cannot clear an event.
new_trigger_node="<trigger_other>${event_to}</trigger_other>"

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
	local policy_xml
	local http_code
	local self_service_flag
	local policy_name
	local current_value
	local formatted_xml
	local general_xml
	local new_general
	local payload
	local verify_xml
	local verify_value

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

	current_value=$(GetPolicyTriggerState "$policy_xml" trigger_other)

	# ALREADY is decided before the --from match on purpose: a policy already
	# at --to is the outcome this run wants, so re-running after a partial
	# apply is idempotent instead of a wall of SKIPPED lines.
	if [[ "$current_value" = "$event_to" ]]; then
		log_line "ALREADY  ${policy_id} (${policy_name}): custom event is already '${event_to}'."
		policies_already=$((policies_already + 1))
		return
	fi

	# Only the named event moves. Renaming whatever happens to be there would
	# quietly repoint policies this run was never meant to touch.
	if [[ "$current_value" != "$event_from" ]]; then
		log_line "SKIPPED  ${policy_id} (${policy_name}): custom event is '${current_value:-none}', not '${event_from}'."
		policies_skipped=$((policies_skipped + 1))
		return
	fi

	# Normalise before line-oriented editing. The API's own formatting is not
	# guaranteed, and the awk replacement is line-based.
	formatted_xml=$(echo "$policy_xml" | xmllint --format - 2>/dev/null)
	if [[ -z "$formatted_xml" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): response did not parse as XML."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# Send the complete <general> element, byte-identical except for the custom
	# event. Jamf Pro's Classic API replaces the content of any element a request
	# supplies, so a PUT carrying a bare <general><trigger_other> could drop the
	# policy's name, category, frequency and every other trigger.
	general_xml=$(echo "$formatted_xml" | awk '/^[[:space:]]*<general>[[:space:]]*$/,/^[[:space:]]*<\/general>[[:space:]]*$/')
	if [[ -z "$general_xml" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): no <general> element in the policy."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# The if tests the substitution's status, which is the library function's
	# exit code, so a node that could not be placed is caught here, not later.
	if ! new_general=$(ReplaceElementInSection "$general_xml" general trigger_other "$new_trigger_node") ||
	   [[ -z "$new_general" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): could not place <trigger_other> in <general>."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# trigger_other is a leaf, so a bug in the replacement shows up as two of
	# them rather than as a parse error. Jamf would take one and the run would
	# report a success that did not happen.
	if [[ "$(echo "$new_general" | grep -c '<trigger_other>')" -ne 1 ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): edited <general> does not contain exactly one <trigger_other>."
		policies_failed=$((policies_failed + 1))
		return
	fi

	payload="<?xml version=\"1.0\" encoding=\"UTF-8\"?><policy>${new_general}</policy>"

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
		log_line "WOULD RENAME ${policy_id} (${policy_name}): ${event_from} -> ${event_to}"
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

	# Read back. An accepted PUT is not proof the value landed.
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

	verify_value=$(GetPolicyTriggerState "$verify_xml" trigger_other)

	if [[ "$verify_value" = "$event_to" ]]; then
		log_line "RENAMED  ${policy_id} (${policy_name}): ${event_from} -> ${event_to}"
		policies_updated=$((policies_updated + 1))
	else
		log_line "FAILED   ${policy_id} (${policy_name}): PUT returned ${http_code} but the custom event reads back as ${verify_value:-empty}, wanted ${event_to}."
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
# of a dry run, reused against a different CSV or a different pair of names, or
# pasted in from one of the other scripts.
confirm_token="RENAME-TRIGGER-${policies_total}-${event_from}-${event_to}"
# Collapse the label to one paste-safe shell word: spaces become _, everything
# outside [A-Za-z0-9_-] is dropped.
confirm_token=$(echo "$confirm_token" | tr ' ' '_' | tr -cd 'A-Za-z0-9_-')

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

log_line "Rename_Policy_Trigger.sh ${SCRIPT_VERSION}"
log_line "Jamf Pro:   ${jamfpro_url}"
log_line "CSV:        ${csv_file} (${policies_total} policy IDs)"
log_line "Rename:     ${event_from} -> ${event_to}"
log_line "Backups:    ${backup_dir}"
if [[ "$apply_changes" = "yes" ]]; then
	log_line "Mode:       APPLY -- policies will be modified"
else
	log_line "Mode:       DRY RUN -- nothing will be modified"
fi
log_line ""
log_line "Callers of '${event_from}' elsewhere will stop matching. jamf policy -event"
log_line "fails silently when nothing matches; this script cannot find them for you."
log_line ""

# policy_ids is newline separated; the unquoted expansion is the intended
# word split (bash 3.2 has no readarray).
for policy_id in ${policy_ids}; do

	ProcessPolicy "$policy_id"

	if [[ "$inter_policy_delay" -gt 0 ]]; then
		sleep "$inter_policy_delay"
	fi

done

log_line ""
if [[ "$apply_changes" = "yes" ]]; then
	log_line "Renamed:          ${policies_updated}"
else
	log_line "Would rename:     ${policies_updated}"
fi
log_line "Already named:    ${policies_already}"
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
