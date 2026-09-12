#!/bin/bash

# Shows or hides every Jamf Pro policy listed in a CSV file in Self Service.
#
# This writes <self_service><use_for_self_service>. It is the flag that decides
# whether a policy appears in Self Service at all; the display name, icon,
# description, categories and feature_on_main_page are left exactly as they are.
#
# ONE SCRIPT, BOTH DIRECTIONS. --show and --hide are the same write with a
# different value, and pairing them would produce two files differing in one
# character. The scope scripts are pairs because add and remove are genuinely
# different XML operations; this is not. Enable_/Disable_ are a pair because
# enabling carries a guard that disabling does not; show and hide carry no
# such asymmetry.
#
# Note what --hide does beyond Self Service: every other script in this directory
# skips non-Self-Service policies by default. A policy hidden here will be passed
# over by the scope, category, enable and trigger scripts on their next run
# unless they are given --include-non-self-service. That is the intended
# behaviour, and it is easy to forget.
#
# A hidden policy is not disabled. It keeps its triggers and still runs on them.
# Use Disable_Policy.sh to stop it running.
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
Show or hide the Jamf Pro policies listed in a CSV in Self Service.

Usage:
  Set_Policy_Self_Service.sh --csv <file> (--show | --hide) [options]

Required:
  --csv <file>             CSV of policy IDs. The policy ID is the first column.
                           A header row, blank lines and lines beginning with #
                           are skipped. Comma or tab separated.

Exactly one of:
  --show                   Make the policy available in Self Service.
  --hide                   Remove it from Self Service.

Only use_for_self_service is written. Display name, icon, description,
categories and feature_on_main_page are left alone, so --show after --hide
restores the entry exactly as it was.

Hiding a policy also takes it out of scope for every other script here: they
skip non-Self-Service policies unless given --include-non-self-service.

Hiding is not disabling. A hidden policy keeps its triggers and still runs on
them. Use Disable_Policy.sh to stop it running.

Options:
  --apply                  Actually write. Without it, nothing is modified.
  --confirm <token>        Required with --apply. The dry run prints the token.
  --backup-dir <dir>       Where to write per-policy backups.
                           Default: ./self-service-backups-YYYYmmdd-HHMMSS
  --log <file>             Log file. Default: <backup-dir>/run.log
  --delay <seconds>        Pause between policies. Default: 0
  --help                   This text.

Exit codes:
  0  every policy in the CSV already matched or was updated
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
show_in_self_service=""
apply_changes="no"
confirm_token_supplied=""
backup_dir=""
log_file=""
inter_policy_delay=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--csv)        csv_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--show)       show_in_self_service="yes"; shift ;;
		--hide)       show_in_self_service="no"; shift ;;
		--apply)      apply_changes="yes"; shift ;;
		--confirm)    confirm_token_supplied="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--backup-dir) backup_dir="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--log)        log_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--delay)      inter_policy_delay="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--include-non-self-service)
			# Refused rather than ignored. Every other script here has this flag
			# because it skips policies that are not in Self Service. This is the
			# script that sets that flag, so skipping on it would make --show a
			# no-op on exactly the policies it exists to act on.
			echo "ERROR! --include-non-self-service does not apply here."
			echo "       This script sets use_for_self_service, so it acts on every"
			echo "       policy in the CSV regardless of its current value."
			exit 3
			;;
		--help|-h)    usage; exit 0 ;;
		*)            echo "ERROR! Unknown argument: $1"; echo; usage; exit 3 ;;
	esac
done

if [[ -z "$csv_file" ]]; then
	echo "ERROR! --csv is required."; echo; usage; exit 3
fi

if [[ ! -f "$csv_file" ]]; then
	echo "ERROR! CSV not found: $csv_file"; exit 3
fi

if [[ -z "$show_in_self_service" ]]; then
	echo "ERROR! Give exactly one of --show or --hide."
	echo; usage; exit 3
fi

# ''|*[!0-9]* rejects the empty string and anything containing a non-digit:
# the portable bash 3.2 integer test.
case "$inter_policy_delay" in
	''|*[!0-9]*) echo "ERROR! --delay must be a whole number of seconds."; exit 3 ;;
esac

if [[ -z "$backup_dir" ]]; then
	backup_dir="./self-service-backups-$(date '+%Y%m%d-%H%M%S')"
fi

# What --show and --hide write, as data. From here on the direction is read
# from target_state; the only places that still branch on it are the
# no-display-name note on show and the hide reminder in the run header.
if [[ "$show_in_self_service" = "yes" ]]; then
	target_state="true"
	action_label="SHOW"
	action_past="SHOWN"
	token_prefix="SELF-SERVICE-SHOW"
