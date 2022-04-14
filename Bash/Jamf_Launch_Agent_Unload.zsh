#!/bin/zsh
#
# Unload the Jamf LaunchDaemon responsible for completing system check-in
launchctl unload /Library/LaunchDaemons/com.jamfsoftware.task.1.plist
#
# Sleep for 2 seconds
sleep 2
#
# Exit
exit 0
