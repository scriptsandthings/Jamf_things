#!/bin/bash

# This script uses the Jamf Pro Classic API to detect which Jamf Pro policies are
# Self Service policies and generates a report with information about those
# policies.
#
# Authentication uses a Jamf Pro API Client (client ID + client secret) via the
# OAuth client_credentials grant. Username/password Basic authentication is no
# longer used.
#
# Prerequisites, in Jamf Pro:
#   Settings > System > API Roles and Clients
#     1. Create an API Role with the "Read Policies" privilege.
#     2. Create an API Client, assign that role, enable it, and generate a secret.
#
# Note: the Classic API /JSSResource/policies endpoints are still supported. The
# Classic API deprecation that closed in March 2026 covered /JSSResource/computers*
# only.
#
# Usage:
#   Generate_Self_Service_Policy_Report.sh [--output <file.csv>] [--help]
#
# Read-only: this script never writes to Jamf Pro. It is the safe first contact
# for the shared library, and its CSV is what the fourteen writer scripts in
# this directory take as their --csv input (they read the policy ID from the
# first column and skip the header row).
#
# Credentials come from the com.github.jamfpro-info preference file, the
# JAMF_PRO_URL / JAMF_PRO_CLIENT_ID / JAMF_PRO_CLIENT_SECRET variables, or a
# prompt; the library resolves them, in that order. Output is a 13-column CSV
# whose path is printed at the end (--output, else a fresh directory under
# $TMPDIR). Needs lib/jamf-api-common.sh next to this script, plus curl,
# xmllint and plutil from the base OS.
#
# Exit codes:
#   0  report written
#   1  could not authenticate, could not list policies, or at least one policy
#      could not be read (the report is still written for the rest)
#   3  usage error
#   130  interrupted (HUP, INT, QUIT or TERM); the token is still revoked

# -u only, as in the writers: every expansion is guarded, and an unset name
# is a bug worth stopping on. No -e: a policy that cannot be read is counted
# and the run continues.
set -u

# Set default exit code
exitCode=0

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

usage() {
	cat <<'EOF'
Report every Self Service policy in Jamf Pro as a CSV file (every field quoted).

Usage:
  Generate_Self_Service_Policy_Report.sh [--output <file.csv>]

Options:
  --output <file>   Where to write the report. Default: a timestamped .csv in a
                    fresh temporary directory; the path is printed at the end.
  --help            This text.

Credentials come from the environment (JAMF_PRO_URL, JAMF_PRO_CLIENT_ID,
JAMF_PRO_CLIENT_SECRET), the com.github.jamfpro-info preference file, or a
prompt. The API client needs only "Read Policies".

Columns (13): Jamf Pro ID, Self Service Policy, Policy Enabled, Policy Name,
Category, Self Service Display Name, SS Categories (Display), SS Categories
(Featured), Featured on Main Page, Scope Targets, Scope Limitations, Scope
Exclusions, Jamf Pro URL.

Exit codes:
  0  report written
  1  auth or listing failed, or at least one policy could not be read
  3  usage error
  130  interrupted by a signal; the token is revoked and nothing further is written
EOF
}

report_file=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--output)  report_file="${2:-}"; shift 2 || { echo "ERROR! $1 needs a value."; exit 3; } ;;
		--help|-h) usage; exit 0 ;;
		*)         echo "ERROR! Unknown argument: $1"; echo; usage; exit 3 ;;
	esac
done

# The default lands in a directory made for it. The earlier "$(mktemp).tsv"
# form created a suffix-less temp file as well and left it behind empty.
if [[ -z "$report_file" ]]; then
	report_file="$(mktemp -d "${TMPDIR:-/tmp}/self-service-report.XXXXXX")/self-service-policies-$(date '+%Y%m%d-%H%M%S').csv"
fi

# Shared Jamf Pro API helpers. This script uses the curl defaults, the OAuth
# token lifecycle, credential resolution, FetchPolicyXML, DecodeXMLEntities
# and GetPolicyName; the scope editors and the CSV reader are for the writers.
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
# Helpers
# ---------------------------------------------------------------------------

