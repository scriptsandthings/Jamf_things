#!/bin/bash

# Adds a trigger to every Jamf Pro policy listed in a CSV file.
#
# A policy's triggers are six separate fields under <general>: five booleans
# (Recurring Check-in, Startup, Login, Logout, Network State Change, Enrollment
# Complete) and one string, trigger_other, which holds the custom event name
# that "jamf policy -event <name>" matches. This script turns one boolean on, or
# sets the custom event.
#
# Adding an automatic trigger to a policy that is ENABLED puts it into service on
# every Mac in scope with nobody opening Self Service. Those are refused unless
# --allow-auto-trigger is given. A disabled policy cannot run whatever its
# triggers say, so it is never refused.
#
# <general><trigger> -- the legacy summary field, "EVENT" or "USER_INITIATED" --
# is NOT written here. Jamf Pro maintains it alongside the booleans. Its value is
# reported before and after each write so the first real run shows whether Jamf
# recomputes it. See CLAUDE.md, standing state.
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
# What this script does, as data
# ---------------------------------------------------------------------------

# The data that differs between the Add_ and Remove_ trigger scripts. It is
# not the only difference: Add_Policy_Trigger.sh also accepts
# --allow-auto-trigger, skips a policy that carries a different custom event
# and refuses to arm an enabled policy; Remove_Policy_Trigger.sh refuses that
# flag, skips on a custom-event mismatch and reports a policy left with
# nothing to run it. Diff the two files before editing either.
boolean_target="true"
action_present="ADD"
action_past="ADDED"
token_prefix="ADD-TRIGGER"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
	cat <<'EOF'
Add a trigger to the Jamf Pro policies listed in a CSV.

Usage:
  Add_Policy_Trigger.sh --csv <file> (--trigger <name> | --custom-event <event>) [options]

Required:
  --csv <file>             CSV of policy IDs. The policy ID is the first column.
                           A header row, blank lines and lines beginning with #
                           are skipped. Comma or tab separated.

Exactly one of:
  --trigger <name>         One of: checkin, startup, login,
                           network-state-change, enrollment-complete.
                           "recurring-check-in" is accepted for checkin.
                           "checkin" is Recurring Check-in. "logout" is NOT
                           accepted: Jamf Pro has retired it, and a
                           trigger_logout write is answered 201 and discarded.
  --custom-event <event>   The custom event name that "jamf policy -event <name>"
                           matches. A policy has exactly ONE custom event. This
                           sets it on policies that have none; a policy that
                           already carries a DIFFERENT event is skipped, because
                           repointing an event you did not name breaks its
                           callers silently. Use Rename_Policy_Trigger.sh for
                           that. Allowed characters: letters, digits, and . _ -

Options:
  --apply                  Actually write. Without it, nothing is modified.
  --confirm <token>        Required with --apply. The dry run prints the token.
  --allow-auto-trigger     Permit adding an automatic trigger to a policy that
                           is currently ENABLED. Refused by default: the policy
                           starts running on every Mac in scope at the next
                           trigger, without anyone opening Self Service. A
                           disabled policy is never refused -- it cannot run.
  --backup-dir <dir>       Where to write per-policy backups.
                           Default: ./trigger-backups-YYYYmmdd-HHMMSS
  --log <file>             Log file. Default: <backup-dir>/run.log
  --delay <seconds>        Pause between policies. Default: 0
  --include-non-self-service
                           Also modify policies that are not Self Service
                           policies. Off by default: this script exists for the
                           Self Service workflow, and a CSV with a stray ID in
                           it should not silently rearm a background policy.
  --help                   This text.

Exit codes:
  0  every policy in the CSV already had the trigger or was updated
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
trigger_name=""
custom_event=""
apply_changes="no"
confirm_token_supplied=""
allow_auto_trigger="no"
backup_dir=""
log_file=""
inter_policy_delay=0
include_non_self_service="no"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--csv)           csv_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--trigger)       trigger_name="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--custom-event)  custom_event="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--apply)         apply_changes="yes"; shift ;;
		--confirm)       confirm_token_supplied="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--allow-auto-trigger) allow_auto_trigger="yes"; shift ;;
		--backup-dir)    backup_dir="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--log)           log_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--delay)         inter_policy_delay="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--include-non-self-service) include_non_self_service="yes"; shift ;;
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

# Exactly one selector. Two would be ambiguous about which is written, and zero
# would make the script a no-op that still looks like it ran.
selector_count=0
[[ -n "$trigger_name" ]] && selector_count=$((selector_count + 1))
[[ -n "$custom_event" ]] && selector_count=$((selector_count + 1))

if [[ "$selector_count" -ne 1 ]]; then
	echo "ERROR! Give exactly one of --trigger or --custom-event."
	echo; usage; exit 3
fi

trigger_element=""
if [[ -n "$trigger_name" ]]; then
	trigger_element=$(ResolveTriggerElement "$trigger_name")
	if [[ -z "$trigger_element" ]]; then
		echo "ERROR! Unknown trigger: ${trigger_name}"
		echo "       Expected one of: ${TRIGGER_FLAG_NAMES}"
		ExplainRetiredTrigger "$trigger_name"
		exit 3
	fi
else
	trigger_element="trigger_other"
	# The event name goes into XML, an XPath predicate and an awk pattern. No
	# quoting scheme survives all three, so the character set is narrow. Jamf's
	# own custom events are conventionally within it.
	if ! echo "$custom_event" | grep -Eq '^[A-Za-z0-9._-]+$'; then
		echo "ERROR! --custom-event may contain only letters, digits and . _ -"
		echo "       Got: $custom_event"
		exit 3
	fi
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

