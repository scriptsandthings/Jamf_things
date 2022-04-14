#!/bin/zsh
# Resets DEPNotify - To be run from Self Service or as a policy
# Greg Knackstedt
# 3.2.2020
# https://github.com/scriptsandthings/
#
#########################
#########################
CurrentConsoleUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
#########################
#########################
#
# Delete the config files from /tmp
rm /var/tmp/depnot*
# Delete the bom files from /tmp
rm /var/tmp/com.depnot*
# Delete plists for current user
rm /Users/"$CurrentConsoleUser"/Library/Preferences/menu.nomad.DEPNot*
# Restart cfprefsd after clearing plists
killall cfprefsd
