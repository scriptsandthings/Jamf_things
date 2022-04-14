#!/bin/bash
# Greg Knackstedt
# 2.14.2020
# v1.1
#
# Functions to write a local log file
# Tested on macOS 10.12-10.15
#
# Just put this into your script or something.. that's how I'm going to use it for now.
#
ScriptName="Script Name.sh"
#
################### Log File Parameters ###################
#
# Current date and time to seconds
# $DateTimeStampFull - Date time stamp - 01-26-2020_09:53:52
DateTimeStampFull=$(date "+%m.%d.%Y_%H.%M.%S")
#
# Name of log file - Script name + Date time stamp.txt
LogFileName="$ScriptName - $DateTimeStampFull.txt"
#
# Name of company for common directory in /Library/
CompanyName="Company Name"
#
# Log file directory
LogDir="/Library/$CompanyName/logs"
#
# Log file name
LogFile="$LogDir"/"$LogFileName"
# Identify currently logged in user
CurrentUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
#
# Jamf binary version
JamfVersion=$(/usr/local/jamf/bin/jamf version)
#
# System Serial Number
SystemSN=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $(NF-1)}')
#
################### Log File Functions ###################
#
# Write Local Log file
function LocalScriptLoggingEnabled
	{
		mkdir -p "$LogDir"
		touch "$LogFile"
		echo "$LogFile"
		exec 3>&1 4>&2 # Save standard output and standard error
		exec 1>>"$LogFile"	# Redirect standard output to logFile
		exec 2>>"$LogFile"	# Redirect standard error to logFile
		echo "########################## Begin Log ##########################" >> "$LogFile"
		echo "$ScriptName" >> "$LogFile"
		echo "$ScriptName" >> "$LogFile"
		echo "$CompanyName" >> "$LogFile"
		echo "$DateTimeStampFull" >> "$LogFile"
		echo "Current Console User: $CurrentUser" >> "$LogFile"
		echo "System Serial Number: $SystemSN" >> "$LogFile"
	}
# Log Jamf script paramaters
function LogJamfParams
	{
		echo "$4" >> "$LogFile"
		echo "$5" >> "$LogFile"
		echo "$6" >> "$LogFile"
		echo "$7" >> "$LogFile"
		echo "$8" >> "$LogFile"
		echo "$9" >> "$LogFile"
		echo "$10" >> "$LogFile"
		echo "$11" >> "$LogFile"
	}
function JSSScriptLoggingEnabled
	{ # Re-direct logging to the JSS
		LocalScriptLoggingEnabled "${1}"
		exec 1>&3 2>&4
		echo >&1 ${1}
	}
################### End Log File Functions ###################
