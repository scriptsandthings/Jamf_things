#!/bin/zsh
#
##############################
##############################
#
#  Before running this script, try the script User_Cache_And_Saved_App_State_Reset.zsh to see if it resolves the Adobe issue.
#
##############################
##############################
#
#  Reset user level files for Adobe. Removes all Adobe files from /Users/$CurrentUser/Library,
#  as well as all files from /Users/$CurrentUser/Library/Caches,
#  and /Users/$CurrentUser/Library/Saved Application State/
#  for the currently logged in user.
#
##############################
##############################
#
#  Created by Greg Knackstedt
#  4.10.18
#  https://github.com/scriptsandthings/
#
##############################
##############################
#
#find current user
CurrentUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
#
#Remove everything Adobe and all caches from currently logged in user's /Library/
rm -Rf /Users/$CurrentUser/Library/Application\ Support/Adob*
rm -Rf /Users/$CurrentUser/Library/Caches/*
rm -Rf /Users/$CurrentUser/Library/Preferences/Adob*
rm -Rf /Users/$CurrentUser/Library/Preferences/adob*
rm -Rf /Users/$CurrentUser/Library/Preferences/com.adob*
rm -Rf /Users/$CurrentUser/Library/Preferences/ByHost/com.adob*
rm -Rf /Users/$CurrentUser/Library/Saved\ Application\ State/*
rm -Rf /Users/$CurrentUser/Library/Containers/com.adob*
rm -Rf /Users/$CurrentUser/Library/LaunchAgents/com.adob*
rm -Rf /Users/$CurrentUser/Library/Group\ Containers/Adob*
rm -Rf /Users/$CurrentUser/Library/Group\ Containers/com.adob*

exit 0