# What is being written, and what a read-back must show.
if [[ "$trigger_element" = "trigger_other" ]]; then
	# Both branches stay so the pair diffs cleanly. boolean_target is fixed
	# per script, so only one of them ever runs: the populated branch is the
	# Add_ one, and the empty value is how a cleared custom event reads back
	# in Remove_.
	if [[ "$boolean_target" = "true" ]]; then
		target_value="$custom_event"
	else
		target_value=""
	fi
	trigger_label="Custom Event ${custom_event}"
else
	target_value="$boolean_target"
	trigger_label=$(TriggerLabel "$trigger_element")
fi

# The leaf that replaces the existing one in <general>. An empty value (a
# Remove_ clear) writes <trigger_other></trigger_other>; whether Jamf Pro reads
# that as "no custom event" rather than rejecting it is unverified, and the
# read-back reports it either way.
new_trigger_node="<${trigger_element}>${target_value}</${trigger_element}>"

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
	local policy_enabled
	local legacy_trigger
	local triggers_before
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

	current_value=$(GetPolicyTriggerState "$policy_xml" "$trigger_element")
	policy_enabled=$(GetPolicyEnabled "$policy_xml")
	legacy_trigger=$(GetLegacyTrigger "$policy_xml")
	triggers_before=$(GetPolicyTriggers "$policy_xml")

	if [[ "$current_value" = "$target_value" ]]; then
		log_line "ALREADY  ${policy_id} (${policy_name}): ${trigger_label} already set, nothing to do."
		policies_already=$((policies_already + 1))
		return
	fi

	# A policy holds exactly one custom event, and this script never repoints
	# one the caller did not name: "jamf policy -event <old>" matching nothing
	# is a successful outcome for the jamf binary, so every caller of the old
	# name would break with nothing in any log. Rename_Policy_Trigger.sh takes
	# both names and is the script for that job.
	if [[ "$trigger_element" = "trigger_other" ]] && [[ -n "$current_value" ]]; then
		log_line "SKIPPED  ${policy_id} (${policy_name}): custom event is already '${current_value}'. Use Rename_Policy_Trigger.sh --from '${current_value}' --to '${custom_event}' to repoint it."
		policies_skipped=$((policies_skipped + 1))
		return
	fi

	# An automatic trigger on an ENABLED policy means it starts running on every
	# Mac in scope at the next trigger. A custom event does not fire by itself,
	# and a disabled policy cannot run at all, so neither is refused.
	if [[ "$boolean_target" = "true" ]] &&
	   [[ "$trigger_element" != "trigger_other" ]] &&
	   [[ "$policy_enabled" = "true" ]] &&
	   [[ "$allow_auto_trigger" != "yes" ]]; then
		log_line "REFUSED  ${policy_id} (${policy_name}): policy is enabled; adding ${trigger_label} would run it on every targeted Mac. --allow-auto-trigger overrides."
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

	# Send the complete <general> element, byte-identical except for the one
	# trigger. Jamf Pro's Classic API replaces the content of any element a
	# request supplies, so a PUT carrying a bare <general><trigger_checkin>
	# could drop the policy's name, category, frequency and every other trigger.
	general_xml=$(echo "$formatted_xml" | awk '/^[[:space:]]*<general>[[:space:]]*$/,/^[[:space:]]*<\/general>[[:space:]]*$/')
	if [[ -z "$general_xml" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): no <general> element in the policy."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# The if tests the substitution's status, which is the library function's
	# exit code, so a node that could not be placed is caught here, not later.
	if ! new_general=$(ReplaceElementInSection "$general_xml" general "$trigger_element" "$new_trigger_node") ||
	   [[ -z "$new_general" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): could not place <${trigger_element}> in <general>."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# The trigger fields are leaves, so a bug in the replacement shows up as two
	# of them rather than as a parse error. Jamf would take one and the run would
	# report a success that did not happen.
	if [[ "$(echo "$new_general" | grep -c "<${trigger_element}>")" -ne 1 ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): edited <general> does not contain exactly one <${trigger_element}>."
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
		log_line "WOULD ${action_present} ${policy_id} (${policy_name}): ${trigger_label}; enabled=${policy_enabled:-none}, now runs on: ${triggers_before}"
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

	verify_value=$(GetPolicyTriggerState "$verify_xml" "$trigger_element")

	if [[ "$verify_value" = "$target_value" ]]; then
		log_line "${action_past}  ${policy_id} (${policy_name}): ${trigger_label}; now runs on: $(GetPolicyTriggers "$verify_xml")"
		# Nothing here writes <general><trigger>. Report it when it moved, so a
		# first real run settles whether Jamf Pro recomputes it.
		if [[ "$(GetLegacyTrigger "$verify_xml")" != "$legacy_trigger" ]]; then
			log_line "         note: <general><trigger> changed ${legacy_trigger:-none} -> $(GetLegacyTrigger "$verify_xml") (Jamf Pro recomputed it; this script does not write it)"
		fi
		policies_updated=$((policies_updated + 1))
	else
		log_line "FAILED   ${policy_id} (${policy_name}): PUT returned ${http_code} but <${trigger_element}> reads back as ${verify_value:-empty}, wanted ${target_value:-empty}."
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
# of a dry run, reused against a different CSV or a different trigger, or pasted
# in from one of the other scripts.
confirm_token="${token_prefix}-${policies_total}-${trigger_label}"
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

log_line "Add_Policy_Trigger.sh ${SCRIPT_VERSION}"
log_line "Jamf Pro:   ${jamfpro_url}"
log_line "CSV:        ${csv_file} (${policies_total} policy IDs)"
log_line "Trigger:    ${trigger_label} -> ${target_value:-cleared}"
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
log_line "Skipped/refused:  ${policies_skipped}"
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
