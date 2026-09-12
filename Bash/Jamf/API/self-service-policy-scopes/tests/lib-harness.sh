#!/bin/bash
# Library fixture harness. Run: env -i HOME=/nonexistent PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash tests/lib-harness.sh
set -u
RT=$(cd "$(dirname "$0")" && pwd)/fixtures
LIB=$(cd "$(dirname "$0")/.." && pwd)/scripts/lib/jamf-api-common.sh
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lib-harness.XXXXXX")
# shellcheck source=../scripts/lib/jamf-api-common.sh
. "$LIB"
echo "bash=$BASH_VERSION awk=$(which awk) sed=$(which sed) xmllint=$(which xmllint)"
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "PASS $1"; }
bad()  { fail=$((fail+1)); echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '     %s\n' "$@"; }
# assert_eq name expected actual
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: [$2]" "actual:   [$3]"; fi; }
# diffstat before after -> prints "added removed"
diffstat() { diff "$1" "$2" | awk '/^>/{a++} /^</{r++} END{print a+0, r+0}'; }

P=$(xmllint --format "$RT/policy-101.xml")
A=$(xmllint --format "$RT/policy-202.xml")
SCOPE=$(echo "$P" | awk '/<scope>/,/<\/scope>/')
GENERAL=$(echo "$P" | awk '/^[[:space:]]*<general>[[:space:]]*$/,/^[[:space:]]*<\/general>[[:space:]]*$/')
SS=$(echo "$P" | awk '/^[[:space:]]*<self_service>[[:space:]]*$/,/^[[:space:]]*<\/self_service>[[:space:]]*$/')
ASCOPE=$(echo "$A" | awk '/<scope>/,/<\/scope>/')
AGENERAL=$(echo "$A" | awk '/^[[:space:]]*<general>[[:space:]]*$/,/^[[:space:]]*<\/general>[[:space:]]*$/')
echo "$SCOPE" > "$WORK/scope.before"; echo "$GENERAL" > "$WORK/general.before"; echo "$P" > "$WORK/policy.before"

echo "--- readers"
assert_eq "GetPolicyEnabled"           "true"  "$(GetPolicyEnabled "$P")"
assert_eq "GetPolicyEnabled(all)"      "false" "$(GetPolicyEnabled "$A")"
assert_eq "GetLegacyTrigger"           "EVENT" "$(GetLegacyTrigger "$P")"
assert_eq "GetPolicySelfService"       "true"  "$(GetPolicySelfService "$P")"
assert_eq "GetPolicySelfService(all)"  "false" "$(GetPolicySelfService "$A")"
assert_eq "GetPolicyCategory (&amp; decoded)" "5|Apps & Utilities" "$(GetPolicyCategory "$P")"
assert_eq "GetPolicyCategory(self-closing)" "|" "$(GetPolicyCategory "$A")"
assert_eq "GetPolicyTriggerState checkin" "true" "$(GetPolicyTriggerState "$P" trigger_checkin)"
assert_eq "GetPolicyTriggerState other"   "install-foo" "$(GetPolicyTriggerState "$P" trigger_other)"
assert_eq "GetPolicyTriggerState absent"  "" "$(GetPolicyTriggerState "$P" trigger_bogus)"
assert_eq "GetPolicyTriggers"          "Self Service, Recurring Check-in, Custom: install-foo" "$(GetPolicyTriggers "$P")"
assert_eq "GetPolicyTriggers(all)"     "none" "$(GetPolicyTriggers "$A")"
assert_eq "PolicyHasAutomaticTrigger"  "yes" "$(PolicyHasAutomaticTrigger "$P")"
assert_eq "PolicyHasAutomaticTrigger(all)" "no" "$(PolicyHasAutomaticTrigger "$A")"
assert_eq "CountScopeTargets"          "4" "$(CountScopeTargets "$P")"
assert_eq "CountScopeTargets(all)"     "0" "$(CountScopeTargets "$A")"
assert_eq "CountScopeEntry targets cg id 7"      "1" "$(CountScopeEntry "$P" targets computer_groups computer_group id 7)"
assert_eq "CountScopeEntry targets cg id 77"     "1" "$(CountScopeEntry "$P" targets computer_groups computer_group id 77)"
assert_eq "CountScopeEntry exclusions cg id 77"  "0" "$(CountScopeEntry "$P" exclusions computer_groups computer_group id 77)"
assert_eq "CountScopeEntry exclusions cg id 7"   "1" "$(CountScopeEntry "$P" exclusions computer_groups computer_group id 7)"
assert_eq "CountScopeEntry limitations ug name Corp.Marketing" "1" "$(CountScopeEntry "$P" limitations user_groups user_group name Corp.Marketing)"
assert_eq "CountScopeEntry limitations ug name CorpXMarketing" "1" "$(CountScopeEntry "$P" limitations user_groups user_group name CorpXMarketing)"
assert_eq "CountScopeEntry exclusions ug name CorpXMarketing"  "0" "$(CountScopeEntry "$P" exclusions user_groups user_group name CorpXMarketing)"
assert_eq "CountScopeEntry targets cg name 'R & D'" "1" "$(CountScopeEntry "$P" targets computer_groups computer_group name 'R & D')"
assert_eq "CountScopeEntry absent section" "0" "$(CountScopeEntry "$A" exclusions computer_groups computer_group id 7)"
assert_eq "CountScopeEntry limitations users name alice" "1" "$(CountScopeEntry "$P" limitations users user name alice)"
assert_eq "CountScopeEntry exclusions users name alice"  "1" "$(CountScopeEntry "$P" exclusions users user name alice)"

