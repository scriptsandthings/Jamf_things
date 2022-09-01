#!/bin/bash
#
####################################
#
# Apple Software Update - Reset Prefs.sh
#
# Deletes Apple Software Update local cached preferences.
# Resolves "Update not found" issues when updates should appear outside of a deferral window but don't.
#
# v1.0
# https://github.com/scriptsandthings
#
# Greg Knackstedt
# 8.31.2022
#
##################
echo "----------------"
echo "Deleting Apple Software Update preferences..."
rm -fv /Library/Preferences/com.apple.SoftwareUpdate.plist
echo "----------------"
