#!/bin/bash
#
# Greg Knackstedt
# gmknacks(AT)gmail.com
# https://github.com/scriptsandthings/
#
# FinderViewCurrentUserPlistBuddy_Jamf.sh
#
# Based on Jamf Script option $4 and a value of "true" or "false" the following is set:
#
# To improve SMB performance in macOS,
# it is recommended to disable file and icon previews in Finder.
# This script removes current file and icon preview settings in Finder,
# then sets the following
#
# Cover-flow View - preview carousel
# Icon View - icon preview
# List Vies - icon preview
# Column View - icon preview
# Column View - preview column
#
################ Variables ################
#
# Identify currently logged in user
CurrentUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
# Set location of PlistBuddy
PlistBuddy=/usr/libexec/PlistBuddy
# Set location of current users com.apple.finder.plist
UserPlist=/Users/$CurrentUser/Library/Preferences/com.apple.finder.plist
#
# Define if value will be "$FinderPreviewSettingValue" true or false
# This is set using Jamf script paramiter 4
FinderPreviewSettingValueValue=$4
################ functions ###############
#
# Clear current Finder preview settings
function ClearFinderPreviewSettingValues
	{
		# Delete the existing cover-flow preview setting
		$PlistBuddy -c 'Delete StandardViewSettings:ExtendedListViewSettings:showIconPreview' $UserPlist;
		# Delete the existing icon preview setting
		$PlistBuddy -c 'Delete StandardViewSettings:IconViewSettings:showIconPreview' $UserPlist;
		# Delete the existing list icon preview setting
		$PlistBuddy -c 'Delete StandardViewSettings:ListViewSettings:showIconPreview' $UserPlist;
		# Delete the existing column icon preview setting
		$PlistBuddy -c 'Delete StandardViewOptions:ColumnViewOptions:ShowIconThumbnails' $UserPlist;
		# Delete the existing column preview column setting
		$PlistBuddy -c 'Delete StandardViewOptions:ColumnViewOptions:ColumnShowIcons' $UserPlist;
	}
#
# Set Finder preview settings to disabled
function SetFinderPreviewSettingValues
	{
		#Reset the cover-flow preview setting to off
		$PlistBuddy -c 'Add StandardViewSettings:ExtendedListViewSettings:showIconPreview bool "$FinderPreviewSettingValue"' $UserPlist;
		#Reset the icon preview setting to off
		$PlistBuddy -c 'Add StandardViewSettings:IconViewSettings:showIconPreview bool "$FinderPreviewSettingValue"' $UserPlist;
		#Reset the list icon preview setting to off
		$PlistBuddy -c 'Add StandardViewSettings:ListViewSettings:showIconPreview bool "$FinderPreviewSettingValue"' $UserPlist;
		#Reset the column icon preview setting to off
		$PlistBuddy -c 'Add StandardViewOptions:ColumnViewOptions:ShowIconThumbnails bool "$FinderPreviewSettingValue"' $UserPlist;
		#Reset the column preview column setting to off
		$PlistBuddy -c 'Add StandardViewOptions:ColumnViewOptions:ColumnShowIcons bool "$FinderPreviewSettingValue"' $UserPlist;
	}
# Set ownership of plist to CurrentUser:staff
function RepairOwnership
	{
		chown -R $CurrentUser:staff $UserPlist
	}
#
# Restart services for CFPreferences and NSUserDefaults, then relaunch Finder to apply change
function ApplyChange
	{
		killall cfprefsd
	}
#
################ Script ################
ClearFinderPreviewSettingValues
SetFinderPreviewSettingValues
RepairOwnership
ApplyChange