else
	target_state="false"
	action_label="HIDE"
	action_past="HIDDEN"
	token_prefix="SELF-SERVICE-HIDE"
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
# Always 0 here: this script has no skip path, because it refuses
# --include-non-self-service instead of honouring it. Kept so the summary
# block matches the other scripts.
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
	local policy_name
	local current_state
	local display_name
	local formatted_xml
	local self_service_xml
	local new_self_service
	local payload
	local verify_xml
	local verify_state

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
	current_state=$(GetPolicySelfService "$policy_xml")
	# Kept for the no-display-name note below and the post-PUT drift check.
	display_name=$(echo "$policy_xml" | xmllint --xpath '/policy/self_service/self_service_display_name/text()' - 2>/dev/null)

	if [[ "$current_state" = "$target_state" ]]; then
		log_line "ALREADY  ${policy_id} (${policy_name}): use_for_self_service is already ${target_state}."
		policies_already=$((policies_already + 1))
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

	# Send the complete <self_service> element, byte-identical except for the one
	# flag. Jamf Pro's Classic API replaces the content of any element a request
	# supplies, so a PUT carrying a bare <self_service><use_for_self_service>
	# would drop the display name, icon, description, the Self Service categories
	# and feature_on_main_page -- the very things that make --show reversible.
	#
	# The awk range stops at the first </self_service>, which is the real close:
	# <self_service_categories> is a different element name and does not match.
	self_service_xml=$(echo "$formatted_xml" | awk '/^[[:space:]]*<self_service>[[:space:]]*$/,/^[[:space:]]*<\/self_service>[[:space:]]*$/')
	if [[ -z "$self_service_xml" ]]; then
		# Refused rather than synthesised. Building a <self_service> element here
		# would mean PUTting one with no display name or icon, and the Classic
		# API would take it as the complete truth for that element.
		log_line "FAILED   ${policy_id} (${policy_name}): no <self_service> element in the policy. Not synthesising one; set it once in the UI and re-run."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# The if tests the substitution's status, which is the library function's
	# exit code, so a node that could not be placed is caught here, not later.
	if ! new_self_service=$(ReplaceElementInSection "$self_service_xml" self_service use_for_self_service "<use_for_self_service>${target_state}</use_for_self_service>") ||
	   [[ -z "$new_self_service" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): could not place <use_for_self_service> in <self_service>."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# use_for_self_service is a leaf, so a bug in the replacement shows up as two
	# of them rather than as a parse error. Jamf would take one and the run would
	# report a success that did not happen.
	if [[ "$(echo "$new_self_service" | grep -c '<use_for_self_service>')" -ne 1 ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): edited <self_service> does not contain exactly one <use_for_self_service>."
		policies_failed=$((policies_failed + 1))
		return
	fi

	payload="<?xml version=\"1.0\" encoding=\"UTF-8\"?><policy>${new_self_service}</policy>"

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

	# Showing a policy with no display name puts the policy's own name in front
	# of users. That is usually an internal name.
	if [[ "$target_state" = "true" ]] && [[ -z "$display_name" ]]; then
		log_line "         note: ${policy_id} has no Self Service display name; users will see the policy name '${policy_name}'."
	fi

	if [[ "$apply_changes" != "yes" ]]; then
		log_line "WOULD ${action_label} ${policy_id} (${policy_name}): use_for_self_service ${current_state:-none} -> ${target_state}"
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

	verify_state=$(GetPolicySelfService "$verify_xml")

	if [[ "$verify_state" = "$target_state" ]]; then
		log_line "${action_past}   ${policy_id} (${policy_name}): use_for_self_service ${current_state:-none} -> ${verify_state}"
		# The display name is what makes --show reversible. If the PUT dropped
		# it, say so now rather than letting someone find out from a user.
		if [[ -n "$display_name" ]] && [[ "$(echo "$verify_xml" | xmllint --xpath '/policy/self_service/self_service_display_name/text()' - 2>/dev/null)" != "$display_name" ]]; then
			log_line "         WARNING: the Self Service display name changed. Restore from ${backup_dir}/policy-${policy_id}-before.xml"
		fi
		policies_updated=$((policies_updated + 1))
	else
		log_line "FAILED   ${policy_id} (${policy_name}): PUT returned ${http_code} but use_for_self_service reads back as ${verify_state:-none}."
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

# The confirmation token is derived from the run. There is no group or user here
# to bind it to an intent, so the policy ID list itself is hashed in: a token
# from a dry run of one CSV will not apply a different CSV of the same length.
# -q prints the bare digest; eight hex characters tell any two CSVs apart
# and are short enough to type.
csv_digest=$(echo "$policy_ids" | /sbin/md5 -q | cut -c1-8)
confirm_token="${token_prefix}-${policies_total}-${csv_digest}"

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

log_line "Set_Policy_Self_Service.sh ${SCRIPT_VERSION}"
log_line "Jamf Pro:   ${jamfpro_url}"
log_line "CSV:        ${csv_file} (${policies_total} policy IDs)"
log_line "Action:     ${action_label} -- use_for_self_service to ${target_state}"
log_line "Backups:    ${backup_dir}"
if [[ "$apply_changes" = "yes" ]]; then
	log_line "Mode:       APPLY -- policies will be modified"
else
	log_line "Mode:       DRY RUN -- nothing will be modified"
fi
log_line ""
if [[ "$target_state" = "false" ]]; then
	log_line "Hidden policies are skipped by the other scripts here unless they are"
	log_line "given --include-non-self-service. Hiding is not disabling: triggers still fire."
	log_line ""
fi

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
	log_line "Changed:          ${policies_updated}"
else
	log_line "Would change:     ${policies_updated}"
fi
log_line "Already set:      ${policies_already}"
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
