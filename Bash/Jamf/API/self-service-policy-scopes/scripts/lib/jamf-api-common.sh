#!/bin/bash
#
# Shared Jamf Pro API helpers for the scripts in this directory.
#
# Source it, do not run it:
#
#   SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
#   . "${SCRIPT_DIR}/lib/jamf-api-common.sh"
#
# Sourcing defines functions and defaults and does nothing else. Nothing here
# makes a network call or reads a credential until you call it.
#
# What lives here: the OAuth token lifecycle, credential resolution,
# FetchPolicyXML (the one status-checked Classic GET), the CSV reader,
# DecodeXMLEntities and GetPolicyName, the <scope> insert / remove / count
# functions, ReplaceElementInSection (the single-element replacer), the policy
# getters (category, enabled, triggers, trigger state, the legacy trigger,
# Self Service) and the trigger name maps. Argument parsing and the per-policy
# loop stay in each script, because that is where they differ.
#
# Needs curl, plutil, xmllint, awk, sed and defaults, all base macOS. Callers
# also use /sbin/md5 for their confirmation tokens.
#
# Exit codes: GetJamfProAPIToken is the only function that exits the calling
# script (1, no token could be issued). InsertScopeEntry, RemoveScopeEntry and
# ReplaceElementInSection return 1 as a function status when the awk pass
# placed or removed nothing; callers test that status, never the output.
#
# Bash 3.2 compatible -- macOS /bin/bash is 3.2.57 through Tahoe 26.

# ---------------------------------------------------------------------------
# Defaults and token state
# ---------------------------------------------------------------------------

# Never issue an unbounded request. A hung curl in one of these scripts is a
# report or a bulk edit that stops halfway with no indication why.
curl_timeouts=(--connect-timeout 15 --max-time 30)

# Seconds of remaining token life at which the token is proactively replaced.
token_renewal_buffer=90

# Token state. Set by GetJamfProAPIToken, cleared by InvalidateAPIToken, read
# by every curl. The check variable is written by APITokenValidCheck only.
api_token=""
api_token_expiration_epoch=0
api_authentication_check=""

# Set by ResolveJamfProCredentials. A caller that exports any of these before
# sourcing skips that source; nothing in this repo does so, and no script has
# a header these could be read from.
jamfpro_url="${jamfpro_url:-}"
jamfpro_client_id="${jamfpro_client_id:-}"
jamfpro_client_secret="${jamfpro_client_secret:-}"

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------

# Fills jamfpro_url, jamfpro_client_id and jamfpro_client_secret from, in order:
# whatever the caller already set, the preference file, the environment, and
# finally an interactive prompt. First non-empty value wins.
#
# Blocks on a TTY prompt when a value is still missing, so this library is not
# usable from cron or a Jamf policy without the preference file or the
# JAMF_PRO_URL / JAMF_PRO_CLIENT_ID / JAMF_PRO_CLIENT_SECRET variables set.
#
#   defaults write $HOME/Library/Preferences/com.github.jamfpro-info jamfpro_url https://your.jamfcloud.com
#   defaults write $HOME/Library/Preferences/com.github.jamfpro-info jamfpro_client_id <client-id>
#   defaults write $HOME/Library/Preferences/com.github.jamfpro-info jamfpro_client_secret <client-secret>

ResolveJamfProCredentials() {

	if [[ -f "$HOME/Library/Preferences/com.github.jamfpro-info.plist" ]]; then

		if [[ -z "$jamfpro_url" ]]; then
			jamfpro_url=$(defaults read "$HOME"/Library/Preferences/com.github.jamfpro-info jamfpro_url 2>/dev/null)
		fi

		if [[ -z "$jamfpro_client_id" ]]; then
			jamfpro_client_id=$(defaults read "$HOME"/Library/Preferences/com.github.jamfpro-info jamfpro_client_id 2>/dev/null)
		fi

		if [[ -z "$jamfpro_client_secret" ]]; then
			jamfpro_client_secret=$(defaults read "$HOME"/Library/Preferences/com.github.jamfpro-info jamfpro_client_secret 2>/dev/null)
		fi

	fi

	if [[ -z "$jamfpro_url" ]] && [[ -n "${JAMF_PRO_URL:-}" ]]; then
		jamfpro_url="$JAMF_PRO_URL"
	fi

	if [[ -z "$jamfpro_client_id" ]] && [[ -n "${JAMF_PRO_CLIENT_ID:-}" ]]; then
		jamfpro_client_id="$JAMF_PRO_CLIENT_ID"
	fi

	if [[ -z "$jamfpro_client_secret" ]] && [[ -n "${JAMF_PRO_CLIENT_SECRET:-}" ]]; then
		jamfpro_client_secret="$JAMF_PRO_CLIENT_SECRET"
	fi

	if [[ -z "$jamfpro_url" ]]; then
		read -r -p "Please enter your Jamf Pro server URL : " jamfpro_url
	fi

	if [[ -z "$jamfpro_client_id" ]]; then
		read -r -p "Please enter your Jamf Pro API client ID : " jamfpro_client_id
	fi

	if [[ -z "$jamfpro_client_secret" ]]; then
		# -s so the secret is not echoed and does not reach the scrollback.
		read -r -p "Please enter the client secret for the $jamfpro_client_id API client: " -s jamfpro_client_secret
		echo
	fi

	# A trailing slash would produce //api/v1/... on every request. This strips
	# one slash: %% with a literal single-character pattern is the same as %.
	jamfpro_url=${jamfpro_url%%/}

}

