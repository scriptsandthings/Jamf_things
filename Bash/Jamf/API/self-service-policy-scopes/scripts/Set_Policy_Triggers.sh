#!/bin/bash

# Sets the complete trigger set on every Jamf Pro policy listed in a CSV file.
#
# Declarative, and that is the point: every trigger named in --set is turned ON
# and every one not named is turned OFF. Use this to make a mixed fleet
# consistent in one run. Use Add_Policy_Trigger.sh / Remove_Policy_Trigger.sh
# when you want to change one trigger and leave the rest alone.
#
# Because it turns things off that you did not mention, every dry-run line
# prints the full before and after.
#
# THE CUSTOM EVENT IS NOT PART OF --set. It is a name, not a switch, and
# clearing it because you forgot to mention it would silently break every caller
# of "jamf policy -event <name>". Governed by its own flags instead:
#
#   --custom-event <name>          set it, on policies that have none or that
#                                  already carry that name
#   --clear-custom-event <name>    clear it, only where it is that name
#   neither                        leave it exactly as it is (and say so)
#
# A policy whose custom event is some other name is SKIPPED whole under either
# flag, not half-updated: this script never repoints or clears an event the
# caller did not name. Rename_Policy_Trigger.sh is the script for repointing.
#
# Turning on an automatic trigger on a policy that is ENABLED puts it into
# service on every Mac in scope. Those are refused unless --allow-auto-trigger is
# given. A disabled policy cannot run whatever its triggers say.
#
# <general><trigger> -- the legacy summary field -- is NOT written here. Jamf Pro
# maintains it alongside the booleans. See CLAUDE.md, standing state.
#
# Also unverified until a first real run: --clear-custom-event writes an empty
# <trigger_other></trigger_other>. Whether Jamf Pro reads that as "no custom
# event" or rejects the PUT is not known; the read-back reports it either way.
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

# Every boolean trigger this script owns. Anything in this list and not in
# --set is turned off, which is the whole contract.
ALL_TRIGGER_ELEMENTS="trigger_checkin trigger_startup trigger_login trigger_network_state_changed trigger_enrollment_complete"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
	cat <<'EOF'
Set the complete trigger set on the Jamf Pro policies listed in a CSV.

Usage:
  Set_Policy_Triggers.sh --csv <file> --set <list> [--custom-event <event> | --clear-custom-event <event>] [options]

Required:
  --csv <file>             CSV of policy IDs. The policy ID is the first column.
                           A header row, blank lines and lines beginning with #
                           are skipped. Comma or tab separated.
  --set <list>             Comma-separated triggers to turn ON. Everything else
                           is turned OFF. Use "none" to turn all five off.
                           Names: checkin, startup, login,
                           network-state-change, enrollment-complete.
                           "recurring-check-in" is accepted for checkin.

                           --set checkin,startup
                           --set none

The custom event (jamf policy -event <name>) is NOT part of --set, because
clearing a name you forgot to mention breaks every caller of it silently:
  --custom-event <event>   Set it on policies that have no custom event, or
                           already this one. A policy carrying a DIFFERENT
                           event is skipped whole -- use Rename_Policy_Trigger.sh
                           to repoint it. Letters, digits, and . _ -
  --clear-custom-event <event>
                           Clear it, only on policies whose event is exactly
                           this name. Any other name: the policy is skipped
                           whole. Naming the event is what proves you know
                           which callers you are cutting off.
  neither                  Leave it alone. The run reports any policy where a
                           custom event was left in place.

Options:
  --apply                  Actually write. Without it, nothing is modified.
  --confirm <token>        Required with --apply. The dry run prints the token.
  --allow-auto-trigger     Permit turning an automatic trigger ON for a policy
                           that is currently ENABLED. Refused by default: the
                           policy starts running on every Mac in scope at the
                           next trigger. A disabled policy is never refused.
  --backup-dir <dir>       Where to write per-policy backups.
                           Default: ./trigger-backups-YYYYmmdd-HHMMSS
  --log <file>             Log file. Default: <backup-dir>/run.log
  --delay <seconds>        Pause between policies. Default: 0
  --include-non-self-service
                           Also modify policies that are not Self Service
                           policies. Off by default.
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
set_list=""
custom_event=""            # --custom-event: the name to set
clear_custom_event=""      # --clear-custom-event: the name to clear, and only that name
custom_event_given="no"    # either flag seen; "no" means leave every custom event alone
apply_changes="no"
confirm_token_supplied=""
allow_auto_trigger="no"
backup_dir=""
log_file=""
inter_policy_delay=0
include_non_self_service="no"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--csv)             csv_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--set)             set_list="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--custom-event)    custom_event="${2:-}"; custom_event_given="yes"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--clear-custom-event) clear_custom_event="${2:-}"; custom_event_given="yes"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--no-custom-event) echo "ERROR! --no-custom-event was replaced by --clear-custom-event <event>, which only clears the event you name."; exit 3 ;;
		--apply)           apply_changes="yes"; shift ;;
		--confirm)         confirm_token_supplied="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--allow-auto-trigger) allow_auto_trigger="yes"; shift ;;
		--backup-dir)      backup_dir="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--log)             log_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--delay)           inter_policy_delay="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--include-non-self-service) include_non_self_service="yes"; shift ;;
		--help|-h)         usage; exit 0 ;;
		*)                 echo "ERROR! Unknown argument: $1"; echo; usage; exit 3 ;;
	esac