# Prints its arguments as one CSV row, RFC 4180 style: every field wrapped in
# double quotes, any double quote inside a field doubled, CRLF line ending.
# Quoting every field, not just the ones that need it, keeps the row shape
# obvious and lets policy names carry commas, semicolons and quotes without a
# per-field decision. Excel and Numbers open it directly; the writers' CSV
# reader strips the quotes off the ID column.
#
#   $@ the fields, in order

WriteCSVRow() {

	local field
	local row=""

	for field in "$@"; do
		field=${field//\"/\"\"}
		row="${row}${row:+,}\"${field}\""
	done

	# %s: a policy name can contain a percent sign, which printf would
	# otherwise read as a format specifier.
	printf '%s\r\n' "$row"

}

# Joins the text of every element matched by an XPath into a single
# semicolon-separated string. xmllint's --xpath concatenates matched text nodes
# with no delimiter, so the elements are serialized and their tags are turned
# into separators instead. XML entities are decoded afterwards, &amp; last so
# that an encoded entity is not decoded twice.
#
#   $1 policy XML
#   $2 XPath selecting the elements (not their text())
#   $3 the element's tag, default "name". limit_to_users/user_groups/user_group
#      is the one list Jamf stores as a bare string element, with no <name>.

ExtractNameList() {

	local xml_data="$1"
	local xpath_expression="$2"
	local tag="${3:-name}"

	echo "$xml_data" | xmllint --xpath "$xpath_expression" - 2>/dev/null \
	  | sed -e "s|</${tag}>|; |g" -e "s|<${tag}>||g" -e "s|<${tag}/>||g" \
	  | tr '\n\t' '  ' | tr -s ' ' \
	  | DecodeXMLEntities \
	  | sed -e 's|[[:space:]]*;[[:space:]]*$||' -e 's|^[[:space:]]*||' -e 's|[[:space:]]*$||'

}

# Appends "<label>: <value>" to a running list, skipping empty values. Used to
# build one scope column out of several scope sub-elements.

AppendScopeItem() {

	local existing="$1"
	local label="$2"
	local value="$3"

	if [[ -z "$value" ]]; then
		echo "$existing"
	elif [[ -z "$existing" ]]; then
		echo "${label}: ${value}"
	else
		echo "${existing} | ${label}: ${value}"
	fi

}

# Returns the Self Service categories whose named flag is true, as a
# semicolon-separated list. Each <category> carries its own <display_in> and
# <feature_in>, so the nodes have to be walked one at a time with an indexed
# predicate -- a flat match of every <name> would lose which name went with
# which flag. These are all local xmllint calls against XML already in memory;
# no additional API requests.

ExtractSelfServiceCategories() {

	local xml_data="$1"
	local flag_element="$2"
	local category_count
	local category_index=1
	local category_name
	local flag_value
	local result=""

	category_count=$(echo "$xml_data" | xmllint --xpath 'count(/policy/self_service/self_service_categories/category)' - 2>/dev/null)

	# count() returns a plain integer, but guard anyway: a malformed response
	# would otherwise put a non-number into the loop condition.
	case "$category_count" in
	    ''|*[!0-9]*) echo ""; return ;;
	esac

	while [[ "$category_index" -le "$category_count" ]]; do

		flag_value=$(echo "$xml_data" | xmllint --xpath "/policy/self_service/self_service_categories/category[${category_index}]/${flag_element}/text()" - 2>/dev/null)

		if [[ "$flag_value" = "true" ]]; then
			category_name=$(ExtractNameList "$xml_data" "/policy/self_service/self_service_categories/category[${category_index}]/name")
			if [[ -n "$category_name" ]]; then
				if [[ -z "$result" ]]; then
					result="$category_name"
				else
					result="${result}; ${category_name}"
				fi
			fi
		fi

		category_index=$((category_index + 1))

	done

	echo "$result"

}

# Downloads one policy as XML and, if it is a Self Service policy, appends one
# row to the report. A policy that cannot be read is counted in
# policies_unreadable and named on stderr rather than silently left out: a
# report presented as complete must not be missing rows nobody knows about.
# Prints nothing on stdout; the row is appended straight to report_file, whose
# header row is written before the loop starts. Never exits.
#
#   $1 policy ID