# ---------------------------------------------------------------------------
# Token lifecycle
# ---------------------------------------------------------------------------

# Requests an access token with the OAuth client_credentials grant and records
# when it expires. Exits the calling script on failure: every script here is
# useless without a token, and continuing would produce a run of 401s that look
# like missing policies.

GetJamfProAPIToken() {

	local response
	local http_code
	local token_response

	# The status rides on the last line so one call yields both. No --fail:
	# a 401 body is worth keeping for the message below, and the status code
	# is what tells a bad secret apart from a disabled integration.
	response=$(/usr/bin/curl --silent \
	    "${curl_timeouts[@]}" \
	    --write-out "\nHTTP_CODE:%{http_code}" \
	    --request POST \
	    --header "Content-Type: application/x-www-form-urlencoded" \
	    --data-urlencode "grant_type=client_credentials" \
	    --data-urlencode "client_id=${jamfpro_client_id}" \
	    --data-urlencode "client_secret=${jamfpro_client_secret}" \
	    "${jamfpro_url}/api/v1/oauth/token" 2>/dev/null)

	http_code=$(echo "$response" | tail -1 | sed 's/^HTTP_CODE://')
	token_response=$(echo "$response" | sed '$d')

	# plutil, not python3 or jq: /usr/bin/python3 is a CLT stub on macOS 12+
	# and jq is not base OS (repo constraint 2). plutil reads JSON natively.
	api_token=$(echo "$token_response" | /usr/bin/plutil -extract access_token raw - 2>/dev/null)

	local expires_in
	expires_in=$(echo "$token_response" | /usr/bin/plutil -extract expires_in raw - 2>/dev/null)

	# plutil returns whatever it found with no validation. Guard before this
	# reaches arithmetic -- a malformed response would otherwise abort the run
	# inside $(( )). Jamf's own CLI treats a missing expires_in as a hard
	# error; this falls back to five minutes and says so, because the token
	# itself is present and the renewal check will simply fire early.
	case "$expires_in" in
		''|*[!0-9]*)
			if [[ -n "$api_token" ]]; then
				echo "WARNING: token response carried no usable expires_in; assuming 300 seconds."
			fi
			expires_in=300
			;;
	esac

	# Stored already minus the renewal buffer, so CheckAndRenewAPIToken
	# compares against now directly.
	api_token_expiration_epoch=$(( $(date +%s) + expires_in - token_renewal_buffer ))

	# Three distinct failures, three distinct messages, the way Jamf's own
	# CLI reports them: the status separates "wrong secret" from "client
	# disabled" from "cannot reach the server", and each is fixed somewhere
	# different.
	if [[ -z "$api_token" ]]; then
		echo "ERROR! Failed to get an access token from ${jamfpro_url}/api/v1/oauth/token (HTTP ${http_code:-000})."
		case "$http_code" in
			000|'')  echo "       curl could not complete the request: check the URL, DNS, TLS and the network." ;;
			400|401) echo "       Jamf Pro rejected the client credentials: check the client ID and secret." ;;
			200)     echo "       Jamf Pro answered 200 without an access_token: check that the API client is enabled" ;
			         echo "       (Settings > System > API Roles and Clients) and has a role assigned." ;;
			*)       echo "       Unexpected response$(DescribeHTTPStatus "$http_code")." ;;
		esac
		exit 1
	fi

}

# Prints a short human hint for an HTTP status, with a leading space, or
# nothing for statuses that need none. For log lines: "PUT returned HTTP 409
# (Conflict: a required field is missing...)". The vocabulary follows Jamf's
# own API helper and the wire-checked notes in jamf-cli.
#
#   $1 HTTP status as curl reports it (000 when no response was received)

DescribeHTTPStatus() {

	case "$1" in
		000|'') echo " (no HTTP response: connection refused, timed out, DNS or TLS failure)" ;;
		400)    echo " (Bad Request: the server could not parse the request)" ;;
		401)    echo " (Unauthorized: the token was rejected)" ;;
		403)    echo " (Forbidden: the API role lacks the privilege for this call)" ;;
		404)    echo " (Not Found: no policy with that ID)" ;;
		409)    echo " (Conflict: the Classic API answers 409 when a required field is missing or a value is invalid; the detail is inside an HTML page)" ;;
		429)    echo " (Too Many Requests: rate limited even after retrying)" ;;
		502)    echo " (Bad Gateway: usually a timeout upstream of the instance)" ;;
		503)    echo " (Service Unavailable: the instance is restarting or overloaded)" ;;
		504)    echo " (Gateway Timeout)" ;;
		*)      echo "" ;;
	esac

}

# Sets api_authentication_check to the HTTP status of an authenticated request.
# No arguments. Side effect only: the status of GET /api/v1/auth lands in
# api_authentication_check, and nothing is printed.

APITokenValidCheck() {

	api_authentication_check=$(/usr/bin/curl --write-out "%{http_code}" --silent --output /dev/null \
	    "${curl_timeouts[@]}" \
	    "${jamfpro_url}/api/v1/auth" --request GET --header "Authorization: Bearer ${api_token}")

}

