#!/bin/zsh --no-rcs
#
#############################################################################################################################
#
# Jamf Pro Extension Attribute for TouchID Status
# Version: 1.0
#
#
# Greg Knackstedt
# 10.21.2024
# shitttyscripts@gmail.com
# https://github.com/scriptsandthings/
#
#
################### A Jamf Pro Extension Attribute for macOS clients that reports the following settings: ###################
#
# System Level TouchID Checks
# - TouchID Status (Biometrics functionality)
# - Biometrics for Unlock
# - Biometric timeout
# - Passcode input timeout
# 
# User Level TouchID Checks
# - Biometrics for Unlock
# - Biometrics for ApplePay
# - Effective biometrics for ApplePay - ***Not Currently Displaying in EA output***
# - Effective biometrics for Unlock - ***Not Currently Displaying in EA output***
#
#############################################################################################################################
#
# Define Variables
#
#############################################################################################################################
#
# Find currently Logged in console user
CurrentConsoleUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
# Check System TouchID Status
SystemTouchIDStatus=`bioutil -rs | grep "Biometrics functionality" | awk -F': ' '{print $2}'`
# Check System TouchID Status for Unlock
SystemTouchIDStatusForUnlock=`bioutil -rs | grep "Biometrics for unlock" | awk -F': ' '{print $2}'`
# Check System TouchID Timeout Settings
SystemTouchIDTimeout=`bioutil -rs | grep "Biometric timeout (in seconds)" | awk -F': ' '{print $2}'`
# Check System TouchID Match Timeout Settings
SystemTouchIDMatchTimeout=`bioutil -rs | grep "Match timeout (in seconds)" | awk -F': ' '{print $2}'`
# Check System Passcode Timeout Settings
SystemTouchIDPasscodeInputTimeout=`bioutil -rs | grep "Passcode input timeout (in seconds)" | awk -F': ' '{print $2}'`
# Check User's TouchID Status for Unlock
UserTouchIDStatusForUnlock=`bioutil -r | grep "Biometrics for unlock" | awk -F': ' '{print $2}'`
# Check User's TouchID Status for ApplePay
UserTouchIDStatusForApplePay=`bioutil -r | grep "Biometrics for ApplePay" | awk -F': ' '{print $2}'`
# Check User's Effective Biometrics for ApplePay
UserTouchIDEffectiveBiometricsForApplePay=`bioutil -r | grep "Effective biometrics for ApplePay" | awk -F': ' '{print $2}'`
# Check User's Effective Biometrics for Unlock
UserTouchIDEffectiveBiometricsForUnlock=`bioutil -r | grep "Effective biometrics for unlock" | awk -F': ' '{print $2}'`
#
#############################################################################################################################
#
# Define Functions
#
#############################################################################################################################
#
# Find number of Fingerprints registered for users with TouchID enabled
function GetFingerprintInfo (){
	# Step 1: Check if users have current fingerprint registrations, loop through each line of the command output containing a UID to pair it & fingerprints registered for each UID with a local username on the macOS client 
	bioutil -cs | grep "User [0-9]\+:" | while read -r line; do
    # Step 2: Extract UID from the line
    uid=$(echo "$line" | awk -F'[ :]' '{print $2}')
    # Step 3: Extract the local user account name corresponding to the UID
    TouchIDUsername=$(id "$uid" | awk -F'[()]' '{print $2}')
    # Step 4: Extract the number of biometric templates (registered fingerprints) from the line
    TouchIDFingerprintsEnrolled=$(echo "$line" | awk '{print $3}')
	# If no registered fingerprints found, report no fingerpints found for user
    if [[ "$TouchIDFingerprintsEnrolled" = "0" ]]; then
		echo "<result>No Fingerprints Enrolled for $TouchIDUsername</result>"
	elif [[ "$TouchIDFingerprintsEnrolled" -gt 0 ]]; then
		# Report results for the user's fingerpint registration
		echo "<result>$TouchIDUsername: $TouchIDFingerprintsEnrolled Fingerprints Registered</result>"
	fi
	done
}
#
#############################################################################################################################
#
# Begin Script
#
#############################################################################################################################
#
# Check if TouchID is enabled at the system level
if [[ "$SystemTouchIDStatus" = "0" ]]; then
	SystemTouchIDStatusResult="TouchID Enabled: False"
