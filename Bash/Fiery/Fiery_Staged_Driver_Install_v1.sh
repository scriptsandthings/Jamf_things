#!/bin/bash
#
####################################
#
# Fiery_Staged_Driver_Install_v1.sh
#
# Install Fiery Printer Driver from .dmg staged in /Users/Shared
# v1.0
# https://github.com/scriptsandthings
#
# Greg Knackstedt
# 5.12.2022
#
####################################
#
# Variables
#
installDMG="$4"
##
####################################
#
# Begin Script
#
# Remove quarantine bit from staged dmg
xattr -dr com.apple.quarantine /Users/Shared/"$installDMG"
#
# Mount staged .dmg
hdiutil attach /Users/Shared/"$installDMG" -nobrowse
sleep 10
#
# Install Fiery driver
sudo ./Volumes/Fiery\ Printer\ Driver/Fiery\ Printer\ Driver\ Installer.app/Contents/Resources/User\ Software/OSX/Printer\ Driver/Installer\ Wizard.app/Contents/MacOS/Fiery\ Printer\ Driver\ Installer install
sleep 5
#
# Unmount Fiery driver installation disk image
hdiutil detach /Volumes/Fiery\ Printer\ Driver
sleep 5
#
# Delete staged Fiery driver installation .dmg file
rm -Rf /Users/Shared/"$installDMG"

exit 0