done

if [[ -z "$csv_file" ]]; then
	echo "ERROR! --csv is required."; echo; usage; exit 3
fi

if [[ ! -f "$csv_file" ]]; then
	echo "ERROR! CSV not found: $csv_file"; exit 3
fi

# --set is required even for "turn everything off", spelled "none". An absent
# --set would make the whole run a no-op that still looked like it worked.
if [[ -z "$set_list" ]]; then
	echo "ERROR! --set is required. Use --set none to turn all five triggers off."
	echo; usage; exit 3
fi

if [[ -n "$custom_event" ]] && [[ -n "$clear_custom_event" ]]; then
	echo "ERROR! --custom-event and --clear-custom-event are mutually exclusive."
	exit 3
fi

# Either flag with an empty name is rejected outright. An empty --custom-event
# would otherwise write <trigger_other></trigger_other> to every policy in the
# CSV -- a silent clear of every custom event, with a confirmation token
# identical to the leave-alone run's.
if [[ "$custom_event_given" = "yes" ]] && [[ -z "$custom_event" ]] && [[ -z "$clear_custom_event" ]]; then
	echo "ERROR! --custom-event and --clear-custom-event each need an event name."
	exit 3
fi

# Resolve --set into the elements to turn on. Everything in
# ALL_TRIGGER_ELEMENTS and not in here is turned off.
wanted_elements=""
if [[ "$set_list" != "none" ]]; then
	# Comma list to words; bash 3.2 has no readarray, and the names cannot
	# contain whitespace, so the unquoted expansion is the intended split.
	for set_name in $(echo "$set_list" | tr ',' ' '); do
		set_element=$(ResolveTriggerElement "$set_name")
		if [[ -z "$set_element" ]]; then
			echo "ERROR! Unknown trigger in --set: ${set_name}"
			echo "       Expected a comma-separated list of: ${TRIGGER_FLAG_NAMES}"
			echo "       Or the word: none"
			ExplainRetiredTrigger "$set_name"
			exit 3
		fi
		wanted_elements="${wanted_elements} ${set_element}"
	done
fi

# The event name goes into XML, an XPath predicate and an awk pattern. No
# quoting scheme survives all three, so the character set is narrow. The
# name to clear is only compared, but it is held to the same rule so a typo
# cannot masquerade as "no policy matched".
for checked_event in "$custom_event" "$clear_custom_event"; do
	if [[ -n "$checked_event" ]] && ! echo "$checked_event" | grep -Eq '^[A-Za-z0-9._-]+$'; then
		echo "ERROR! A custom event name may contain only letters, digits and . _ -"
		echo "       Got: $checked_event"
		exit 3
	fi
done

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

# A readable description of the target state, for the run header.
target_description=""
for describe_element in ${ALL_TRIGGER_ELEMENTS}; do
	# Whole-word membership test. The padding spaces on both sides mean an
	# element name matches only as a complete word, never as part of a
	# longer one. The same test appears twice more in ProcessPolicy.
	case " ${wanted_elements} " in
		*" ${describe_element} "*)
			# :+ inserts the separator only when something precedes it.
			target_description="${target_description}${target_description:+, }$(TriggerLabel "$describe_element")"
			;;
	esac
done
if [[ -z "$target_description" ]]; then
	target_description="no automatic triggers"
fi
if [[ -n "$custom_event" ]]; then
	target_description="${target_description}, Custom: ${custom_event}"
elif [[ -n "$clear_custom_event" ]]; then
	target_description="${target_description}, custom event '${clear_custom_event}' cleared"
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