policies_unreadable=0

CheckSelfServicePolicies(){

	local PolicyId="$1"
	local DownloadedXMLData
	local PolicyName
	local SelfServicePolicyCheck

	if [[ -n "$PolicyId" ]]; then

		# FetchPolicyXML (library) accepts only an HTTP 200 whose body parses;
		# anything else is reported and skipped. On failure it prints the reason
		# instead of a body. Token renewal stays out here: $( ) is a subshell.
		CheckAndRenewAPIToken
		if ! DownloadedXMLData=$(FetchPolicyXML "$PolicyId"); then
			echo "ERROR! Policy ${PolicyId}: ${DownloadedXMLData}. Left out of the report." >&2
			policies_unreadable=$((policies_unreadable + 1))
			return
		fi

		# Entity-decoded: the CSV is read by people and by Excel, not by Jamf.
		PolicyName=$(GetPolicyName "$DownloadedXMLData")
		SelfServicePolicyCheck=$(echo "$DownloadedXMLData" | xmllint --xpath '/policy/self_service/use_for_self_service/text()' - 2>/dev/null)

		# Only Self Service policies make the report. Everything below is local
		# parsing of XML already in memory; no further API requests.
		if [[ "$SelfServicePolicyCheck" = "true" ]]; then

			JamfProID=$(echo "$DownloadedXMLData" | xmllint --xpath '/policy/general/id/text()' - 2>/dev/null)
			PolicyEnabled=$(echo "$DownloadedXMLData" | xmllint --xpath '/policy/general/enabled/text()' - 2>/dev/null)
			PolicyCategory=$(echo "$DownloadedXMLData" | xmllint --xpath '/policy/general/category/name/text()' - 2>/dev/null | DecodeXMLEntities)
			SelfServiceDisplayName=$(echo "$DownloadedXMLData" | xmllint --xpath '/policy/self_service/self_service_display_name/text()' - 2>/dev/null | DecodeXMLEntities)

			# Self Service categories. Each category carries display_in and feature_in
			# independently, so a policy can be featured in a category it also displays
			# in, or display in several and be featured in none. feature_on_main_page is
			# a separate policy-level flag and is not a category at all.

			SelfServiceCategoriesDisplay=$(ExtractSelfServiceCategories "$DownloadedXMLData" "display_in")
			SelfServiceCategoriesFeatured=$(ExtractSelfServiceCategories "$DownloadedXMLData" "feature_in")
			if [[ -z "$SelfServiceCategoriesDisplay" ]]; then
			   SelfServiceCategoriesDisplay="None"
			fi
			if [[ -z "$SelfServiceCategoriesFeatured" ]]; then
			   SelfServiceCategoriesFeatured="None"
			fi

			FeatureOnMainPage=$(echo "$DownloadedXMLData" | xmllint --xpath "/policy/self_service/feature_on_main_page/text()" - 2>/dev/null)
			if [[ -z "$FeatureOnMainPage" ]]; then
			   FeatureOnMainPage="false"
			fi
			# Admin console deep link for the row.
			JamfProURL="${jamfpro_url}/policies.html?id=${JamfProID}"

			# Scope targets. "All Computers" is reported on its own; anything else
			# is listed by type. A policy scoped to all computers can still carry
			# additional targets, so both are collected.

			ScopeAllComputers=$(echo "$DownloadedXMLData" | xmllint --xpath '/policy/scope/all_computers/text()' - 2>/dev/null)
			ScopeTargets=""
			if [[ "$ScopeAllComputers" = "true" ]]; then
			   ScopeTargets="All Computers"
			fi
			ScopeTargets=$(AppendScopeItem "$ScopeTargets" "Groups"      "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/computer_groups/computer_group/name')")
			ScopeTargets=$(AppendScopeItem "$ScopeTargets" "Computers"   "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/computers/computer/name')")
			ScopeTargets=$(AppendScopeItem "$ScopeTargets" "Buildings"   "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/buildings/building/name')")
			ScopeTargets=$(AppendScopeItem "$ScopeTargets" "Departments" "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/departments/department/name')")
			if [[ -z "$ScopeTargets" ]]; then
			   ScopeTargets="No targets"
			fi

			# Scope limitations. limit_to_users holds the "Limit to users in LDAP
			# groups" setting, which Jamf Pro stores outside the limitations
			# element -- and, per the Classic API schema, as a bare
			# <user_group>Name</user_group> string with no <name> child. The
			# earlier ".../user_group/name" path matched nothing, so this column
			# was always empty.

			ScopeLimitations=""
			ScopeLimitations=$(AppendScopeItem "$ScopeLimitations" "Users"            "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/limitations/users/user/name')")
			ScopeLimitations=$(AppendScopeItem "$ScopeLimitations" "User Groups"      "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/limitations/user_groups/user_group/name')")
			ScopeLimitations=$(AppendScopeItem "$ScopeLimitations" "LDAP Groups"      "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/limit_to_users/user_groups/user_group' user_group)")
			ScopeLimitations=$(AppendScopeItem "$ScopeLimitations" "Network Segments" "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/limitations/network_segments/network_segment/name')")
			ScopeLimitations=$(AppendScopeItem "$ScopeLimitations" "iBeacons"         "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/limitations/ibeacons/ibeacon/name')")
			if [[ -z "$ScopeLimitations" ]]; then
			   ScopeLimitations="None"
			fi

			# Scope exclusions.

			ScopeExclusions=""
			ScopeExclusions=$(AppendScopeItem "$ScopeExclusions" "Groups"           "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/exclusions/computer_groups/computer_group/name')")
			ScopeExclusions=$(AppendScopeItem "$ScopeExclusions" "Computers"        "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/exclusions/computers/computer/name')")
			ScopeExclusions=$(AppendScopeItem "$ScopeExclusions" "Buildings"        "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/exclusions/buildings/building/name')")
			ScopeExclusions=$(AppendScopeItem "$ScopeExclusions" "Departments"      "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/exclusions/departments/department/name')")
			ScopeExclusions=$(AppendScopeItem "$ScopeExclusions" "Users"            "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/exclusions/users/user/name')")
			ScopeExclusions=$(AppendScopeItem "$ScopeExclusions" "User Groups"      "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/exclusions/user_groups/user_group/name')")
			ScopeExclusions=$(AppendScopeItem "$ScopeExclusions" "Network Segments" "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/exclusions/network_segments/network_segment/name')")
			ScopeExclusions=$(AppendScopeItem "$ScopeExclusions" "iBeacons"         "$(ExtractNameList "$DownloadedXMLData" '/policy/scope/exclusions/ibeacons/ibeacon/name')")
			if [[ -z "$ScopeExclusions" ]]; then
			   ScopeExclusions="None"
			fi

			if [[ -n "$JamfProID" ]]; then
			   WriteCSVRow "$JamfProID" "$SelfServicePolicyCheck" "$PolicyEnabled" "$PolicyName" \
			       "$PolicyCategory" "$SelfServiceDisplayName" \
			       "$SelfServiceCategoriesDisplay" "$SelfServiceCategoriesFeatured" "$FeatureOnMainPage" \
			       "$ScopeTargets" "$ScopeLimitations" "$ScopeExclusions" "$JamfProURL" >> "$report_file"
			else
			   echo "ERROR! Policy ${PolicyId} (${PolicyName}): parsed but has no general/id. Left out of the report." >&2
			   policies_unreadable=$((policies_unreadable + 1))
			fi
		fi
	fi
}

