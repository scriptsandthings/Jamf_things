#!/bin/bash
###############################
#
# Jamf_Connect_LaunchAgent_Uninstall - v2.5.sh
# Checks for Jamf Connect related LaunchAgents, if found unloads and deletes them.
# 9.3.2022
# v2.5
# Greg Knackstedt
# 
# - Based on the Jamf provided Jamf Connect Uninstaller.pkg written by Matthew Ward and Sameh Sayed.
# - A more complete removal of additional Jamf Connect related launch agents then my original attempt.
#
###############################
# 
# Quit Connect if running 
ConnectProcess=$(pgrep 'Jamf Connect')

if [ "$ConnectProcess" -gt 0 ]; then
    kill "$ConnectProcess"
fi

/usr/bin/logger 'Killing Jamf Connect processes'

# Variables
/usr/bin/logger 'starting script'
SyncLA='/Library/LaunchAgents/com.jamf.connect.sync.plist'
VerifyLA='/Library/LaunchAgents/com.jamf.connect.verify.plist'
Connect2LA='/Library/LaunchAgents/com.jamf.connect.plist'
ConnectULA='/Library/LaunchAgents/com.jamf.connect.unlock.login.plist'


# Find if there's a console user or not. Blank return if not.

consoleuser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')

# get the UID for the user

uid=$(/usr/bin/id -u "$consoleuser")
/usr/bin/logger ''''
/usr/bin/logger 'Console user is '"$consoleuser"', UID: '"$uid"''


# disable and remove LaunchD components

if [ -f "$SyncLA" ]; then
	/bin/echo ''''
    /bin/echo "Jamf Connect Sync Launch Agent is present. Unloading &amp; removing.."
    /bin/launchctl bootout gui/"$uid" "$SyncLA"
   sudo /bin/rm -rf "$SyncLA"
        else 
    /bin/echo "Jamf Connect Sync launch agent not installed"
fi

if [ -f "$VerifyLA" ]; then
	/bin/echo ''''
    /bin/echo "Jamf Connect Verify Launch Agent is present. Unloading &amp; removing.."
    /bin/launchctl bootout gui/"$uid" "$VerifyLA"
   sudo /bin/rm -rf "$VerifyLA"
        else 
    /bin/echo "Jamf Connect Verify launch agent not installed"
fi

if [ -f "$Connect2LA" ]; then
	/bin/echo ''''
    /bin/echo "Jamf Connect 2 Launch Agent is present. Unloading &amp; removing.."
    /bin/launchctl bootout gui/"$uid" "$Connect2LA"
   sudo /bin/rm -rf "$Connect2LA"
        else 
    /bin/echo "Jamf Connect 2 launch agent not installed"
fi

if [ -f "$ConnectULA" ]; then
	/bin/echo ''''
    /bin/echo "Jamf Connect Unlock Launch Agent is present. Unloading &amp; removing.."
    /bin/launchctl bootout gui/"$uid" "$ConnectULA"
    sudo /bin/rm -rf "$ConnectULA"
        else 
    /bin/echo "Jamf Connect Unlock launch agent not installed"
fi
/bin/echo ''''

/bin/echo "Jamf Connect LaunchAgents removed"

exit 0
