#!/bin/sh

#  Reset_Adobe_User_Level_v2 - runs as currently logged in user
#  Reset user level files for Adobe. Removes all Adobe files from ~/Library
#
#  Created by Greg Knackstedt on 4.10.18.

#Current user
CurrentUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')

#clear user caches
rm -Rf /Users/$CurrentUser/Library/Caches/*
#clear saved application state
rm -Rf /Users/$CurrentUser/Library/Saved\ Application\ State/*

exit
