#!/bin/bash
# Greg Knackstedt
# https://github.com/ShitttyScripts/Shittty_macOS
# ShitttyScripts(AT)gmail.com
# 2.9.2020
# v1.0
#
# macOS management scripts
# Targeted for macOS 10.12-10.15
#
# Check that prestage files exist
# Install system config profile for jump network
# Verify system is connected to jump network SSID
# Remove current jamf binary/profiles
# Force close self service if open.
# Run QuickAdd.pkg to enroll in new Jamf instance
#
ScriptName="JamfNACMigration.sh"
#
################### Jamf Script Parameters ###################
#
# Company Name for /Library/CompanyName/ standard directory
# Set with Jamf Script Parameter #4
CompanyName="$4"
#
# Name of configuration profile
# Set with Jamf Script Parameter #5
ProfileName="$5"
#
# Name of .pkg to be installed
# Set with Jamf Script Parameter #6
PKGName="$6"
#
# Name of jump network between enrollment
# Set with Jamf Script Parameter #7
JumpNetworkName="$7"
#
# Name of jump network between enrollment
# Set with Jamf Script Parameter #8
JumpNetworkName="$8"
#
# Number of seconds to wait between checking if system is connected to $JumpNetworkName SSID
# Set with Jamf Script Parameter #9
SSIDWaitSeconds="$9"
#
# Number of times to loop checking for the $JumpNetworkName SSID before exiting script
# Set with Jamf Script Parameter #10
SSIDTryCount="$10"
#
################### Script Path Paramaters ###################
#
# Path to directory containing config profiles
ProfilePath="/Library/$CompanyName/profiles"
ProfileFullPath="$ProfilePath"/"$ProfileName"
#
# Path to directory containing pkg files
PKGPath="/Library/$CompanyName/pkg"
PKGFullPath="$PKGPath"/"$PKGName"
#
# Path to jamf Binary
JamfBinary="/usr/local/jamf/bin/jamf"
#
################### Log Parameters ###################
#
# Current date and time to seconds
# $DateTimeStampFull - Date time stamp - 01-26-2020_09:53:52
DateTimeStampFull="$(date "+%m.%d.%Y_%H.%M.%S")"
#
# Name of log file - Script name + Date time stamp.txt
LogFileName=""$ScriptName"_"$DateTimeStampFull".txt"
#
# Log file directory
LogDir="/Library/$CompanyName/logs"
#
# Log file name
LogFile="$LogDir"/"$LogFileName"
#
# Identify currently logged in user
CurrentUser="$(stat -f "%Su" /dev/console)"
#
# System Serial Number
SystemSN="$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $(NF-1)}')"
#
################### Log File Functions ###################
#
# Write Local Log file to /Library/CompanyName/logs/LogFileName_DateTime.txt
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
#
################### Jamf Log Functions ###################
#
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
		JssLoggingEnabled "${1}"
		exec 1>&3 2>&4
		echo >&1 ${1}
	}
#
################### SetARDField Script Parameters ###################
#
# Flag="Text1" Text2 Text3 Text4
Flag="Text1"
Flag2="Text2"
Flag3="Text3"
Flag4="Text4"
#
# ARD Kickstart binary path
KickstartBinary="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
#
# ARD plist and computer info field
ARDPlistFlag=$(defaults read /Library/Preferences/com.apple.RemoteDesktop.plist "$Flag")
ARDPlistFlag2=$(defaults read /Library/Preferences/com.apple.RemoteDesktop.plist "$Flag2")
ARDPlistFlag3=$(defaults read /Library/Preferences/com.apple.RemoteDesktop.plist "$Flag3")
ARDPlistFlag4=$(defaults read /Library/Preferences/com.apple.RemoteDesktop.plist "$Flag4")
#
################### Identify System Status Script Functions ###################
#
# JSS Address
function IdentifyCurrentJSSAddress
	{
		JSSAddress=$($JamfBinary checkJSSConnection | sed -e 's/:*//' | awk -F "/" '{print $3}')
	}
#
# Jamf Binary Version
function GetJamfBinaryVersion
	{
		JamfBinaryVersion=$($JamfBinary version)
	}
#
# Identify SSID system is connected to and store as $SSID variable.
function IdentifyCurrentlyConnectedSSID
	{
		SSID="$(/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I | awk -F: '/ SSID/{print $2}' | awk '{$1=$1};1')"
	}
#
# Top console user for system
function IdentifyTopConsoleUser
	{
		SystemTopConsoleUser="$(ac -p | sort -nk 2 | grep -v reboot | grep -v shutdown | awk '/total/{print x};{x=$1}')"
	}