elif [[ "$SystemTouchIDStatus" = "1"  ]]; then
	SystemTouchIDStatusResult="TouchID Enabled: True"
	# Check if TouchID is enabled for Unlock at the system level
	if [[ "$SystemTouchIDStatusForUnlock" = "0" ]]; then
		SystemTouchIDStatusForUnlockResult="TouchID Enabled for Unlock: False"
		elif [[ "$SystemTouchIDStatusForUnlock" = "1"  ]]; then
			SystemTouchIDStatusForUnlockResult="TouchID Enabled for Unlock: True"
	else 
			SystemTouchIDStatusForUnlockResult="Error Checking TouchID Status for Unlock"
	fi
    # Report System TouchID Timeout Setting
	if [[ "$SystemTouchIDTimeout" = "0" ]]; then
		SystemTouchIDTimeoutResult="Biometric Timeout: Not Configured"
		elif [[ "$SystemTouchIDTimeout" -gt 0  ]]; then
			SystemTouchIDTimeoutResult="Biometric Timeout: $SystemTouchIDTimeout Seconds"
	else 
			SystemTouchIDTimeoutResult="Error Checking Biometric Timeout Settings"
	fi
    # Report System TouchID Match Timeout Setting
	if [[ "$SystemTouchIDMatchTimeout" = "0" ]]; then
		SystemTouchIDMatchTimeoutResult="Biometric Match Timeout: Not Configured"
		elif [[ "$SystemTouchIDMatchTimeout" -gt 0  ]]; then
			SystemTouchIDMatchTimeoutResult="Biometric Match Timeout: $SystemTouchIDMatchTimeout Seconds"
	else 
			SystemTouchIDMatchTimeoutResult="Error Checking Biometric Match Timeout Settings"
	fi
	# Report System TouchID Passcode Input Timeout Setting
	if [[ "$SystemTouchIDPasscodeInputTimeout" = "0" ]]; then
		SystemTouchIDPasscodeInputTimeoutResult="Passcode Input Timeout: Not Configured"
		elif [[ "$SystemTouchIDPasscodeInputTimeout" -gt 0 ]]; then
			SystemTouchIDPasscodeInputTimeoutResult="Passcode Input Timeout: $SystemTouchIDPasscodeInputTimeout Seconds"
	else 
			SystemTouchIDPasscodeInputTimeoutResult="Error Checking Passcode Input Timeout Settings"
	fi
	# Check if users have TouchID Enabled for Unlock
	if [[ "$UserTouchIDStatusForUnlock" = "0" ]]; then
		UserTouchIDStatusForUnlockResult="$CurrentConsoleUser: Unlock Disabled"
		elif [[ "$UserTouchIDStatusForUnlock" = "1"  ]]; then
			UserTouchIDStatusForUnlockResult="$CurrentConsoleUser: Unlock Enabled"
	else 
			UserTouchIDStatusForUnlockResult="Error Checking "$CurrentConsoleUser"'s TouchID Status for Unlock"
	fi
	# Check if users have TouchID Enabled for ApplePay
	if [[ "$UserTouchIDStatusForApplePay" = "0" ]]; then
		UserTouchIDStatusForApplePayResult="$CurrentConsoleUser: ApplePay Disabled"
		elif [[ "$UserTouchIDStatusForApplePay" = "1"  ]]; then
			UserTouchIDStatusForApplePayResult="$CurrentConsoleUser: ApplePay Enabled"
	else 
			UserTouchIDStatusForApplePayResult="Error Checking "$CurrentConsoleUser"'s TouchID Status for ApplePay"
	fi
else 
	# If unable to determine TouchID status, report an error
	SystemTouchIDStatusResult="Error Checking if TouchID is enabled on this Mac."
	echo "<result>$SystemTouchIDStatusResult</result>"
	exit 0
fi
#
# Echo all of the results
echo "<result>$SystemTouchIDStatusResult</result>"
echo "<result>$SystemTouchIDStatusForUnlockResult</result>"
echo "<result>$SystemTouchIDTimeoutResult</result>"
echo "<result>$SystemTouchIDMatchTimeoutResult</result>"
echo "<result>$SystemTouchIDPasscodeInputTimeoutResult</result>"
echo "<result>$UserTouchIDStatusForUnlockResult</result>"
echo "<result>$UserTouchIDStatusForApplePayResult</result>"
# Check for user fingerprint registrations and list # of fingerprints per user if registrations are found
GetFingerprintInfo
exit 0