echo "--- ReadPolicyIDsFromCSV"
# ids.csv (checked in): header, quoted ID, blank line, comment, padded ID, non-numeric, tab-separated.
assert_eq "ReadPolicyIDsFromCSV mixed" "101 202 303" "$(ReadPolicyIDsFromCSV "$RT/ids.csv" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "ReadPolicyIDsFromCSV tsv report" "101 202" "$(ReadPolicyIDsFromCSV "$RT/policies.tsv" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "ReadPolicyIDsFromCSV UTF-8 BOM, no header" "123 456" "$(ReadPolicyIDsFromCSV "$RT/bom.csv" | tr '\n' ' ' | sed 's/ $//')"

echo "--- ReplaceElementInSection"
# R1 leaf
out=$(ReplaceElementInSection "$GENERAL" general enabled "<enabled>false</enabled>"); rc=$?
echo "$out" > "$WORK/r1.after"
assert_eq "R1 leaf rc" "0" "$rc"
assert_eq "R1 leaf exactly one <enabled>" "1" "$(echo "$out" | grep -c '<enabled>')"
assert_eq "R1 leaf value" "false" "$(echo "<policy>$out</policy>" | xmllint --xpath '/policy/general/enabled/text()' -)"
assert_eq "R1 leaf diffstat (1 added 1 removed)" "1 1" "$(diffstat "$WORK/general.before" "$WORK/r1.after")"
assert_eq "R1 &amp; in name preserved" "1" "$(echo "$out" | grep -c '<name>Install Foo &amp; Bar</name>')"
# R2 block, on the FULL policy so the self_service category must be untouched
out=$(ReplaceElementInSection "$P" general category "<category><id>-1</id></category>"); rc=$?
echo "$out" > "$WORK/r2.after"
assert_eq "R2 block rc" "0" "$rc"
assert_eq "R2 block one general/category" "1" "$(echo "$out" | xmllint --xpath 'count(/policy/general/category)' -)"
assert_eq "R2 block new id" "-1" "$(echo "$out" | xmllint --xpath '/policy/general/category/id/text()' -)"
assert_eq "R2 self_service category untouched" "Productivity" "$(echo "$out" | xmllint --xpath '/policy/self_service/self_service_categories/category/name/text()' -)"
assert_eq "R2 diffstat (1 added 4 removed)" "1 4" "$(diffstat "$WORK/policy.before" "$WORK/r2.after")"
assert_eq "R2 scope+self_service byte-identical" "" "$(diff <(echo "$P" | awk '/<scope>/,/<\/policy>/') <(echo "$out" | awk '/<scope>/,/<\/policy>/'))"
# R3 self-closing
out=$(ReplaceElementInSection "$AGENERAL" general category "<category><id>5</id></category>"); rc=$?
assert_eq "R3 self-closing rc" "0" "$rc"
assert_eq "R3 self-closing count <category>" "1" "$(echo "$out" | grep -c '<category>')"
assert_eq "R3 self-closing no <category/> left" "0" "$(echo "$out" | grep -c '<category/>')"
out=$(ReplaceElementInSection "$AGENERAL" general trigger_other "<trigger_other>evt</trigger_other>"); rc=$?
assert_eq "R3b self-closing leaf rc" "0" "$rc"
assert_eq "R3b self-closing leaf count" "1" "$(echo "$out" | grep -c '<trigger_other')"
# R4 absent
G4=$(echo "$GENERAL" | grep -v '<trigger_other>')
out=$(ReplaceElementInSection "$G4" general trigger_other "<trigger_other>new-evt</trigger_other>"); rc=$?
assert_eq "R4 absent rc" "0" "$rc"
assert_eq "R4 absent count" "1" "$(echo "$out" | grep -c '<trigger_other>')"
assert_eq "R4 absent placed before </general>" "<trigger_other>new-evt</trigger_other>" "$(echo "$out" | tail -2 | head -1 | sed 's/^[[:space:]]*//')"
# R5 wrong section -> exit 1, nothing changed
out=$(ReplaceElementInSection "$GENERAL" scope enabled "<enabled>false</enabled>"); rc=$?
assert_eq "R5 wrong section rc" "1" "$rc"
# R6 leaf with &amp; content replaced (name)
out=$(ReplaceElementInSection "$GENERAL" general name "<name>A &amp; B</name>"); rc=$?
assert_eq "R6 leaf-with-entity rc" "0" "$rc"
assert_eq "R6 leaf-with-entity count (policy, category, site)" "3" "$(echo "$out" | grep -c '<name>')"
# R7 dropping a block must not swallow past its own close (site block after category)
out=$(ReplaceElementInSection "$GENERAL" general category "<category><id>2</id></category>")
assert_eq "R7 site block survives category replace" "1" "$(echo "$out" | grep -c '<site>')"
# R8 leaf value containing a slash / dot regex-ish: element name only used; test trigger_other value 'a.b-c'
out=$(ReplaceElementInSection "$GENERAL" general trigger_other "<trigger_other>a.b-c</trigger_other>")
assert_eq "R8 trigger_other value" "a.b-c" "$(echo "<policy>$out</policy>" | xmllint --xpath '/policy/general/trigger_other/text()' -)"

echo "--- InsertScopeEntry"
chk_insert() { # name section container node xpath_expect_count xpath_other_untouched
	local name="$1" section="$2" container="$3" node="$4"
	out=$(InsertScopeEntry "$SCOPE" "$section" "$container" "$node"); rc=$?
	echo "$out" > "$WORK/ins.after"
	assert_eq "$name rc" "0" "$rc"
	assert_eq "$name wellformed" "0" "$(echo "<policy>$out</policy>" | xmllint --noout - 2>&1 | wc -l | tr -d ' ')"
	echo "<policy>$out</policy>" > "$WORK/ins.policy"
}
chk_insert "I1 targets cg 42" targets computer_groups "<computer_group><id>42</id></computer_group>"
assert_eq "I1 targets count 42" "1" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" targets computer_groups computer_group id 42)"
assert_eq "I1 exclusions count 42" "0" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" exclusions computer_groups computer_group id 42)"
assert_eq "I1 diffstat" "1 0" "$(diffstat "$WORK/scope.before" "$WORK/ins.after")"
chk_insert "I2 limitations ug 99" limitations user_groups "<user_group><id>99</id></user_group>"
assert_eq "I2 limitations count 99" "1" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" limitations user_groups user_group id 99)"
assert_eq "I2 exclusions count 99" "0" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" exclusions user_groups user_group id 99)"
assert_eq "I2 diffstat" "1 0" "$(diffstat "$WORK/scope.before" "$WORK/ins.after")"
chk_insert "I3 exclusions cg 42" exclusions computer_groups "<computer_group><id>42</id></computer_group>"
assert_eq "I3 exclusions count 42" "1" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" exclusions computer_groups computer_group id 42)"
assert_eq "I3 targets count 42" "0" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" targets computer_groups computer_group id 42)"
assert_eq "I3 diffstat" "1 0" "$(diffstat "$WORK/scope.before" "$WORK/ins.after")"
chk_insert "I4 limitations self-closing network_segments" limitations network_segments "<network_segment><id>5</id></network_segment>"
assert_eq "I4 count" "1" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" limitations network_segments network_segment id 5)"
assert_eq "I4 exclusions untouched" "0" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" exclusions network_segments network_segment id 5)"
assert_eq "I4 diffstat (3 added 1 removed)" "3 1" "$(diffstat "$WORK/scope.before" "$WORK/ins.after")"
chk_insert "I5 exclusions self-closing computers" exclusions computers "<computer><id>9</id></computer>"
assert_eq "I5 exclusions computers 9" "1" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" exclusions computers computer id 9)"
assert_eq "I5 targets computers 9 untouched" "0" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" targets computers computer id 9)"
assert_eq "I5 targets computers 1 intact" "1" "$(CountScopeEntry "$(cat "$WORK/ins.policy")" targets computers computer id 1)"
# I6 all_computers fixture: self-closing target container, self-closing <exclusions/>
out=$(InsertScopeEntry "$ASCOPE" targets computer_groups "<computer_group><id>42</id></computer_group>"); rc=$?
assert_eq "I6 all_computers targets rc" "0" "$rc"
assert_eq "I6 all_computers targets count" "1" "$(CountScopeEntry "<policy>$out</policy>" targets computer_groups computer_group id 42)"
assert_eq "I6 all_computers still true" "true" "$(echo "<policy>$out</policy>" | xmllint --xpath '/policy/scope/all_computers/text()' -)"
out=$(InsertScopeEntry "$ASCOPE" exclusions computer_groups "<computer_group><id>42</id></computer_group>"); rc=$?
assert_eq "I7 self-closing <exclusions/> rc" "0" "$rc"
assert_eq "I7 self-closing <exclusions/> count" "1" "$(CountScopeEntry "<policy>$out</policy>" exclusions computer_groups computer_group id 42)"
assert_eq "I7 wellformed" "0" "$(echo "<policy>$out</policy>" | xmllint --noout - 2>&1 | wc -l | tr -d ' ')"
# I8 exclusions section entirely absent
S8=$(echo "$SCOPE" | awk '/<exclusions>/{skip=1} !skip{print} /<\/exclusions>/{skip=0}')
out=$(InsertScopeEntry "$S8" exclusions computer_groups "<computer_group><id>42</id></computer_group>"); rc=$?
assert_eq "I8 absent section rc" "0" "$rc"
assert_eq "I8 absent section count" "1" "$(CountScopeEntry "<policy>$out</policy>" exclusions computer_groups computer_group id 42)"
assert_eq "I8 wellformed" "0" "$(echo "<policy>$out</policy>" | xmllint --noout - 2>&1 | wc -l | tr -d ' ')"
# I9 targets container absent (no <computer_groups> before limitations)
S9=$(echo "$SCOPE" | awk '/<computer_groups>/&&!done{skip=1} !skip{print} /<\/computer_groups>/&&skip{skip=0;done=1}')
out=$(InsertScopeEntry "$S9" targets computer_groups "<computer_group><id>42</id></computer_group>"); rc=$?
assert_eq "I9 targets container absent rc" "0" "$rc"
assert_eq "I9 targets count" "1" "$(CountScopeEntry "<policy>$out</policy>" targets computer_groups computer_group id 42)"
assert_eq "I9 exclusions cg 7 intact" "1" "$(CountScopeEntry "<policy>$out</policy>" exclusions computer_groups computer_group id 7)"
assert_eq "I9 wellformed" "0" "$(echo "<policy>$out</policy>" | xmllint --noout - 2>&1 | wc -l | tr -d ' ')"
# I10 container present in exclusions but ALSO absent in limitations: limitations computer_groups (not valid in Jamf, but library must place it under limitations not exclusions)
out=$(InsertScopeEntry "$SCOPE" limitations user_groups "<user_group><name>New.Group</name></user_group>")
assert_eq "I10 limitations by-name placed" "1" "$(CountScopeEntry "<policy>$out</policy>" limitations user_groups user_group name New.Group)"
assert_eq "I10 not in exclusions" "0" "$(CountScopeEntry "<policy>$out</policy>" exclusions user_groups user_group name New.Group)"

echo "--- RemoveScopeEntry"
out=$(RemoveScopeEntry "$SCOPE" targets computer_groups computer_group id 7); rc=$?
echo "$out" > "$WORK/rm.after"
assert_eq "D1 targets rm cg 7 rc" "0" "$rc"
assert_eq "D1 targets 7 gone" "0" "$(CountScopeEntry "<policy>$out</policy>" targets computer_groups computer_group id 7)"
assert_eq "D1 targets 77 stays" "1" "$(CountScopeEntry "<policy>$out</policy>" targets computer_groups computer_group id 77)"
assert_eq "D1 exclusions 7 stays" "1" "$(CountScopeEntry "<policy>$out</policy>" exclusions computer_groups computer_group id 7)"
assert_eq "D1 diffstat (0 added 4 removed)" "0 4" "$(diffstat "$WORK/scope.before" "$WORK/rm.after")"
out=$(RemoveScopeEntry "$SCOPE" exclusions computer_groups computer_group id 7); rc=$?
assert_eq "D2 exclusions rm cg 7 rc" "0" "$rc"
assert_eq "D2 exclusions 7 gone" "0" "$(CountScopeEntry "<policy>$out</policy>" exclusions computer_groups computer_group id 7)"
assert_eq "D2 targets 7 stays" "1" "$(CountScopeEntry "<policy>$out</policy>" targets computer_groups computer_group id 7)"
out=$(RemoveScopeEntry "$SCOPE" limitations user_groups user_group name Corp.Marketing); rc=$?
assert_eq "D3 limitations rm Corp.Marketing rc" "0" "$rc"
assert_eq "D3 Corp.Marketing gone from limitations" "0" "$(CountScopeEntry "<policy>$out</policy>" limitations user_groups user_group name Corp.Marketing)"
assert_eq "D3 CorpXMarketing stays" "1" "$(CountScopeEntry "<policy>$out</policy>" limitations user_groups user_group name CorpXMarketing)"
assert_eq "D3 exclusions Corp.Marketing stays" "1" "$(CountScopeEntry "<policy>$out</policy>" exclusions user_groups user_group name Corp.Marketing)"
S4=$(RemoveScopeEntry "$SCOPE" limitations user_groups user_group id 11)
out=$(RemoveScopeEntry "$S4" limitations user_groups user_group name Corp.Marketing); rc=$?
assert_eq "D4 Corp.Marketing must not match CorpXMarketing (rc 1)" "1" "$rc"
assert_eq "D4 CorpXMarketing untouched" "1" "$(CountScopeEntry "<policy>$S4</policy>" limitations user_groups user_group name CorpXMarketing)"
out=$(RemoveScopeEntry "$SCOPE" targets computer_groups computer_group id 4242); rc=$?
assert_eq "D5 absent entry rc" "1" "$rc"
out=$(RemoveScopeEntry "$SCOPE" exclusions users user name alice); rc=$?
assert_eq "D6 exclusions rm alice rc" "0" "$rc"
assert_eq "D6 limitations alice stays" "1" "$(CountScopeEntry "<policy>$out</policy>" limitations users user name alice)"
assert_eq "D6 exclusions alice gone" "0" "$(CountScopeEntry "<policy>$out</policy>" exclusions users user name alice)"
out=$(RemoveScopeEntry "$SCOPE" targets computers computer id 1); rc=$?
assert_eq "D7 targets rm computer 1 rc" "0" "$rc"
assert_eq "D7 wellformed" "0" "$(echo "<policy>$out</policy>" | xmllint --noout - 2>&1 | wc -l | tr -d ' ')"
assert_eq "D7 CountScopeTargets now 3" "3" "$(CountScopeTargets "<policy>$out</policy>")"
# D8 group 7 vs 77 the other way: remove 77, 7 stays
out=$(RemoveScopeEntry "$SCOPE" targets computer_groups computer_group id 77)
assert_eq "D8 rm 77 keeps 7" "1" "$(CountScopeEntry "<policy>$out</policy>" targets computer_groups computer_group id 7)"
assert_eq "D8 77 gone" "0" "$(CountScopeEntry "<policy>$out</policy>" targets computer_groups computer_group id 77)"
# D9 remove by name with &: the writers reject & in names before reaching here; document behaviour
out=$(RemoveScopeEntry "$SCOPE" targets computer_groups computer_group name 'R & D'); rc=$?
echo "NOTE D9 RemoveScopeEntry by raw name 'R & D' rc=$rc (formatted XML holds R &amp; D; writers reject & in --user-group so unreachable)"

echo "--- Set_Policy_Triggers.sh DescribeTriggers"
eval "$(sed -n '/^DescribeTriggers() {/,/^}/p' "$(dirname "$LIB")/../Set_Policy_Triggers.sh")"
assert_eq "DescribeTriggers general-only + ss true" "Self Service, Recurring Check-in, Custom: install-foo" "$(DescribeTriggers "<policy>$GENERAL</policy>" true)"
assert_eq "DescribeTriggers general-only + ss false" "Recurring Check-in, Custom: install-foo" "$(DescribeTriggers "<policy>$GENERAL</policy>" false)"
assert_eq "DescribeTriggers none" "none" "$(DescribeTriggers "<policy>$AGENERAL</policy>" false)"
assert_eq "DescribeTriggers ss only" "Self Service" "$(DescribeTriggers "<policy>$AGENERAL</policy>" true)"
# Simulate Set_Policy_Triggers loop: turn checkin off, startup on, custom event set, then describe
NG="$GENERAL"
for el in trigger_checkin trigger_startup; do
	want=false; [ "$el" = trigger_startup ] && want=true
	NG=$(ReplaceElementInSection "$NG" general "$el" "<${el}>${want}</${el}>") || bad "loop replace $el"
done
NG=$(ReplaceElementInSection "$NG" general trigger_other "<trigger_other>new-evt</trigger_other>")
assert_eq "Set_Policy_Triggers loop result" "Startup, Custom: new-evt" "$(DescribeTriggers "<policy>$NG</policy>" false)"
assert_eq "Set_Policy_Triggers loop exactly one of each" "1 1 1" "$(echo "$NG" | grep -c "<trigger_checkin>") $(echo "$NG" | grep -c "<trigger_startup>") $(echo "$NG" | grep -c "<trigger_other>")"
assert_eq "Set_Policy_Triggers loop wellformed" "0" "$(echo "<policy>$NG</policy>" | xmllint --noout - 2>&1 | wc -l | tr -d ' ')"

echo "--- Self Service leaf via ReplaceElementInSection (Set_Policy_Self_Service path)"
out=$(ReplaceElementInSection "$SS" self_service use_for_self_service "<use_for_self_service>false</use_for_self_service>"); rc=$?
assert_eq "SS leaf rc" "0" "$rc"
assert_eq "SS leaf count" "1" "$(echo "$out" | grep -c '<use_for_self_service>')"
assert_eq "SS categories untouched" "Productivity" "$(echo "<policy>$out</policy>" | xmllint --xpath '/policy/self_service/self_service_categories/category/name/text()' -)"

echo; echo "TOTAL pass=$pass fail=$fail"