# /api/v1/auth/keep-alive is documented only for tokens issued from
# /api/v1/auth/token (username and password); Jamf's docs say nothing about
# client_credentials tokens, and its response carries the other token shape.
# Rather than depend on undocumented behaviour, request a new token instead,
# either shortly before expiry or once the current one stops authenticating.

CheckAndRenewAPIToken() {

	if [[ -z "$api_token" ]] || [[ $(date +%s) -ge ${api_token_expiration_epoch} ]]; then
		GetJamfProAPIToken
		return
	fi

	APITokenValidCheck

	if [[ "${api_authentication_check}" != 200 ]]; then
		GetJamfProAPIToken
	fi

}

# Revokes the token so it cannot be reused after the script exits. Safe to call
# more than once, and safe to call when no token was ever issued.

InvalidateAPIToken() {

	if [[ -n "$api_token" ]]; then
		# --silent --output /dev/null: revocation is best effort. A failure
		# here is not worth aborting an exit path for; the token expires on
		# its own within the hour anyway.
		/usr/bin/curl --silent --output /dev/null \
		    "${curl_timeouts[@]}" \
		    "${jamfpro_url}/api/v1/auth/invalidate-token" \
		    --request POST --header "Authorization: Bearer ${api_token}"
		api_token=""
	fi

}

# ---------------------------------------------------------------------------
# Policy fetch
# ---------------------------------------------------------------------------

# GETs one policy from the Classic API and prints its XML.
#
# Returns 0 only for an HTTP 200 whose body parses as XML. Anything else --
# a 404, a 401 after a token hiccup, a 502 from a slow instance, a proxy's HTML
# maintenance page, a timed-out empty body -- returns 1 and prints a one-line
# reason INSTEAD of a body. Callers must not count anything from a body that
# did not pass this check: xmllint prints 0 for a count over garbage, and 0 is
# exactly what a Remove_ script reads as "already gone" and a verify step reads
# as "removed", so a failed read would otherwise report as a success.
#
# Call it as a command substitution, and call CheckAndRenewAPIToken in the
# caller first. Both are deliberate: inside $( ) this function runs in a
# subshell, so nothing it assigns (a renewed api_token, an error variable)
# would survive back in the caller. The reason therefore travels on stdout:
#
#   CheckAndRenewAPIToken
#   if ! policy_xml=$(FetchPolicyXML "$id"); then
#       log_line "FAILED   ${id}: ${policy_xml}"     # the reason, not XML
#   fi
#
#   $1 policy ID

FetchPolicyXML() {

	local policy_id="$1"
	local response
	local http_code
	local body

	# The status code rides on the last line of the body so one curl call
	# yields both without a temp file. RetryableRequest handles 429 and
	# transport failures; anything else comes back after one attempt.
	response=$(RetryableRequest \
	    --header "Authorization: Bearer ${api_token}" \
	    -H "Accept: application/xml" \
	    "${jamfpro_url}/JSSResource/policies/id/${policy_id}")

	# The last line is the marker curl appended; peel it off, then strip it
	# out of the body.
	http_code=$(echo "$response" | tail -1 | sed 's/^HTTP_CODE://')
	body=$(echo "$response" | sed '$d')

	if [[ "$http_code" != "200" ]]; then
		echo "GET returned HTTP ${http_code:-000}$(DescribeHTTPStatus "$http_code")"
		return 1
	fi

	if [[ -z "$body" ]] || ! echo "$body" | xmllint --noout - 2>/dev/null; then
		echo "GET returned HTTP 200 but the body is empty or not XML"
		return 1
	fi

	echo "$body"
	return 0

}

# PUTs a policy payload to the Classic API and prints the HTTP status.
#
# A PUT here always carries a complete enclosing element, so repeating it is
# harmless; that is what makes the retry in RetryableRequest safe for writes.
# The caller still decides what the status means (201 or 200 is accepted, and
# neither is success -- read-back is). Same subshell rule as FetchPolicyXML:
# renew the token in the caller first.
#
#   $1 policy ID   $2 payload XML

PutPolicyXML() {

	local policy_id="$1"
	local payload="$2"
	local response

	response=$(RetryableRequest \
	    --output /dev/null \
	    --request PUT \
	    --header "Authorization: Bearer ${api_token}" \
	    --header "Content-Type: application/xml" \
	    --data "$payload" \
	    "${jamfpro_url}/JSSResource/policies/id/${policy_id}")

	echo "$response" | tail -1 | sed 's/^HTTP_CODE://'

}

# Runs one curl request with the shared timeouts and a bounded retry, and
# prints the body followed by a last line of HTTP_CODE:<status>.
#
# Retries, up to three attempts with 1 s and 2 s between them, happen only
# for a 429 (Too Many Requests, honouring a numeric Retry-After header when
# the server sends one) and for a transport failure (curl status 000: refused,
# reset, timed out). A 5xx is returned as-is: Jamf's own CLI does not retry
# those either, and a 502 mid-run is worth a human's attention rather than a
# quiet third attempt. Every other status is final on the first try.
#
# Arguments are passed straight to curl after -s and the timeouts, so callers
# supply their own method, headers, body and URL.

