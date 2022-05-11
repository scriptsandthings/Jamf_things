#!/bin/sh
#
############################################################
#
# Greg Knackstedt
# https://github.com/scriptsandthings/Jamf_things/
# 5.11.2022
#
# ProofPoint_ObserveIt_AutoUpdater_Version.zsh
# v2.0
#
# Checks for the ProofPoint ObserveIT AutoUpdater daemon and reports the installed version
#
############################################################
updaterPath="/Library/ITUpdater/updater/"
updaterName="autoUpdater"
#
if [ -e "${updaterPath}${updaterName}" ]; then
    updaterVersion=$(/usr/bin/defaults read /Library/ITUpdater/updater/plist/updater.Info.plist CFBundleVersion)
    echo "<result>$updaterVersion</result>"
else
    echo "<result>Not installed</result>"
fi

exit 0
