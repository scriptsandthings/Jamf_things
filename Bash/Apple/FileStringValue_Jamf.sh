#!/bin/bash
#
############################################
###########################################
#
# Greg Knackstedt
# gmknacks(AT)gmail.com
# https://github.com/scriptsandthings/
#
###########################################
###########################################
#
# FileStringValue_Jamf.sh
#
# Checks if a FullTargetFile exists
# Verifies the first string is correct
# Checks for an existing string
# If string exists it is set to defined Value
# if string does not exist the fully defined string will be appended to the end of the FullTargetFile
#
##############################################################
################ Default Variable Declaration ################
##############################################################
#
# Current date
# echo "Date stamp - $DateStamp"
# $ Date stamp - 01.26.2020
DateStamp=$(date +"%m.%d.%Y")
#
# Current date and time to seconds
# $ Date time stamp - 01.26.2020_09.3.52
# echo "Date time stamp - $DateTimeStamp"
DateTimeStamp=$(date "+%m.%d.%Y_%H.%M.%S")
#
# Backup $FullTargetFile name
BackupFileExt="backup.$DateTimeStamp.txt"
#
# Where to place backups
BackupDir="/Users/Shared/bin/Backup"
#
# Identify currently logged in user
CurrentUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
#
########################################################
################ JAMF Script Parameters ################
########################################################
#
# $4 - Set action for script
# 1 - remove string
# 2 - Add/modify string
# 3 - Reset FullTargetFile to default
#
# $5 - Set the full path with name and extension of the target FullTargetFile
# Example: /Users/username/Folder/FullTargetFile.txt
#
# $6 - Required first string for valid target FullTargetFile if required
# Example: [default]
#
# $7 - Set the string you want add/change
# Example: DSDontWriteNetworkStores
#
# $8 - Define the value the string should be set to
# Example: True
#
###########################################
############### Parameters ################
###########################################
#
# Set action for script
# Defined with Jamf script paramater value 4
# 1 - remove string
# 2 - Add/modify string
# 3 - Reset FullTargetFile to default
Action=$4
#
# Full path to the target file
# Defined with Jamf script paramater value 5
TargetFilePath=$5
#
# Full name of target file including extension
# Defined with Jamf script paramater value 6
TargetFileName=$6
#
# Required default string
# Defined with Jamf script paramater value 7
FullTargetFileHead=$7
#
# Define string which stores setting
# Defined with Jamf script paramater value 8
String=$8
#
# Specify value for string
# Defined with Jamf Paramater 9
StringValue=$9
#
###########################################
################ Variables ################
###########################################
#
# Define full String
FullString="$String=$StringValue"
#
# Combine target path and filename
FullTargetFile="$TargetFilePath/$TargetFileName"
#
###########################################
################ Functions ################
###########################################
#
# Make a local backup of the target FullTargetFile to BackupDir
function MakeBackup
	{
		echo "------------------------"
		echo "Making backup copy of $TargetFileName."
		echo "The backup will be saved here:"
		echo "$BackupDir/$TargetFileName.$BackupFileExt"
		echo ""
		ditto "$FullTargetFile" "$BackupDir"/"$TargetFileName"."$BackupFileExt"
	}
#
# Display the variables to console
function DisplayParameters
	{
		clear
		echo "------------------------"
		echo "FileStringValueJamf.sh"
		echo "------------------------"
		echo ""
		echo "Selected Script Parameters"
		echo ""
		echo "Action Parameter: $Action"
		echo ""
		echo "Target FullTargetFile: $FullTargetFile"
		echo "Default FullTargetFile Head: $FullTargetFileHead"
		echo "Target String: $String"
		echo "Target String Value $StringValue"
		echo "Resulting String: $FullString"
		echo ""
		echo "------------------------"
		echo "If $FullTargetFile exists, a backup will be made before any actions are taken."
		echo "------------------------"
		echo ""
		echo "The backup copy FullTargetFilename will be: $FullTargetFile.$BackupFileExt"
		echo "The backup will be saved to the following directory:"
		echo "$BackupDir"
	}
# Add previously defined string including value
function WriteString
	{
		echo "$FullString" | tee -a "$FullTargetFile"
	}
#
# Update existing string with new value
function ModifyString
	{
		sed -i '' "s/$String=.*/$String=$StringValue/" "$FullTargetFile"
	}
#
# Create empty FullTargetFile
function CreateFullTargetFile
	{
		touch "$FullTargetFile"
	}
