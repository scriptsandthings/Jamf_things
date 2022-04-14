#!/bin/zsh
#######################
#######################
#
# Greg Knackstedt
# 9.2.2021
# https://github.com/scriptsandthings/
#
#######################
#######################
#
# Remove Nudge system wide preferences
rm -Rfv /Library/Preferences/com.github.macadmins.Nudge.plist
# Remove Nuge plist from all user directories
rm -rfv /Users/*/Library/Preferences/com.github.macadmins.Nudge.plist
exit 0