#
################### SetARDField Script Functions ###################
#
# Sets ARD field 1 to the jss address the system is currently enrolled with
function SetARD1CurrentJSSAddress
	{
		if [ -z "$ARDPlistFlag" ]; then
		  echo "ARD flag $ARDPlistFlag is blank. Setting flag to: $JSSAddress"
		  $KickstartBinary -configure -computerinfo -set1 -1 "$JSSAddress"
		else
		  if [ "$Flag" != "$ARDPlistFlag" ];
		  	then
				echo "ARD flag $ARDPlistFlag, is outdated. Updating flag to: $JSSAddress."
				$KickstartBinary -configure -computerinfo -set1 -1 "$JSSAddress"
		  fi
		fi
	}
#
# Sets ARD Field 2 to the currently installed jamf binary version
function SetARD2JamfBinaryVersion
	{
		if [ -z "$ARDPlistFlag2" ]; then
		  echo "ARD flag $ARDPlistFlag2 is blank. Setting flag to: $JamfBinaryVersion"
		  $KickstartBinary -configure -computerinfo -set2 -2 "$JamfBinaryVersion"
		else
		  if [ "$Flag2" != "$ARDPlistFlag2" ]; then
			echo "ARD flag $ARDPlistFlag2, is outdated. Updating flag to: $JamfBinaryVersion."
			$KickstartBinary -configure -computerinfo -set2 -2 "$JamfBinaryVersion"
		  fi
		fi
	}
#
# Sets ARD field 3 to the currently connected SSID
function SetARD3SSID
	{
		if [ -z "$ARDPlistFlag3" ]; then
		  echo "ARD flag $ARDPlistFlag3 is blank. Setting flag to: $SSID"
		  $KickstartBinary -configure -computerinfo -set3 -3 "$SSID"
		else
		  if [ "$Flag3" != "$ARDPlistFlag3" ]; then
			echo "ARD flag $ARDPlistFlag3, is outdated. Updating flag to: $SSID."
			$KickstartBinary -configure -computerinfo -set3 -3 "$SSID"
		  fi
		fi
	}
#
# Sets ARD field 4 to the systems top console user - identified locally, not 100% always
# but it's helpful to locate systems in ARD later if a user is not currently logged in
function SetARD4TopConsoleUser
	{
		if [ -z "$ARDPlistFlag4" ]; then
		  echo "ARD flag $ARDPlistFlag4 is blank. Setting flag to: $SystemTopConsoleUser"
		  $KickstartBinary -configure -computerinfo -set4 -4 "$SystemTopConsoleUser"
		else
		  if [ "$Flag4" != "$ARDPlistFlag4" ]; then
			echo "ARD flag $ARDPlistFlag4, is outdated. Updating flag to: $SystemTopConsoleUser."
			$KickstartBinary -configure -computerinfo -set4 -4 "$SystemTopConsoleUser"
		  fi
		fi
	}
#
################### Set Above In ARDField Function ###################
#
# Set all 4 ARD custom computer info fields from functions above.
function SetARDFields
	{
		echo "###############################"
		echo "Updating ARD computer info fields 1-4"
		echo "###############################"
		GetJamfBinaryVersion
		IdentifyCurrentJSSAddress
		IdentifyCurrentlyConnectedSSID
		IdentifyTopConsoleUser
		SetARD1CurrentJSSAddress
		SetARD2JamfBinaryVersion
		SetARD3SSID
		SetARD4TopConsoleUser
	}
#
################### WiFi Network Service - 1st Priority - Functions ###################
#
# Turns WiFi power on, and enables the network service if it is disabled
function EnableWiFi
	{
		echo "###############################"
		echo "Turning on Wi-Fi if it is off."
		echo "###############################"
		networksetup -setairportpower Wi-Fi on
		sleep 2
		echo "###############################"
		echo "Enabling Wi-Fi network service if it is currently disabled."
		echo "###############################"
		networksetup -setnetworkserviceenabled Wi-Fi on
		sleep 2
	}
#
# Display system's network services in order of priority.
# This will show up in logging.
function ListNetworkServicePriority
	{
		echo "###############################"
		echo "Current network service priority is:"
		echo "###############################"
		networksetup -listnetworkserviceorder
	}
#
# Set wifi as the highest priority network service
function SetWiFiPriorityNetworkService
	{
		echo "###############################"
		echo "Setting WiFi network service as top priority for all network traffic."
		echo "###############################"
		echo "networksetup -ordernetworkservices "Wi-Fi" `networksetup -listallnetworkservices | grep -v 'An asterisk ' |  sed s/\^'*'// | grep -v Wi-Fi | sed 's/.*/\"&\"/' | tr '\n' ' '` "| bash
		sleep 2
	}
