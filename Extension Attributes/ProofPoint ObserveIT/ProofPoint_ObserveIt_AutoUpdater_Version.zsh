#!/bin/zsh
#
############################################################
#
# Greg Knackstedt
# https://github.com/scriptsandthings/Jamf_things/
# 5.11.2022
#
# ProofPoint_ObserveIt_AutoUpdater_Version.zsh
# v1.0
#
# Checks for the ProofPoint ObserveIT AutoUpdater daemon installed version
#
############################################################
#
if [ -d /Library/ITUpdater/updater ]; then
    AppVersion=`/usr/bin/defaults read /Library/ITUpdater/updater/updater.Info.plist CFBundleVersion`
    echo "<result>$AppVersion</result>"
else
    echo "<result>Not installed</result>"
fi

exit 0
