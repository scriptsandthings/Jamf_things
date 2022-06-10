#!/bin/zsh
#######################
#
# List_All_Installed_Apps.sh v1.0
#
# Finds and lists all installed applications on a Mac.
#       Short script to list all .app bundles on a Mac using Spotlight to search the entire drive.
# Greg Knackstedt
# 6.10.2022
#
######################
#
mdfind -onlyin /Applications/ '(kMDItemCFBundleIdentifier != "com.apple.*" && kMDItemCFBundleIdentifier != "com.adobe.*") && kMDItemKind == "Application"' | sort -g