RetryableRequest() {

	local attempt=1
	local max_attempts=3
	local response
	local http_code
	local retry_after
	local delay

	while :; do
		# %header{} needs curl 7.84+; macOS 13 and later ship 8.x. On an
		# older curl the expansion is empty and the fallback delay applies.
		response=$(/usr/bin/curl -s "${curl_timeouts[@]}" \
		    --write-out "\nHTTP_CODE:%{http_code}\nRETRY_AFTER:%header{retry-after}" \
		    "$@")

		retry_after=$(echo "$response" | tail -1 | sed 's/^RETRY_AFTER://' | tr -cd '0-9')
		response=$(echo "$response" | sed '$d')
		http_code=$(echo "$response" | tail -1 | sed 's/^HTTP_CODE://')

		if [[ "$http_code" != "429" ]] && [[ "$http_code" != "000" ]]; then
			break
		fi
		if [[ "$attempt" -ge "$max_attempts" ]]; then
			break
		fi

		delay=$attempt
		if [[ "$http_code" = "429" ]] && [[ -n "$retry_after" ]] && [[ "$retry_after" -le 30 ]]; then
			delay=$retry_after
		fi
		sleep "$delay"
		attempt=$((attempt + 1))
	done

	echo "$response"

}

# ---------------------------------------------------------------------------
# Readers
# ---------------------------------------------------------------------------

# Decodes the five predefined XML entities on stdin, for values that are
# printed to a person or a report rather than sent back to Jamf. xmllint's
# --xpath text() output keeps them encoded, so a policy named "Foo & Bar"
# would otherwise log as "Foo &amp; Bar". &amp; is decoded last so an encoded
# entity such as &amp;lt; is not decoded twice.

DecodeXMLEntities() {
	sed -e 's|&lt;|<|g' -e 's|&gt;|>|g' -e 's|&quot;|"|g' -e "s|&apos;|'|g" -e 's|&amp;|\&|g'
}

# Prints a policy's name, entity-decoded, for log lines and reports.
#
#   $1 policy XML

GetPolicyName() {
	echo "$1" | xmllint --xpath '/policy/general/name/text()' - 2>/dev/null | DecodeXMLEntities
}

# Prints the policy ID from the first column of each usable line of a CSV.
#
# Anything whose first field is not all digits is skipped, which disposes of the
# header row without having to guess at its wording, and means the CSV (or older TSV) from
# Generate_Self_Service_Policy_Report.sh can be fed in directly. Blank lines and
# lines beginning with # are skipped too. Comma or tab separated; CRLF tolerated.

ReadPolicyIDsFromCSV() {

	local file="$1"

	# tr strips CRLF line endings. The awk sub() on the first line strips a
	# UTF-8 byte-order mark (EF BB BF), which Excel writes at the front of a
	# "CSV UTF-8" export; left in place it glues onto the first field and the
	# header row is skipped anyway, but a header-less CSV would lose its first
	# policy ID. Octal escapes are the portable spelling for BSD awk.
	tr -d '\r' < "$file" | awk -F'[,\t]' '
		NR == 1 { sub(/^\357\273\277/, "") }
		/^[[:space:]]*$/ { next }
		/^[[:space:]]*#/ { next }
		{
			id = $1
			# Strip surrounding whitespace and an optional double quote, so a
			# quoted cell "42" is accepted.
			gsub(/^[[:space:]]*"?|"?[[:space:]]*$/, "", id)
			if (id ~ /^[0-9]+$/) print id
		}
	'

}

# ---------------------------------------------------------------------------
# Scope entries
# ---------------------------------------------------------------------------
#
# A policy's <scope> has two sections that can carry per-user and per-group
# entries, and they hold some of the same element names:
#
#   <scope>
#     <computer_groups>...</computer_groups>          <- targets
#     <limitations>
#       <users><user><name>..</name></user></users>
#       <user_groups><user_group><name>..</name></user_group></user_groups>
#       <network_segments/>
#       <ibeacons/>
#     </limitations>
#     <exclusions>
#       <computer_groups>...</computer_groups>
#       <users>...</users>
#       <user_groups>...</user_groups>
#       ...
#     </exclusions>
#   </scope>
#
# Every function below takes the section as its first argument for that reason:
# <users> exists under both, and the same person can legitimately be a
# limitation and an exclusion on one policy. Touching the wrong section is the
# main way these scripts could quietly corrupt a policy.
#
# Note that computer groups are valid as targets and exclusions but NOT as
# limitations. Jamf Pro limits by user, user group, network segment and iBeacon.

# Counts matching entries in one scope section. Used to skip work that is
# already done and, after a write, to prove the write landed.
#
#   $1 policy XML
#   $2 section: targets | limitations | exclusions
#   $3 container: computer_groups | computers | users | user_groups
#   $4 entry element: computer_group | computer | user | user_group
#   $5 match element: id | name
#   $6 value

CountScopeEntry() {

	local policy_xml="$1"
	local section="$2"
	local container="$3"
	local entry="$4"
	local match_element="$5"
	local value="$6"
	local result

	local section_path="/${section}"
	if [[ "$section" = "targets" ]]; then
		# Targets are direct children of <scope>; there is no wrapper element.
		section_path=""
	fi

	# value lands inside the predicate's single quotes, so a quote in it would
	# break out of the XPath. Safety rests on the caller's character whitelist
	# (CLAUDE.md hard rule 5); nothing is escaped here.
	result=$(echo "$policy_xml" | xmllint --xpath \
	    "count(/policy/scope${section_path}/${container}/${entry}[${match_element}='${value}'])" - 2>/dev/null)

	case "$result" in
		''|*[!0-9]*) echo "0" ;;
		*)           echo "$result" ;;
	esac

}