# A one-character spinner so a long run visibly has not hung. ASCII only:
# a Braille glyph is three bytes, and without a UTF-8 locale (launchd, a Jamf
# policy, cron) bash slices bytes rather than characters and prints garbage.
# Only started when stdout is a terminal. \b is a backspace, so each glyph
# overwrites the last. Loops until killed, by the EXIT trap or the explicit
# kill after the policy loop.
progress_indicator() {
	local spinner="|/-\\"
	local i
	while :; do
		for i in 0 1 2 3; do
			printf '%s\b' "${spinner:$i:1}"
			sleep 0.10
		done
	done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Traps first, then the token. The EXIT trap (0) stops the spinner and revokes
# the token however the script ends; the signal traps exit explicitly (which
# fires the EXIT trap) rather than let the loop carry on after Ctrl-C. Signal
# 9 cannot be trapped, which is why the list is spelled out rather than
# generated with seq. Single quotes on the EXIT trap are deliberate: SPIN_PID
# is empty here and set later, so it has to expand when the trap fires.
SPIN_PID=""
trap 'if [[ -n "$SPIN_PID" ]]; then kill "$SPIN_PID" 2>/dev/null; fi; InvalidateAPIToken' 0
trap 'exit 130' 1 2 3 15

# Fills jamfpro_url, jamfpro_client_id and jamfpro_client_secret from the
# preference file, the environment, or a prompt. See the library for the exact
# order and for the `defaults write` commands that populate the preference file.
ResolveJamfProCredentials

# Get a Jamf Pro API access token. Exits the script on failure.
GetJamfProAPIToken

echo "Report being generated. File location will appear below once ready."

if [[ -t 1 ]]; then
	progress_indicator &
	SPIN_PID=$!
fi

# Download every policy ID. The list endpoint returns <policies><policy><id>.
# An empty result is an error, not "no policies": a tenant always has at
# least the policies Jamf creates itself, so nothing back means the request
# failed (privilege, URL, network) and the report would be silently empty.
# No HTTP status is read on this one curl; the empty check below stands in
# for it, since any non-200 body has no <policies><policy><id> to match.
CheckAndRenewAPIToken
PolicyIDList=$(/usr/bin/curl -s "${curl_timeouts[@]}" --header "Authorization: Bearer ${api_token}" -H "Accept: application/xml" "${jamfpro_url}/JSSResource/policies" | xmllint --xpath '/policies/policy/id' - 2>/dev/null)

# xmllint prints the matched <id>N</id> elements run together on one line;
# grep -Eo pulls out the digits one per line, and grep -c ^ counts the lines.
PolicyIDs=$(echo "$PolicyIDList" | grep -Eo "[0-9]+")
PoliciesCount=$(echo "$PolicyIDs" | grep -c ^)

if [[ -z "$PolicyIDs" ]]; then
	echo "ERROR! Could not list policies from ${jamfpro_url}/JSSResource/policies."
	echo "       Check the API role has Read Policies and that the URL is the Jamf Pro instance."
	exit 1
fi

echo "Checking $PoliciesCount policies for Self Service policies ..."
echo

# Write the header up front so a tenant with no Self Service policies still
# gets a (header-only) report rather than a "not found" error.
mkdir -p "$(dirname "$report_file")" || { echo "ERROR! Cannot create $(dirname "$report_file")"; exit 1; }
WriteCSVRow "Jamf Pro ID Number" "Self Service Policy" "Policy Enabled" "Policy Name" \
    "Category" "Self Service Display Name" "SS Categories (Display)" "SS Categories (Featured)" \
    "Featured on Main Page" "Scope Targets" "Scope Limitations" "Scope Exclusions" "Jamf Pro URL" > "$report_file"

# Generate report of Self Service policies. PolicyIDs is one ID per line;
# the unquoted expansion is the intended word split.
for anID in ${PolicyIDs}; do

   CheckSelfServicePolicies "$anID"

done

# Stop the spinner before the summary prints over it, and revoke the token
# now rather than at exit. The EXIT trap runs both again; both are idempotent.
if [[ -n "$SPIN_PID" ]]; then
	kill "$SPIN_PID" 2>/dev/null
	SPIN_PID=""
fi

InvalidateAPIToken

# Lines in the report minus the header row.
SelfServiceCount=$(( $(grep -c ^ "$report_file") - 1 ))
echo "Self Service policies found: ${SelfServiceCount} of ${PoliciesCount}"
echo "Report on Self Service policies available here: $report_file"

if [[ "$policies_unreadable" -gt 0 ]]; then
	echo "ERROR! ${policies_unreadable} of ${PoliciesCount} policies could not be read and are missing from the report (see above)."
	exitCode=1
fi

exit $exitCode
