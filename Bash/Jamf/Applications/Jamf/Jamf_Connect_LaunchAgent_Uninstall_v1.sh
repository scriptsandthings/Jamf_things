#!/bin/zsh
# 
###############################
#
# Jamf_Connect_LaunchAgent_Uninstall_v1.sh
# Checks for the Jamf Connect LaunchAgent and if found, unloads and removes the LaunchAgent
# 5.11.2022
# v1.0
# Greg Knackstedt
# https://github.com/scriptsandthings/ 
#
###############################
#
# Checks for the Jamf Connect LaunchAgent and if found, unloads and removes the LaunchAgent
# 
###############################
#
laPath="/Library/LaunchAgents/"
laName="com.jamf.connect.plist"

if [ -e "${laPath}${laName}" ]; then
sudo launchctl unload "${laPath}${laName}"
rm -f "${laPath}${laName}"
fi

echo "${laName} Not Installed"

exit 0