# Counts a user group named in scope/limit_to_users/user_groups, the second
# place Jamf Pro keeps a policy's user-group limitation. Entries there are
# bare strings -- <user_group>Staff</user_group>, no <name> child -- which is
# why CountScopeEntry cannot be pointed at it. Jamf's own CLI writes policy
# user-group limitations here and treats limitations/user_groups as a mirror,
# so a read-back that finds the group in either place has found it.
#
#   $1 policy XML   $2 group name

CountLimitToUsersGroup() {

	local policy_xml="$1"
	local value="$2"
	local result

	result=$(echo "$policy_xml" | xmllint --xpath \
	    "count(/policy/scope/limit_to_users/user_groups/user_group[.='${value}'])" - 2>/dev/null)

	case "$result" in
		''|*[!0-9]*) echo "0" ;;
		*)           echo "$result" ;;
	esac

}

# Inserts one entry into a scope section and prints the whole <scope> back.
#
# The insertion is surgical on purpose. Jamf Pro's Classic API replaces the
# content of any element the request supplies, so a PUT carrying a bare
# <exclusions><computer_groups> with one group in it can drop every other
# exclusion already on the policy. Sending the complete <scope>,
# byte-identical except for the added node, removes the question entirely.
#
# Section "targets" is the special case: targets are direct children of <scope>
# rather than a wrapper element, and <computer_groups> and <computers> appear
# again inside <exclusions>. The target region is therefore everything between
# <scope> and whichever of <limitations> or <exclusions> comes first.
#
# Exits non-zero if the node could not be placed anywhere, so a caller can
# report FAILED for that policy instead of sending an unchanged <scope>.
#
#   $1 formatted <scope> XML   $2 section   $3 container   $4 new node

InsertScopeEntry() {

	local scope_xml="$1"
	local section="$2"
	local container="$3"
	local new_node="$4"

	echo "$scope_xml" | awk -v section="$section" -v container="$container" -v node="$new_node" '
		BEGIN { targets = (section == "targets") }

		# State, all starting empty (false): in_section is set while inside the
		# section being edited; has_section records that the section was seen
		# at all; found_container that the container was seen inside it;
		# in_container while between the container open and close tags; and
		# inserted once the node is placed, after which every line passes
		# through unchanged.

		# --- target region bookkeeping ---------------------------------------
		targets && /<scope>/ { in_section = 1; has_section = 1; found_container = 0 }
		# Either wrapper ends the target region. The optional slash also
		# matches a self-closing <limitations/> so the region cannot leak
		# past an empty wrapper (Jamf writes populated wrappers today, but
		# the bound must not depend on that).
		targets && (/<limitations\/?>/ || /<exclusions\/?>/) {
			if (in_section && !found_container && !inserted) {
				match($0, /^[[:space:]]*/)
				pad = substr($0, 1, RLENGTH)
				print pad "<" container ">"
				print pad "  " node
				print pad "</" container ">"
				inserted = 1
			}
			in_section = 0
		}

		# --- section bookkeeping for limitations and exclusions --------------
		!targets && $0 ~ ("<" section "/>") {
			match($0, /^[[:space:]]*/)
			pad = substr($0, 1, RLENGTH)
			print pad "<" section ">"
			print pad "  <" container ">"
			print pad "    " node
			print pad "  </" container ">"
			print pad "</" section ">"
			has_section = 1
			inserted = 1
			next
		}

		!targets && $0 ~ ("<" section ">") { in_section = 1; has_section = 1; found_container = 0 }

		# --- the container itself --------------------------------------------
		# Self-closing container: expand it to a populated one.
		in_section && !inserted && $0 ~ ("^[[:space:]]*<" container "/>[[:space:]]*$") {
			match($0, /^[[:space:]]*/)
			pad = substr($0, 1, RLENGTH)
			print pad "<" container ">"
			print pad "  " node
			print pad "</" container ">"
			found_container = 1
			inserted = 1
			next
		}

		# Populated container: note the open tag, then append the node just
		# before its close tag.
		in_section && !inserted && $0 ~ ("^[[:space:]]*<" container ">[[:space:]]*$") { found_container = 1; in_container = 1 }

		in_container && $0 ~ ("^[[:space:]]*</" container ">[[:space:]]*$") {
			match($0, /^[[:space:]]*/)
			pad = substr($0, 1, RLENGTH)
			print pad "  " node
			in_container = 0
			inserted = 1
		}

		# Section closes with no container seen: create the container, node
		# inside, just before the close.
		!targets && in_section && $0 ~ ("</" section ">") {
			if (!found_container) {
				match($0, /^[[:space:]]*/)
				pad = substr($0, 1, RLENGTH)
				print pad "  <" container ">"
				print pad "    " node
				print pad "  </" container ">"
				inserted = 1
			}
			in_section = 0
		}

		/<\/scope>/ {
			# No section element at all. Jamf Pro always writes every section and
			# container, even when empty, so this is a belt-and-braces path.
			if (!has_section || (targets && !inserted)) {
				match($0, /^[[:space:]]*/)
				pad = substr($0, 1, RLENGTH)
				if (targets) {
					print pad "  <" container ">"
					print pad "    " node
					print pad "  </" container ">"
				} else {
					print pad "  <" section ">"
					print pad "    <" container ">"
					print pad "      " node
					print pad "    </" container ">"
					print pad "  </" section ">"
				}
				inserted = 1
			}
		}

		# Every line is echoed after any insertion the rules above made for it.
		# That ordering is what keeps a node inserted "before a close tag"
		# ahead of the close tag in the output.
		{ print }

		END { if (!inserted) exit 1 }
	'

}