#
# Write default head to FullTargetFile
function WriteFullTargetFileHead
	{
		echo "$FullTargetFileHead" >> "$FullTargetFile"
	}
#
# Remove bad default FullTargetFile
function RemoveFullTargetFile
	{
		rm -f "$FullTargetFile"
	}
#
# Add string or set value in valid target FullTargetFile
function ValidFullTargetFile
	{
		WriteString
	}
#
# Check FullTargetFile for string then change value or append string to FullTargetFile
function KeepString
	{
		if grep -q "$String.*" "$FullTargetFile";
			then
				ModifyString
			else
				WriteString
		fi
	}
#
# Remove string from FullTargetFile
function RemoveString
	{
		sed -i '' "s/$String=.*//" "$FullTargetFile"
	}
#
# Verify target FullTargetFile contains valid first line
function CheckFullTargetFileHead
	{
		if [ $FullTargetFileHeadVerified = true ];
			then
				# Bypass first line check if
				echo "------------------------"
				echo "$FullTargetFile head check bypassed."
			else
				echo "------------------------"
				echo "- Checking head of FullTargetFile."
				if [ $(head -n 1 "$FullTargetFile") = "$FullTargetFileHead" ];
					then
						FullTargetFileHeadVerified=true
						echo "------------------------"
						echo "- $FullTargetFileHead is the head of $FullTargetFile."
					else
						FullTargetFileHeadVerified=false
						echo "------------------------"
						echo "$FullTargetFileHead is NOT the head of $FullTargetFile."
				fi
		fi
	}
#
# create Default FullTargetFile
function CreateDefaultFullTargetFile
	{
		echo "------------------------"
		echo "- Creating default $FullTargetFile"
		CreateFullTargetFile
		WriteFullTargetFileHead
	}
#
# Replace invalid FullTargetFile with new and write desired string
function ReplaceFullTargetFile
	{
		RemoveFullTargetFile
		CreateDefaultFullTargetFile
		WriteString
	}
#
# Reset target FullTargetFile with new and write default string
function ResetFullTargetFile
	{
		echo "------------------------"
		echo "- Resetting $FullTargetFile to default."
		RemoveFullTargetFile
		CreateDefaultFullTargetFile
		CheckFullTargetFileHead
	}
#
# Verify target FullTargetFile contains valid first line
function CheckFullTargetFileHead
{
	if [ "$FullTargetFileHeadVerified" = true ];
		then # Bypass first line check if
			echo "------------------------"
			echo "$FullTargetFile head check bypassed."
	else
		echo "- Checking head of FullTargetFile."
		if [ $(head -n 1 "$FullTargetFile") = "$FullTargetFileHead" ];
			then
				FullTargetFileHeadVerified=true
				echo "------------------------"
				echo "$FullTargetFileHead is the head of $FullTargetFile."
		else
			FullTargetFileHeadVerified=false
				echo "------------------------"
				echo "$FullTargetFileHead is NOT the head of $FullTargetFile."
				ResetFullTargetFile
	fi
fi
}
#
# Check if FullTargetFile exists
function DoesFullTargetFileExist
	{
		echo "------------------------"
		echo  "- Checking if $FullTargetFile exists."
		if [ -f "$FullTargetFile" ];
			then
				echo "------------------------"
				echo  "$FullTargetFile found."
				MakeBackup
				CheckFullTargetFileHead
			else
				echo "------------------------"
				echo  "$FullTargetFile NOT found."
				CreateDefaultFullTargetFile
		fi
}
#
# Error if action not defined
function ActionNotDefined
	{
		echo "------------------------"
		echo "------------------------"
		echo "------------------------"
		echo ""
		echo ""
		echo "Something's wrong, I can feel it...."
		echo ""
		echo ""
		echo "Verify the parameters of the script and try again."
		echo "Nothing has been done. Exiting."
		echo "------------------------"
		echo "------------------------"
		echo "------------------------"
	}
#
# Check if FullTargetFile exists then start action based on result
function PerformTasks
{
	if [ "$Action" -eq "1" ]
		then
			RemoveString
			exit
	elif [ "$Action" -eq "2" ]
		then
			KeepString
			exit
	elif [ "$Action" -eq "3" ]
		then
			ResetFullTargetFile
			exit
	else
		ActionNotDefined
		exit
	fi
}
#
###########################################
################ Script ###################
###########################################
#
DisplayParameters
DoesFullTargetFileExist
PerformTasks