#
################### Jamf10Migration Functions ###################
#
# Update ARD computer info fields 1-4.
# Verify that staging files exist, if not throw an error and exit.
function VerifyPreStage
	{
		echo "###############################"
		echo "Updating ARD computer info fields 1-4."
		SetARDFields
		echo "ARD fields updated."
		echo "###############################"
		if [ -f "$ProfileFullPath" && -f "$PKGFullPath" ];
			then
   				echo "###############################"
				echo "$PKGFullPath and $ProfileFullPath are NOT present on the system."
				echo "No changes have been made to the system."
				echo "Exiting safely..."
				echo "###############################"
   				exit 127
   			else
				echo "###############################"
   				echo "Verified $PKGFullPath and $ProfileFullPath are present on the system."
   				echo "Continuing."
   				echo "###############################"
		fi
	}
#
# Import .mobileconfig profile
function ImportProfile
	{
		echo "###############################"
		echo "Installing configuration profile: "$ProfilePath"/"$ProfileName""
		echo "###############################"
		profiles -I -F "$ProfilePath"/"$ProfileName"
	}
#
# Verify that system has connected to the specified SSID successfully before continuing.
# Check every 5 seconds for connection. After 90 seconds (18 iterations) exit with an error.
function VerifiySSIDConnected
	{
		echo "###############################"
		echo "Checking current Wi-Fi network."
		echo "###############################"
		if [ "$SSID" != "$JumpNetworkName" ] && [ "$SSIDCount" -ne "0" ];
			then
				echo "###############################"
				echo "Currently connected to the $SSID network."
				echo "Verifying system has connected to the $JumpNetworkName network before proceeding."
				echo "Giving the system 10 seconds to establish a connection."
				echo "###############################"
				while [ "$SSID" != "$JumpNetworkName" ] && [ "$SSIDCount" -ne "0" ];
					do
						# Wait 20 seconds
						# Check the current SSID again
						sleep "$SSIDWaitSeconds"
						echo "###############################"
						echo "Currently connected to the $SSID network."
						echo "System must be connected to the $JumpNetworkName network before proceeding."
						echo "###############################"
						echo "Checking again in $SSIDWaitSeconds seconds."
						echo "###############################"
						echo "###############################"
						IdentifyCurrentlyConnectedSSID
						SSIDCount=$((SSIDCount=SSIDCount-1))
						if [ "$SSID" = "$JumpNetworkName" ];
							then
								echo "###############################"
								echo "System is currently connected to the $SSID network."
								echo "Proceeding."
								echo "###############################"
								SetARDFields
								sleep 5
								break
						elif  [ "$SSID" != "$JumpNetworkName" ] && [ "$SSIDCount" -ne "0" ];
							then
								echo "###############################"
								echo "Unable to connect to the $JumpNetworkName network."
								echo "No changes have been made to the system."
								echo "Exiting safely..."
								echo "###############################"
								exit 127
						fi
					done
		elif [ "$SSID" == "$JumpNetworkName" ];
			then
				echo "###############################"
				echo "System is currently connected to the $SSID network."
				echo "Proceeding."
				echo "###############################"
				SetARDFields
				sleep 5
		elif [ "$SSID" != "$JumpNetworkName" ];
			then
				echo "###############################"
				echo "Unable to connect to a Wi-Fi network."
				echo "No changes have been made to the system."
				echo "Exiting safely..."
				echo "###############################"
				exit 127
		else
			echo "###############################"
			echo "Unable to connect to the $JumpNetworkName network."
			echo "No changes have been made to the system."
			echo "Exiting safely..."
			echo "###############################"
			exit 127
		fi
	}
#
# Unenroll from JSS/Remove framework/binary
function JamfUnenroll
	{
		echo "###############################"
		echo "Removing existing Jamf binary/configuration profiles."
		echo "###############################"
		$JamfBinary removeMDMProfile
		sleep 3
		$JamfBinary removeFramework
		sleep 3
		killall "Self Service"
		sleep 3
	}
#
# Run QuickAdd.pkg
function InstallQuickAddPKG
	{
		echo "###############################"
		echo "Installing package: $PKGPath/$PKGName"
		echo "###############################"
		installer -allowUntrusted -verbose -pkg "$PKGPath"/"$PKGName" -target /
	}
#
################### Script ###################
LocalScriptLoggingEnabled
JSSScriptLoggingEnabled
LogJamfParams
SetARDFields
VerifyPreStage
EnableWiFi
ListNetworkServicePriority
SetWiFiPriorityNetworkService
ListNetworkServicePriority
SetARDFields
ImportProfile
VerifiySSIDConnected
JamfUnenroll
InstallQuickAddPKG