# Removes one entry from a scope section and prints the whole <scope> back.
# Exits non-zero when nothing matched, so a caller can tell "already gone" from
# "removed".
#
# Each entry block is buffered and discarded only if the complete block matches.
# Buffering is what makes it exact: once xmllint has formatted the XML, the id
# and the element that owns it are on different lines, so a line-at-a-time
# filter could delete one entry's <id> and leave a malformed block behind. It
# also means group 7 is never confused with group 77.
#
#   $1 formatted <scope> XML   $2 section   $3 container
#   $4 entry element   $5 match element   $6 value

RemoveScopeEntry() {

	local scope_xml="$1"
	local section="$2"
	local container="$3"
	local entry="$4"
	local match_element="$5"
	local match_value="$6"

	echo "$scope_xml" | awk \
	    -v section="$section" \
	    -v container="$container" \
	    -v entry="$entry" \
	    -v match_element="$match_element" \
	    -v match_value="$match_value" '
		BEGIN {
			removed = 0
			targets = (section == "targets")
			# The value is interpolated into a regex below. A dot in an Entra
			# group name would otherwise match any character and could take
			# out a different entry; unescaped parentheses turn "Marketing (US)"
			# into a group, and an unescaped $ anchors. Every ERE metacharacter
			# is escaped here, whatever validation the caller applied.
			gsub(/[.*+?^${}()|\[\]\\]/, "\\\\&", match_value)
		}

		targets && /<scope>/ { in_section = 1 }
		# Same bound as InsertScopeEntry: a self-closing wrapper also ends targets.
		targets && (/<limitations\/?>/ || /<exclusions\/?>/) { in_section = 0 }

		!targets && $0 ~ ("<" section ">")  { in_section = 1 }
		!targets && $0 ~ ("</" section ">") { in_section = 0 }

		# Container open and close lines pass through untouched; only the
		# entry blocks between them are buffered.
		in_section   && $0 ~ ("^[[:space:]]*<" container ">[[:space:]]*$")  { in_container = 1; print; next }
		in_container && $0 ~ ("^[[:space:]]*</" container ">[[:space:]]*$") { in_container = 0; print; next }

		in_container && $0 ~ ("^[[:space:]]*<" entry ">[[:space:]]*$") {
			buffering = 1
			matched = 0
			buffer_length = 0
			buffer[++buffer_length] = $0
			next
		}

		buffering {
			buffer[++buffer_length] = $0

			if ($0 ~ ("^[[:space:]]*<" match_element ">" match_value "</" match_element ">[[:space:]]*$")) {
				matched = 1
			}

			if ($0 ~ ("^[[:space:]]*</" entry ">[[:space:]]*$")) {
				if (matched) {
					removed++
				} else {
					for (i = 1; i <= buffer_length; i++) print buffer[i]
				}
				buffering = 0
			}

			next
		}

		{ print }

		END { if (removed == 0) exit 1 }
	'

}

# Counts a policy's scope targets: computers, computer groups, buildings and
# departments. A policy whose targets all go away never runs again, which is
# the one irreversible-feeling mistake the target scripts can make, so
# Remove_Policy_Scope_Target.sh checks this before it writes and refuses
# without --allow-empty-scope.
#
#   $1 policy or scope XML wrapped in <policy>

CountScopeTargets() {

	local xml="$1"
	local total

	total=$(echo "$xml" | xmllint --xpath \
	    "count(/policy/scope/computers/computer) + count(/policy/scope/computer_groups/computer_group) + count(/policy/scope/buildings/building) + count(/policy/scope/departments/department)" - 2>/dev/null)

	# xmllint prints a sum as a float, e.g. 3 or 3.0 depending on version.
	total=${total%%.*}

	case "$total" in
		''|*[!0-9]*) echo "0" ;;
		*)           echo "$total" ;;
	esac

}

# ---------------------------------------------------------------------------
# Single-value elements
# ---------------------------------------------------------------------------

# Replaces one child element inside a parent section and prints the parent back.
# Unlike the scope functions this is a replace, not an append: it serves
# <general><category>, <general><enabled>, the seven trigger fields and
# <self_service><use_for_self_service>, each of which a policy has exactly one
# of, so setting one means swapping the whole element.
#
# The section bound matters here too. <category> appears under <general> AND
# under <self_service><self_service_categories>, and those are unrelated fields
# -- a policy filed under "Apps & Utilities" can display under "Productivity" in
# Self Service. Passing section "general" is what keeps them apart.
#
# Handles a populated block, a one-line leaf (<enabled>true</enabled>), a
# self-closing <category/>, and the element being absent entirely. Exits
# non-zero if it could not place the new value.
#
#   $1 formatted parent XML   $2 section   $3 element   $4 replacement node

