#!/bin/zsh
# 
#################################
#
# Jamf_Connect_LaunchAgent_Install_Status.zsh
#
# Greg Knackstedt
# 5.11.2022
# v1.0
#
# Checks for the Jamf Connect LaunchAgent presence and reports a True or False status if it is found
# 
#################################
#
launchAgentPath="/Library/LaunchAgents/"
launchAgentName="com.jamf.connect.plist"
result="False"

if [ -e "${launchAgentPath}${launchAgentName}" ]; then
    result="True"
fi

echo "<result>$result</result>"

