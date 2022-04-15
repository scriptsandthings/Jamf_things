#!/bin/bash
#
####################
####################
#
# Greg Knackstedt
# gmknacks(AT)gmail.com
# https://github.com/scriptsandthings/
#
####################
####################
#
# DefaultsWriteCurrentUser_Jamf.sh
#
# For information on how to use defaults write refer to the man page
# man defaults
#
# Use the defaults write command to change a defined setting in a .plist for the current user
# Uses Jamf script parameters for portability
#
# By defining script parameters $4, $5, $6, and $7, the following example command
# would be executed targeting the currently logged in user
#
#  defaults write com.apple.desktopservices.plist DSDontWriteNetworkStores true
#
############################################################
#################### Script Parameters #####################
############################################################
#
# $4 - Define path to directory containing .plist within the user directory
# Do not include an opening / or trailing / in the path
# Example: Preferences
#
# $5 - Define .plist file to target
# You use the full file name including the file extension
# Example: com.apple.desktopservices.plist
#
# $6 - Define the string to target with defaults write
# Example: DSDontWriteNetworkStores
#
# $7 - Define value to set for the string
# Example: true
#
################ Default Variable Declaration ################
#
# Identify currently logged in user
CurrentUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
#
# Current date
# echo "Date stamp - $DateStamp"
# $ Date stamp - 01.26.2020
DateStamp=$(date +"%m.%d.%Y")
#
# Current date and time to seconds
# $ Date time stamp - 01.26.2020_09.53.52
# echo "Date time stamp - $DateTimeStamp"
DateTimeStamp=$(date "+%m.%d.%Y_%H.%M.%S")
#
# Backup $TargetFileFull name
BackupFileExt="backup.$CurrentUser.$DateTimeStamp.plist"
#
# Where to place backups
BackupDir="/Users/Shared/bin/Backup"
#
# Define the current user's home directory
UserHome="/Users/$CurrentUser"
#
# Define current user's /Library/Preferences/ folder
UserLib="$UserHome/Library"
#
# Define path to directory containing .plist within the user directory
# Example: Preferences/Microsoft
PlistDir="$4/"
#
# Define .plist file to target
# Example: com.apple.desktopservices.plist
TargetFileName=$5
#
# Combine above to define the full path to the target plist for current console UserDefaultsWrite
TargetFileFull="$UserLib/$PlistDir/$TargetFileName"
#
# Define string to target with defaults write
# Example: DSDontWriteNetworkStores
TargetString=$6
#
# Define value to set $TargetString
TargetStringValue=$7
#
################ Functions ################
#
# Make a local backup of the target TargetFileFull to BackupDir
function MakeBackup
	{
		echo "------------------------"
		echo "Making backup copy of $TargetFileName."
		echo "The backup will be saved here:"
		echo "$BackupDir/$TargetFileName.$BackupFileExt"
		echo ""
		ditto "$TargetFileFull" "$BackupDir"/"$TargetFileName"."$BackupFileExt"
	}
#
# Call defaults write to apply the defined value to the defined string in the targeted .plist for current user
function UserDefaultsWrite
	{
		defaults write $TargetFileFull $TargetString $TargetStringValue
	}
#
# Set ownership of plist to $CurrentUser:staff
function RepairOwnership
	{
		chown -Rf $CurrentUser:staff $TargetFileFull
	}
#
# Restart services for CFPreferences and NSUserDefaults
function ApplyChange
	{
		killall cfprefsd
	}
#
################ Script ################
#
MakeBackup
UserDefaultsWrite
RepairOwnership
ApplyChange