ReplaceElementInSection() {

	local parent_xml="$1"
	local section="$2"
	local element="$3"
	local new_node="$4"

	echo "$parent_xml" | awk -v section="$section" -v element="$element" -v node="$new_node" '
		# Section open. Anchored to a line holding only the tag, so the tag
		# name appearing inside a text value cannot open a section.
		$0 ~ ("^[[:space:]]*<" section ">[[:space:]]*$") { in_section = 1 }

		$0 ~ ("^[[:space:]]*</" section ">[[:space:]]*$") {
			# Element absent from the section: add it before the section closes.
			if (in_section && !replaced) {
				match($0, /^[[:space:]]*/)
				pad = substr($0, 1, RLENGTH)
				print pad "  " node
				replaced = 1
			}
			in_section = 0
		}

		in_section && !replaced && $0 ~ ("^[[:space:]]*<" element ">[^<]*</" element ">[[:space:]]*$") {
			# A leaf on one line, which is how xmllint --format writes any
			# element whose content is text: <enabled>true</enabled>. Without
			# this branch the open-tag patterns below both miss, the element
			# looks absent, and a second copy gets appended -- leaving two
			# <enabled> elements in one <general> and the original value first.
			match($0, /^[[:space:]]*/)
			pad = substr($0, 1, RLENGTH)
			print pad node
			replaced = 1
			next
		}

		# Self-closing <element/>: replace it in place.
		in_section && !replaced && $0 ~ ("^[[:space:]]*<" element "/>[[:space:]]*$") {
			match($0, /^[[:space:]]*/)
			pad = substr($0, 1, RLENGTH)
			print pad node
			replaced = 1
			next
		}

		# Block open: print the replacement here and swallow the old block
		# below, children and all, up to its close.
		in_section && !replaced && $0 ~ ("^[[:space:]]*<" element ">[[:space:]]*$") {
			match($0, /^[[:space:]]*/)
			pad = substr($0, 1, RLENGTH)
			print pad node
			dropping = 1
			replaced = 1
			next
		}

		dropping {
			# Swallow the old block, including any children, up to its close.
			if ($0 ~ ("^[[:space:]]*</" element ">[[:space:]]*$")) { dropping = 0 }
			next
		}

		in_section && !replaced && $0 ~ ("^[[:space:]]*<" element "[ >/]") {
			# The element IS here but in a shape none of the branches above
			# recognise -- an open tag carrying an attribute, say, or text
			# content that xmllint wrapped across lines. Treating it as absent
			# would append a second copy: well-formed XML, a 201 from Jamf, and
			# whichever value Jamf keeps. Refuse instead so the caller reports
			# a failure for that policy and nothing is sent.
			unhandled = 1
		}

		{ print }

		END { if (!replaced || unhandled) exit 1 }
	'

}

# Prints a policy's current category as "id|name", for reporting a change as
# "from -> to" rather than just announcing the new value.
#
#   $1 policy XML

GetPolicyCategory() {

	local policy_xml="$1"
	local category_id
	local category_name

	category_id=$(echo "$policy_xml" | xmllint --xpath '/policy/general/category/id/text()' - 2>/dev/null)
	category_name=$(echo "$policy_xml" | xmllint --xpath '/policy/general/category/name/text()' - 2>/dev/null)

	# xmllint returns the raw text node, so "Apps &amp; Utilities" arrives
	# encoded. Decode for display; DecodeXMLEntities orders &amp; last so
	# nothing decodes twice.
	category_name=$(echo "$category_name" | DecodeXMLEntities)

	echo "${category_id}|${category_name}"

}

# Prints a policy's enabled state as "true" or "false", or the empty string if
# the policy carries no <enabled> element at all.
#
#   $1 policy XML

GetPolicyEnabled() {

	local policy_xml="$1"

	echo "$policy_xml" | xmllint --xpath '/policy/general/enabled/text()' - 2>/dev/null

}

# Prints a one-line summary of everything that can make a policy run, so every
# writer that changes what can run a policy (enable, disable, the four trigger
# scripts) reports what it is switching rather than just which policies it
# touched, and PolicyHasAutomaticTrigger can decide from the same text.
# Output is a comma-separated list, or "none".
#
# Self Service comes first because it is the reason this directory exists. The
# automatic triggers matter more on the way in than on the way out: enabling a
# policy with Recurring Check-in set means it executes on every targeted Mac at
# next check-in, without anyone opening Self Service.
#
# One awk pass rather than an xmllint call per trigger. The section tracking is
# the same idea as everywhere else here -- <self_service_categories> is nested
# inside <self_service> and must not be mistaken for it.
#
#   $1 policy XML

