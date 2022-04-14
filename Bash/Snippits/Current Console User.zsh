#!/bin/zsh
#
# Use scutil to identify the currently logged in user
CurrentConsoleUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
# Echo current logged in user to terminal output
echo "$CurrentConsoleUser"
#
exit 0
