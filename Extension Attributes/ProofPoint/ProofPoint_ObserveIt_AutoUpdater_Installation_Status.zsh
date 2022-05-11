#!/bin/zsh
#
############################################################
#
# Greg Knackstedt
# https://github.com/scriptsandthings/Jamf_things/
# 5.11.2022
#
# ProofPoint_ObserveIt_AutoUpdater_Installation_Status.zsh
# v1.0
#
# Checks for the ProofPoint ObserveIT AutoUpdater daemon and reports a True or False status
#
############################################################
#
updaterPath="/Library/ITUpdater/updater/"
updaterName="autoUpdater"
result="False"
#
if [ -e "${updaterPath}${updaterName}" ]; then
    result="True"
fi
#
echo "<result>$result</result>"
#
exit 0