GetPolicyTriggers() {

	local policy_xml="$1"

	echo "$policy_xml" | xmllint --format - 2>/dev/null | awk '
		# Append with ", " as the separator; no leading separator on the first.
		function add(label) { out = out (out == "" ? "" : ", ") label }

		/^[[:space:]]*<general>[[:space:]]*$/        { sec = "general";      next }
		/^[[:space:]]*<\/general>[[:space:]]*$/      { sec = "";             next }
		/^[[:space:]]*<self_service>[[:space:]]*$/   { sec = "self_service"; next }
		/^[[:space:]]*<\/self_service>[[:space:]]*$/ { sec = "";             next }

		sec == "self_service" && /<use_for_self_service>true<\/use_for_self_service>/ { self_service = 1 }

		sec == "general" && /<trigger_checkin>true<\/trigger_checkin>/                             { add("Recurring Check-in") }
		sec == "general" && /<trigger_startup>true<\/trigger_startup>/                             { add("Startup") }
		sec == "general" && /<trigger_login>true<\/trigger_login>/                                 { add("Login") }
		sec == "general" && /<trigger_logout>true<\/trigger_logout>/                               { add("Logout") }
		sec == "general" && /<trigger_network_state_changed>true<\/trigger_network_state_changed>/ { add("Network State Change") }
		sec == "general" && /<trigger_enrollment_complete>true<\/trigger_enrollment_complete>/     { add("Enrollment Complete") }

		sec == "general" && /<trigger_other>[^<]+<\/trigger_other>/ {
			# Two sub() calls take the text between the tags; POSIX awk has
			# no regex capture groups.
			custom = $0
			sub(/^[^>]*>/, "", custom)
			sub(/<.*$/, "", custom)
			if (custom != "") add("Custom: " custom)
		}

		END {
			if (self_service) out = (out == "" ? "Self Service" : "Self Service, " out)
			print (out == "" ? "none" : out)
		}
	'

}

# True when a policy would run on its own, with no one opening Self Service.
# Prints "yes" or "no".
#
#   $1 policy XML

PolicyHasAutomaticTrigger() {

	local policy_xml="$1"
	local triggers

	triggers=$(GetPolicyTriggers "$policy_xml")

	# Everything except Self Service and "none" is automatic.
	triggers=$(echo "$triggers" | sed -e 's|Self Service||' -e 's|none||' -e 's|[, ]||g')

	if [[ -n "$triggers" ]]; then
		echo "yes"
	else
		echo "no"
	fi

}

# ---------------------------------------------------------------------------
# Triggers
# ---------------------------------------------------------------------------

# The six boolean triggers, as accepted on the command line. Kept as a plain
# string because bash 3.2 has no associative arrays.
#
# "recurring-check-in" is also accepted by ResolveTriggerElement as an alias
# of "checkin" (it is what the Jamf UI calls the trigger) but is deliberately
# not advertised here or in any usage text, so there is one documented name.
# shellcheck disable=SC2034  # consumed by the scripts that source this file
TRIGGER_FLAG_NAMES="checkin startup login logout network-state-change enrollment-complete"

# Maps a command-line trigger name to its Classic API element. Prints the empty
# string for anything unrecognised, so callers validate by testing for empty.
#
# The custom event is deliberately absent: it is a string, not a boolean, and
# every script takes it through its own --custom-event flag.
#
#   $1 trigger name

ResolveTriggerElement() {

	case "$1" in
		checkin|recurring-check-in)  echo "trigger_checkin" ;;
		startup)                     echo "trigger_startup" ;;
		login)                       echo "trigger_login" ;;
		logout)                      echo "trigger_logout" ;;
		network-state-change)        echo "trigger_network_state_changed" ;;
		enrollment-complete)         echo "trigger_enrollment_complete" ;;
		*)                           echo "" ;;
	esac

}

# Maps a Classic API trigger element to the label Jamf Pro's own UI uses, so
# output reads the way the admin console does.
#
#   $1 element name

TriggerLabel() {

	case "$1" in
		trigger_checkin)               echo "Recurring Check-in" ;;
		trigger_startup)               echo "Startup" ;;
		trigger_login)                 echo "Login" ;;
		trigger_logout)                echo "Logout" ;;
		trigger_network_state_changed) echo "Network State Change" ;;
		trigger_enrollment_complete)   echo "Enrollment Complete" ;;
		trigger_other)                 echo "Custom Event" ;;
		*)                             echo "$1" ;;
	esac

}

# Prints the value of one <general> child. "true"/"false" for the boolean
# triggers, the event name for trigger_other, empty if the element is absent.
#
#   $1 policy XML   $2 element name

GetPolicyTriggerState() {

	local policy_xml="$1"
	local element="$2"

	echo "$policy_xml" | xmllint --xpath "/policy/general/${element}/text()" - 2>/dev/null

}

# Prints <general><trigger>, the legacy summary field -- "EVENT" when the policy
# has an automatic trigger, "USER_INITIATED" when it is Self Service only.
#
# Nothing here writes it. Jamf Pro maintains it alongside the booleans, and the
# booleans are what the admin UI edits. Reported after a write so that a first
# real run shows whether Jamf recomputed it; see the standing note in CLAUDE.md.
#
#   $1 policy XML

GetLegacyTrigger() {

	local policy_xml="$1"

	echo "$policy_xml" | xmllint --xpath '/policy/general/trigger/text()' - 2>/dev/null

}

# Prints <self_service><use_for_self_service>, "true" or "false", or empty if
# the policy carries no <self_service> element.
#
#   $1 policy XML

GetPolicySelfService() {

	local policy_xml="$1"

	echo "$policy_xml" | xmllint --xpath '/policy/self_service/use_for_self_service/text()' - 2>/dev/null

}
