#!/bin/zsh
#################################
#################################
# Installs from a .dmg placed by a staging package into /Users/Shared/
# Set the .dmg name with Jamf Script option $4
# This method of install ensures that USB device passthrough functions
# without the need for local admin rights.
# Script developed with feedback from VMware support, as they had not previously
# recieved a request for a silent install method.
#
# Greg Knackstedt
# https://github.com/scriptsandthings/
# 6.20.2021
#################################
#################################
#
# Remove VMware Horizon Client from /Applications/
rm -Rf /Applications/VMware\ Horizon\ Client.app
#
# Remove VMware Horizon Client files from /Library/Application Support/
rm -Rf /Library/Application\ Support/VMware/VMware\ Horizo*
sleep 5
#
# Remove the quarantine bit from the .dmg prior to copy.
# This step is essential in setting USB passthrough as enabled
xattr -dr com.apple.quarantine /Users/Shared/"$4"
#
# Mount the DMG
hdiutil attach /Users/Shared/"$4" -nobrowse
sleep 10
#
# Copy the VMware Horizon Client.app to /Applications/
cp -pPR /Volumes/VMware\ Horizon\ Client/VMware\ Horizon\ Client.app /Applications/
sleep 10
#
# Unmount the .dmg
hdiutil detach /Volumes/VMware\ Horizon\ Client
sleep 5
#
# Clean up the staged .dmg
rm -Rf /Users/Shared/"$4"
#
#Set the rights of the USB kexts and support files so they may be loaded by unprivileged users
/Applications/VMware\ Horizon\ Client.app/Contents/Library/InitUsbServices.tool
sleep 5
#
# Start Services - Not needed
# sh /Applications/VMware\ Horizon\ Client.app/Contents/Library/services.sh --start
exit 0