# Describes a policy's triggers the way the admin console reads them. Takes the
# Self Service flag separately because the edited <general> fragment does not
# carry the <self_service> element.
#
#   $1 policy XML, complete or just <policy><general>...</general></policy>
#   $2 the policy's use_for_self_service value ("true" or anything else)
#
# Prints e.g. "Self Service, Recurring Check-in, Custom: installChrome", or
# "none".
DescribeTriggers() {
	local xml="$1"
	local self_service="$2"
	local summary
	summary=$(GetPolicyTriggers "$xml")
	# GetPolicyTriggers already prefixes "Self Service" when the XML it was
	# given carries <self_service>, and the edited <general> fragment never
	# does. Normalise: strip whatever it added, then add the prefix back from
	# the flag every caller passes. Without this a full policy read
	# "Self Service, Self Service, ..." and could never equal the fragment's
	# summary, so every Self Service policy failed read-back.
	summary=${summary#Self Service, }
	summary=${summary#Self Service}
	if [[ "$summary" = "none" ]]; then
		summary=""
	fi
	if [[ "$self_service" = "true" ]]; then
		# :+ adds the comma only when there is a summary to follow it.
		summary="Self Service${summary:+, }${summary}"
	fi
	echo "${summary:-none}"
}

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
	local policy_enabled
	local before_summary
	local after_summary
	local current_custom
	local formatted_xml
	local general_xml
	local new_general
	local element
	local want
	local turning_on_auto
	local payload
	local verify_xml
	local verify_summary

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

	policy_enabled=$(GetPolicyEnabled "$policy_xml")
	current_custom=$(GetPolicyTriggerState "$policy_xml" trigger_other)
	before_summary=$(DescribeTriggers "$policy_xml" "$self_service_flag")

	# The custom event is only ever written when the caller named what is
	# there. A policy carrying some other name is skipped whole -- the booleans
	# are not set either -- so a declarative run never leaves a policy half
	# done. "jamf policy -event <old>" matching nothing is a success for the
	# jamf binary, so a wrongly cleared or repointed event breaks every caller
	# with nothing in any log.
	if [[ -n "$custom_event" ]] && [[ -n "$current_custom" ]] && [[ "$current_custom" != "$custom_event" ]]; then
		log_line "SKIPPED  ${policy_id} (${policy_name}): custom event is '${current_custom}', not '${custom_event}'. Use Rename_Policy_Trigger.sh --from '${current_custom}' --to '${custom_event}' first."
		policies_skipped=$((policies_skipped + 1))
		return
	fi
	if [[ -n "$clear_custom_event" ]] && [[ -n "$current_custom" ]] && [[ "$current_custom" != "$clear_custom_event" ]]; then
		log_line "SKIPPED  ${policy_id} (${policy_name}): custom event is '${current_custom}', not '${clear_custom_event}'. Nothing changed on this policy."
		policies_skipped=$((policies_skipped + 1))
		return
	fi

	# Refuse before editing: turning an automatic trigger ON for an enabled
	# policy runs it on every Mac in scope at the next trigger. Only a trigger
	# that is not already on counts -- leaving one alone changes nothing.
	turning_on_auto="no"
	for element in ${ALL_TRIGGER_ELEMENTS}; do
		# Same whole-word membership test as the run-header loop above.
		case " ${wanted_elements} " in
			*" ${element} "*)
				if [[ "$(GetPolicyTriggerState "$policy_xml" "$element")" != "true" ]]; then
					turning_on_auto="yes"
				fi
				;;
		esac
	done

	if [[ "$turning_on_auto" = "yes" ]] && [[ "$policy_enabled" = "true" ]] && [[ "$allow_auto_trigger" != "yes" ]]; then
		log_line "REFUSED  ${policy_id} (${policy_name}): policy is enabled; this would newly arm an automatic trigger and run it on every targeted Mac. --allow-auto-trigger overrides."
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

	# Send the complete <general> element. Jamf Pro's Classic API replaces the
	# content of any element a request supplies, so a PUT carrying only the
	# trigger fields could drop the policy's name, category and frequency.
	general_xml=$(echo "$formatted_xml" | awk '/^[[:space:]]*<general>[[:space:]]*$/,/^[[:space:]]*<\/general>[[:space:]]*$/')
	if [[ -z "$general_xml" ]]; then
		log_line "FAILED   ${policy_id} (${policy_name}): no <general> element in the policy."
		policies_failed=$((policies_failed + 1))
		return
	fi

	# Every boolean, every time. Chained because each call takes and returns the
	# whole <general>, so the next one sees the previous edit.
	new_general="$general_xml"
	for element in ${ALL_TRIGGER_ELEMENTS}; do

		want="false"
		# Same whole-word membership test as the run-header loop above.
		case " ${wanted_elements} " in
			*" ${element} "*) want="true" ;;
		esac

		# The if tests the substitution's status, which is the library
		# function's exit code, so a node that could not be placed is caught
		# here, not later.
		if ! new_general=$(ReplaceElementInSection "$new_general" general "$element" "<${element}>${want}</${element}>") ||
		   [[ -z "$new_general" ]]; then
			log_line "FAILED   ${policy_id} (${policy_name}): could not place <${element}> in <general>."
			policies_failed=$((policies_failed + 1))
			return
		fi

		# The trigger fields are leaves, so a bug in the replacement shows up as
		# two of them rather than as a parse error.
		if [[ "$(echo "$new_general" | grep -c "<${element}>")" -ne 1 ]]; then
			log_line "FAILED   ${policy_id} (${policy_name}): edited <general> does not contain exactly one <${element}>."
			policies_failed=$((policies_failed + 1))
			return
		fi

	done

	# Write the custom event only when the guard above let this policy through:
	# --custom-event sets it (the policy has none, or already this name);
	# --clear-custom-event empties it (the policy has exactly this name). With
	# neither flag the element is untouched and the run says so.
	#
	# On a clear, custom_event is empty and this writes
	# <trigger_other></trigger_other>. UNVERIFIED that Jamf Pro reads an empty
	# element as "no custom event" rather than rejecting it; the read-back
	# reports it either way. See the header.
	if [[ -n "$custom_event" ]] || { [[ -n "$clear_custom_event" ]] && [[ -n "$current_custom" ]]; }; then
		if ! new_general=$(ReplaceElementInSection "$new_general" general trigger_other "<trigger_other>${custom_event}</trigger_other>") ||
		   [[ -z "$new_general" ]]; then
			log_line "FAILED   ${policy_id} (${policy_name}): could not place <trigger_other> in <general>."
			policies_failed=$((policies_failed + 1))
			return
		fi
		# Same exactly-one guard as the booleans: a duplicate here would be
		# well-formed XML that Jamf accepts and resolves however it likes.
		if [[ "$(echo "$new_general" | grep -c '<trigger_other>')" -ne 1 ]]; then
			log_line "FAILED   ${policy_id} (${policy_name}): edited <general> does not contain exactly one <trigger_other>."
			policies_failed=$((policies_failed + 1))
			return
		fi
	elif [[ -n "$current_custom" ]]; then
		log_line "         note: ${policy_id} (${policy_name}) keeps custom event '${current_custom}'. Pass --clear-custom-event '${current_custom}' to clear it."
	fi

	after_summary=$(DescribeTriggers "<policy>${new_general}</policy>" "$self_service_flag")

	# ALREADY is decided on the rendered summaries, not the XML: the summary
	# is what the operator sees, and equal summaries mean no visible change.
	# A difference of case or whitespace in the XML is not a change.
	if [[ "$before_summary" = "$after_summary" ]]; then
		log_line "ALREADY  ${policy_id} (${policy_name}): ${before_summary}"
		policies_already=$((policies_already + 1))
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

	# A policy with nothing left to run it stays enabled and never runs again.
	# Reported, not refused: it is still visible in the UI and easy to undo.
	if [[ "$after_summary" = "none" ]]; then
		log_line "         note: ${policy_id} (${policy_name}) will have no trigger and no Self Service entry -- nothing can run it."
	fi

	if [[ "$apply_changes" != "yes" ]]; then
		log_line "WOULD SET ${policy_id} (${policy_name}): enabled=${policy_enabled:-none}"
		log_line "              ${before_summary}"
		log_line "           -> ${after_summary}"
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

	# Read back. An accepted PUT is not proof the values landed.
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

	# The Self Service flag is re-read from the verify GET rather than reused:
	# the PUT sent only <general>, but the summary should describe what is
	# actually on the server now.
	verify_summary=$(DescribeTriggers "$verify_xml" "$(GetPolicySelfService "$verify_xml")")

	if [[ "$verify_summary" = "$after_summary" ]]; then
		log_line "SET      ${policy_id} (${policy_name}): ${before_summary} -> ${verify_summary}"
		policies_updated=$((policies_updated + 1))
	else
		log_line "FAILED   ${policy_id} (${policy_name}): PUT returned ${http_code} but the triggers read back as '${verify_summary}', wanted '${after_summary}'."
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

# The confirmation token is derived from the run. The target state can be five
# names long, so it is hashed rather than spelled out; the run header prints the
# state in full right above it.
# -q prints the bare digest; eight hex characters tell any two CSVs apart
# and are short enough to type.
spec_digest=$(echo "${wanted_elements}|${custom_event}|${clear_custom_event}" | /sbin/md5 -q | cut -c1-8)
confirm_token="SET-TRIGGERS-${policies_total}-${spec_digest}"

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

log_line "Set_Policy_Triggers.sh ${SCRIPT_VERSION}"
log_line "Jamf Pro:   ${jamfpro_url}"
log_line "CSV:        ${csv_file} (${policies_total} policy IDs)"
log_line "Target:     ${target_description}"
if [[ "$custom_event_given" != "yes" ]]; then
	log_line "            custom events are left as they are"
fi
log_line "Backups:    ${backup_dir}"
if [[ "$apply_changes" = "yes" ]]; then
	log_line "Mode:       APPLY -- policies will be modified"
else
	log_line "Mode:       DRY RUN -- nothing will be modified"
fi
log_line ""
log_line "Every trigger not named in --set is turned OFF."
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
log_line "Already matched:  ${policies_already}"
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
