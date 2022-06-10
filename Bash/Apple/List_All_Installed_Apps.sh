#!/bin/zsh
#######################
#
# List_All_Installed_Apps.sh v1.1
#
# Finds and lists all installed applications on a Mac.
#       Short script to list all .app bundles on a Mac using Spotlight to search the contents of /Applications/.
#       Apple applications are excluded using the com.apple.* bundle identifier.
# Greg Knackstedt
# 6.10.2022
#
######################
#
mdfind -onlyin /Applications/ '(kMDItemCFBundleIdentifier != "com.apple.*" && kMDItemKind == "Application"' | sort -g
