#!/bin/bash
#
# End-to-end exercise of every script in ../scripts against the mock Jamf Pro
# server in mock/mock_jamf.py. Nothing here touches a real tenant.
#
# Runs under a STOCK macOS PATH so Homebrew GNU tools cannot mask a BSD
# incompatibility:
#
#   tests/e2e.sh
#
# Needs python3 for the mock only (an authoring/test tool; the scripts under
# test never call it). Prints one PASS/FAIL line per check and exits 1 on any
# failure. Scratch goes in a temp directory that is removed on exit.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS=$(cd "$HERE/../scripts" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ss-e2e.XXXXXX")
# A random high port so two runs (or two agents) cannot collide on one mock.
PORT=$((20000 + RANDOM % 10000))
URL="http://127.0.0.1:${PORT}"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; shift; [[ $# -gt 0 ]] && printf '     %s\n' "$@"; }
assert_eq() { if [[ "$2" = "$3" ]]; then ok "$1"; else bad "$1" "expected: [$2]" "actual:   [$3]"; fi; }
assert_grep() { if grep -q -- "$2" "$3"; then ok "$1"; else bad "$1" "missing: $2" "in: $3"; fi; }
assert_nogrep() { if ! grep -q -- "$2" "$3"; then ok "$1"; else bad "$1" "unexpected: $2" "in: $3"; fi; }

# --- mock server ----------------------------------------------------------

python3 "$HERE/mock/mock_jamf.py" "$PORT" "$HERE"/fixtures/policy-*.xml >"$WORK/mock.log" 2>&1 &
MOCK_PID=$!
trap 'kill "$MOCK_PID" 2>/dev/null; wait "$MOCK_PID" 2>/dev/null; if [[ -z "${KEEP:-}" ]]; then rm -rf "$WORK"; fi' 0
for _ in 1 2 3 4 5 6 7 8 9 10; do
	curl -s -o /dev/null "$URL/api/v1/auth" && break
	sleep 0.3
done

# The mock's GET answers with the server's own re-serialisation, so read a
# policy field straight from it for assertions.
get_field() { # id xpath
	local body
	# Two attempts: policy 429 answers every other GET with a 429, and this
	# helper is not the code under test.
	for _ in 1 2; do
		body=$(curl -s -H "Authorization: Bearer tok-1" -H "Accept: application/xml" "$URL/JSSResource/policies/id/$1")
		[[ -n "$body" ]] && break
	done
	echo "$body" | xmllint --xpath "$2" - 2>/dev/null
}

# --- running a script under the stock environment ---------------------------

# run <name> <script> [args...]: runs the script with the mock's credentials,
# stock PATH, no HOME preferences, output in $WORK/<name>.out, rc in $RC.
run() {
	local name="$1"; shift
	local script="$1"; shift
	env -i HOME="$WORK/home" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
	    JAMF_PRO_URL="$URL" JAMF_PRO_CLIENT_ID=cid JAMF_PRO_CLIENT_SECRET=sec \
	    /bin/bash "$SCRIPTS/$script" "$@" >"$WORK/$name.out" 2>&1 </dev/null
	RC=$?
}

# token_from <outfile>: the --confirm token a dry run printed.
token_from() { sed -n 's/.*--apply --confirm \([^ ]*\).*/\1/p' "$1" | tail -1; }

# dry_then_apply <name> <script> [args...]: dry run, then apply with the
# printed token, both into $WORK/<name>-dry.out and $WORK/<name>-apply.out.
dry_then_apply() {
	local name="$1"; shift
	local script="$1"; shift
	run "$name-dry" "$script" --csv "$CSV" --backup-dir "$WORK/$name-dry-bk" "$@"
	DRY_RC=$RC
	local token
	token=$(token_from "$WORK/$name-dry.out")
	run "$name-apply" "$script" --csv "$CSV" --backup-dir "$WORK/$name-bk" "$@" --apply --confirm "$token"
	APPLY_RC=$RC
}

mkdir -p "$WORK/home"
CSV="$WORK/ids.csv"
printf 'Jamf Pro ID Number\tPolicy Name\r\n101\tInstall Foo\r\n202\tAll\r\n303\tReset Keychain\r\n404\tmissing\r\n500\tproxy\r\n' > "$CSV"

# --- 0. every script: --help exits 0, no args exits non-zero -----------------

for s in "$SCRIPTS"/*.sh; do
	b=$(basename "$s")
	run "help-$b" "$b" --help
	assert_eq "$b --help rc" "0" "$RC"
	if [[ "$b" != "Generate_Self_Service_Policy_Report.sh" ]]; then
		run "noarg-$b" "$b"
		assert_eq "$b no-args rc" "3" "$RC"
	fi
done

# --- 1. report --------------------------------------------------------------

run report Generate_Self_Service_Policy_Report.sh --output "$WORK/report.csv"
assert_eq "report rc (1: two unreadable policies)" "1" "$RC"
assert_grep "report names policy 404 as unreadable" "Policy 404: GET returned HTTP 404" "$WORK/report.out"
assert_grep "report names policy 500 as non-XML" "Policy 500: GET returned HTTP 200 but the body" "$WORK/report.out"
assert_eq "report rows (header + 3 Self Service policies)" "4" "$(grep -c ^ "$WORK/report.csv")"
assert_grep "report: 404 line carries the status hint" "Not Found: no policy with that ID" "$WORK/report.out"
assert_grep "report: rate-limited policy 429 present (first GET answered 429, retry succeeded)" '^"429",' "$WORK/report.csv"
assert_eq "mock saw at least two GETs for policy 429" "1" "$([[ $(grep -c 'GET /JSSResource/policies/id/429' "$WORK/mock.log") -ge 2 ]] && echo 1 || echo 0)"
assert_grep "report LDAP Groups column populated from bare user_group strings" "LDAP Groups: Teachers; Staff" "$WORK/report.csv"
assert_grep "report decodes &amp; in policy name" "Install Foo & Bar" "$WORK/report.csv"
assert_nogrep "report leaves out the non-Self-Service policy" '^"202",' "$WORK/report.csv"
assert_eq "report: every row starts and ends with a quoted field" "4" "$(tr -d '\r' < "$WORK/report.csv" | grep -c '^"[^"]*",.*"$')"
assert_eq "report: CRLF row endings" "4" "$(grep -c $'\r$' "$WORK/report.csv")"
run roundtrip Enable_Policy.sh --csv "$WORK/report.csv" --backup-dir "$WORK/roundtrip-bk"
assert_grep "report CSV feeds straight back into a writer (quoted IDs, CRLF)" "(3 policy IDs)" "$WORK/roundtrip.out"

# --- 2. scope targets: add two values, backup written once, remove ---------

dry_then_apply add-target Add_Policy_Scope_Target.sh --group-id 42 --computer-id 9
assert_eq "add-target dry rc (1: 404 and 500 fail)" "1" "$DRY_RC"
assert_grep "add-target dry: 404 failed on GET" "FAILED   404: GET returned HTTP 404" "$WORK/add-target-dry.out"
assert_grep "add-target dry: 500 failed as non-XML" "FAILED   500: GET returned HTTP 200 but the body" "$WORK/add-target-dry.out"
assert_grep "add-target dry: 202 skipped (not Self Service)" "SKIPPED  202" "$WORK/add-target-dry.out"
assert_eq "add-target apply rc (404/500 fail)" "1" "$APPLY_RC"
assert_eq "add-target apply: 101 has group 42" "1" "$(get_field 101 'count(/policy/scope/computer_groups/computer_group[id=42])')"
assert_eq "add-target apply: 101 has computer 9" "1" "$(get_field 101 'count(/policy/scope/computers/computer[id=9])')"
assert_eq "add-target apply: 101 original groups intact" "4" "$(get_field 101 'count(/policy/scope/computer_groups/computer_group)')"
assert_eq "add-target apply: exclusions untouched" "1" "$(get_field 101 'count(/policy/scope/exclusions/computer_groups/computer_group)')"
assert_eq "add-target: before.xml written once (no group 42 in it)" "0" "$(grep -c '<id>42</id>' "$WORK/add-target-bk/policy-101-before.xml")"
# shellcheck disable=SC2016  # the literal \$TOKEN is what the scripts print
assert_eq "every writer's restore hint carries a Bearer token and timeouts" "14" "$(grep -lF 'Restore with: curl --connect-timeout 15 --max-time 30 -X PUT -H \"Authorization: Bearer \$TOKEN\"' "$SCRIPTS"/*.sh | grep -c .)"

dry_then_apply rm-target Remove_Policy_Scope_Target.sh --group-id 42 --computer-id 9
assert_eq "rm-target apply: group 42 gone" "0" "$(get_field 101 'count(/policy/scope/computer_groups/computer_group[id=42])')"
assert_eq "rm-target apply: computer 9 gone" "0" "$(get_field 101 'count(/policy/scope/computers/computer[id=9])')"
assert_eq "rm-target: before.xml holds group 42 (pre-run state, not post-first-PUT)" "1" "$(grep -c '<id>42</id>' "$WORK/rm-target-bk/policy-101-before.xml")"
assert_grep "rm-target apply: 202 skipped (not Self Service)" "SKIPPED  202" "$WORK/rm-target-apply.out"

run rm-last Remove_Policy_Scope_Target.sh --csv "$CSV" --group-id 7 --backup-dir "$WORK/rm-last-bk"
assert_grep "rm-target refuses to empty 303's scope" "REFUSED  303" "$WORK/rm-last.out"

# --- 3. exclusions and limitations ------------------------------------------

dry_then_apply add-excl Add_Policy_Scope_Exclusion.sh --group-id 55 --username bob
assert_eq "add-excl: 101 excludes group 55" "1" "$(get_field 101 'count(/policy/scope/exclusions/computer_groups/computer_group[id=55])')"
assert_eq "add-excl: 101 excludes bob" "1" "$(get_field 101 'count(/policy/scope/exclusions/users/user[name="bob"])')"
assert_eq "add-excl: limitations untouched" "1" "$(get_field 101 'count(/policy/scope/limitations/users/user)')"
dry_then_apply rm-excl Remove_Policy_Scope_Exclusion.sh --group-id 55 --username bob
assert_eq "rm-excl: group 55 gone" "0" "$(get_field 101 'count(/policy/scope/exclusions/computer_groups/computer_group[id=55])')"
assert_eq "rm-excl: bob gone, alice kept" "alice" "$(get_field 101 '/policy/scope/exclusions/users/user/name/text()')"

run lim-mirror Add_Policy_Scope_Limitation.sh --csv "$CSV" --user-group Teachers --backup-dir "$WORK/lim-mirror-bk"
assert_grep "add-lim: group present only in limit_to_users counts as ALREADY (303)" "ALREADY  303" "$WORK/lim-mirror.out"
assert_grep "add-lim: 101 has no Teachers anywhere, would add" "WOULD ADD 101" "$WORK/lim-mirror.out"
dry_then_apply add-lim Add_Policy_Scope_Limitation.sh --username carol --user-group 'Corp.Marketing'
dry_then_apply add-lim-id Add_Policy_Scope_Limitation.sh --user-group-id 13
run lim-both Add_Policy_Scope_Limitation.sh --csv "$CSV" --user-group 'X' --user-group-id 13
assert_eq "add-lim rejects --user-group with --user-group-id" "3" "$RC"
assert_eq "add-lim: carol limited" "1" "$(get_field 101 'count(/policy/scope/limitations/users/user[name="carol"])')"
assert_eq "add-lim: Corp.Marketing not duplicated" "1" "$(get_field 101 'count(/policy/scope/limitations/user_groups/user_group[name="Corp.Marketing"])')"
assert_eq "add-lim: group 13 limited" "1" "$(get_field 101 'count(/policy/scope/limitations/user_groups/user_group[id=13])')"
dry_then_apply rm-lim Remove_Policy_Scope_Limitation.sh --username carol --user-group 'Corp.Marketing'
dry_then_apply rm-lim-id Remove_Policy_Scope_Limitation.sh --user-group-id 13
assert_eq "rm-lim: group 13 gone" "0" "$(get_field 101 'count(/policy/scope/limitations/user_groups/user_group[id=13])')"
assert_eq "rm-lim: Corp.Marketing removed, CorpXMarketing kept" "CorpXMarketing" "$(get_field 101 '/policy/scope/limitations/user_groups/user_group/name/text()')"
assert_eq "rm-lim: exclusions' Corp.Marketing untouched" "1" "$(get_field 101 'count(/policy/scope/exclusions/user_groups/user_group[name="Corp.Marketing"])')"

# --- 4. category -------------------------------------------------------------

dry_then_apply cat-name Set_Policy_Category.sh --category-name 'Apps & Utilities'
assert_grep "cat-name: 101 already filed there" "ALREADY  101" "$WORK/cat-name-apply.out"
assert_eq "cat-name: 303 refiled" "Apps &amp; Utilities" "$(get_field 303 '/policy/general/category/name/text()')"
assert_eq "cat-name: 303 name intact" "Reset Keychain" "$(get_field 303 '/policy/general/name/text()')"
run cat-slash Set_Policy_Category.sh --csv "$CSV" --category-name 'Apps/Utilities'
assert_eq "cat: slash in name rejected" "3" "$RC"
assert_grep "cat: slash message points to --category-id" "pass --category-id instead" "$WORK/cat-slash.out"
dry_then_apply cat-none Set_Policy_Category.sh --no-category
assert_eq "cat-none: 101 cleared" "-1" "$(get_field 101 '/policy/general/category/id/text()')"

# --- 5. enable / disable -------------------------------------------------------

dry_then_apply enable Enable_Policy.sh
assert_grep "enable: 101 already enabled" "ALREADY  101" "$WORK/enable-apply.out"
assert_eq "enable: 303 enabled" "true" "$(get_field 303 '/policy/general/enabled/text()')"
assert_eq "enable: 303 has exactly one <enabled>" "1" "$(get_field 303 'count(/policy/general/enabled)')"
dry_then_apply disable Disable_Policy.sh
assert_eq "disable: 101 disabled" "false" "$(get_field 101 '/policy/general/enabled/text()')"
run disable-flag Disable_Policy.sh --csv "$CSV" --allow-auto-trigger
assert_eq "disable rejects --allow-auto-trigger" "3" "$RC"
run trailing-flag Disable_Policy.sh --csv "$CSV" --delay
assert_eq "a flag with no value exits 3 instead of looping forever" "3" "$RC"
assert_grep "trailing flag names itself" "ERROR! --delay needs a value" "$WORK/trailing-flag.out"
run trailing-output Generate_Self_Service_Policy_Report.sh --output
assert_eq "report: --output with no value exits 3" "3" "$RC"
printf '429\n' > "$WORK/one429.csv"
run enable-429-dry Enable_Policy.sh --csv "$WORK/one429.csv" --backup-dir "$WORK/e429-dry-bk"
run enable-429 Enable_Policy.sh --csv "$WORK/one429.csv" --backup-dir "$WORK/e429-bk" --apply --confirm "$(token_from "$WORK/enable-429-dry.out")"
assert_eq "enable through 429s: rc 0 (GET, PUT and read-back all retried past a 429)" "0" "$RC"
assert_eq "enable through 429s: 429 enabled" "true" "$(get_field 429 '/policy/general/enabled/text()')"

# --- 6. triggers ---------------------------------------------------------------

dry_then_apply add-evt Add_Policy_Trigger.sh --custom-event newEvt
assert_grep "add-evt: 101 skipped, different event named" "SKIPPED  101 (Install Foo & Bar): custom event is already 'install-foo'" "$WORK/add-evt-apply.out"
assert_eq "add-evt: 101 event untouched" "install-foo" "$(get_field 101 '/policy/general/trigger_other/text()')"
assert_eq "add-evt: 303 event set" "newEvt" "$(get_field 303 '/policy/general/trigger_other/text()')"

dry_then_apply add-startup Add_Policy_Trigger.sh --trigger startup --allow-auto-trigger
assert_eq "add-startup: 303 startup on" "true" "$(get_field 303 '/policy/general/trigger_startup/text()')"
assert_eq "add-startup: 303 legacy trigger recomputed by server" "EVENT" "$(get_field 303 '/policy/general/trigger/text()')"

dry_then_apply rm-evt Remove_Policy_Trigger.sh --custom-event install-foo
assert_eq "rm-evt: 101 event cleared" "" "$(get_field 101 '/policy/general/trigger_other/text()')"
assert_grep "rm-evt: 303 skipped (different event)" "SKIPPED  303" "$WORK/rm-evt-apply.out"

dry_then_apply rename Rename_Policy_Trigger.sh --from newEvt --to installKeychain
assert_eq "rename: 303 repointed" "installKeychain" "$(get_field 303 '/policy/general/trigger_other/text()')"

run set-empty Set_Policy_Triggers.sh --csv "$CSV" --set none --custom-event ''
assert_eq "set-triggers rejects empty --custom-event" "3" "$RC"
run set-old Set_Policy_Triggers.sh --csv "$CSV" --set none --no-custom-event
assert_eq "set-triggers rejects retired --no-custom-event" "3" "$RC"
dry_then_apply set-clear-wrong Set_Policy_Triggers.sh --set none --clear-custom-event someOtherEvent
assert_grep "set-triggers: 303 skipped whole when named event differs" "SKIPPED  303 (Reset Keychain): custom event is 'installKeychain', not 'someOtherEvent'" "$WORK/set-clear-wrong-apply.out"
assert_eq "set-triggers: 303 startup still on after skip" "true" "$(get_field 303 '/policy/general/trigger_startup/text()')"
dry_then_apply set-all Set_Policy_Triggers.sh --set checkin,login --allow-auto-trigger --clear-custom-event installKeychain
assert_eq "set-all rc" "1" "$APPLY_RC"
assert_grep "set-all: 303 SET (Self Service prefix not doubled)" "SET      303 (Reset Keychain): Self Service, Startup, Custom: installKeychain -> Self Service, Recurring Check-in, Login" "$WORK/set-all-apply.out"
assert_eq "set-all: 303 startup off" "false" "$(get_field 303 '/policy/general/trigger_startup/text()')"
assert_eq "set-all: 303 login on" "true" "$(get_field 303 '/policy/general/trigger_login/text()')"
assert_eq "set-all: 303 event cleared" "" "$(get_field 303 '/policy/general/trigger_other/text()')"
assert_eq "set-all: 101 checkin on, one element" "1" "$(get_field 101 'count(/policy/general/trigger_checkin[text()="true"])')"
assert_grep "set-all: 101 already (idempotent second pass would say ALREADY)" "SET      101" "$WORK/set-all-apply.out"
run set-again Set_Policy_Triggers.sh --csv "$CSV" --set checkin,login --backup-dir "$WORK/set-again-bk"
assert_grep "set-triggers idempotent: 303 ALREADY on rerun" "ALREADY  303" "$WORK/set-again.out"

# --- 7. Self Service visibility ------------------------------------------------

dry_then_apply hide Set_Policy_Self_Service.sh --hide
assert_eq "hide: 101 hidden" "false" "$(get_field 101 '/policy/self_service/use_for_self_service/text()')"
assert_eq "hide: 101 SS categories intact" "Productivity" "$(get_field 101 '/policy/self_service/self_service_categories/category/name/text()')"
dry_then_apply show Set_Policy_Self_Service.sh --show
assert_eq "show: 101 shown again" "true" "$(get_field 101 '/policy/self_service/use_for_self_service/text()')"

# --- 8. a signal stops the run (SIGTERM here: a background job ignores SIGINT) ----

printf '101\n303\n' > "$WORK/two.csv"
env -i HOME="$WORK/home" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    JAMF_PRO_URL="$URL" JAMF_PRO_CLIENT_ID=cid JAMF_PRO_CLIENT_SECRET=sec \
    /bin/bash "$SCRIPTS/Disable_Policy.sh" --csv "$WORK/two.csv" --backup-dir "$WORK/int-bk" --delay 3 >"$WORK/int.out" 2>&1 </dev/null &
INT_PID=$!
sleep 1.5
kill -TERM "$INT_PID"
wait "$INT_PID"; INT_RC=$?
assert_eq "signal: script exits 130" "130" "$INT_RC"
assert_grep "signal: first policy was processed" "101" "$WORK/int.out"
assert_nogrep "signal: second policy never reached" "303 (Reset Keychain)" "$WORK/int.out"

# --- 9. backup dir not created when auth fails ---------------------------------

env -i HOME="$WORK/home" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    JAMF_PRO_URL="$URL" JAMF_PRO_CLIENT_ID=cid JAMF_PRO_CLIENT_SECRET=wrong \
    /bin/bash "$SCRIPTS/Enable_Policy.sh" --csv "$CSV" --backup-dir "$WORK/noauth-bk" >"$WORK/noauth.out" 2>&1 </dev/null
assert_eq "bad secret: rc 1" "1" "$?"
assert_grep "bad secret: message names the credentials, not the URL" "rejected the client credentials" "$WORK/noauth.out"
if [[ -e "$WORK/noauth-bk" ]]; then bad "bad secret: no backup dir left behind"; else ok "bad secret: no backup dir left behind"; fi


echo
echo "TOTAL pass=$pass fail=$fail  (work dir: $WORK, removed on exit)"
[[ "$fail" -eq 0 ]]
