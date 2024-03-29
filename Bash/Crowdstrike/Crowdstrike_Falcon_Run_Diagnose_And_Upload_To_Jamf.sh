#!/bin/zsh
##############################################################################
##############################################################################
##############################################################################
##############################################################################
#
# Crowdstrike_Falcon_Run_Diagnose_And_Upload_To_Jamf.sh
# v1.0
# 3.28.2022
#
# Greg Knackstedt
# shitttyscripts@gmail.com
# https://github.com/scriptsandthings
#
# Need to clean up variables and quotes *
##############################################################################
##############################################################################
# ! ! ! WARNING: THIS WILL PUT A LARGE FILE INTO YOUR JAMF DATABASE ! ! !
#.       ! ! ! WARNING: MISUSE MAY CORRUPT YOUR JAMF DATABASE ! ! !
##############################################################################
##############################################################################
# This was written for a specific use case. To be run on one system at a time,
# the logs downloaded by the IT Security team and immediately deleted from the 
# Jamf inventory record. Failure to do so may cause Jamf to become unresponsive.
##############################################################################
##############################################################################
#
#
##############################################################################
##############################################################################
# Script to call application specific diagnostic scripts and binaries,
# gather the logs in a single .zip archive, and upload the .zip archive
# to the Macs inventory record in Jamf as a file attachment.
##############################################################################
##############################################################################
#
#
# Creates temp working directories in /Users/Shared.
# Redirects logging for this policy to a local .log saved in the temp directory.
# Opens the .log file in Console.app for the user so they can see that the policy is
# making progress since it may take some time to complete depending on what
# application or script is being called.
# Calls a bash command to generate diagnostic logs, with the ability to pass
# two command line switches through to the binary/script being invoked.
# Moves the outputted log files into the temp directory in /Users/Shared. 
# Relaunches Console.app to a fresh .log redirection to show compression and upload progress.
# Compresses that temp directory into a .zip w/a set name.
# Identifies the Macs computer ID in Jamf.
# Uploads the .zip archive as an attachment to the Macs Jamf inventory record.
# Removes any temp files and directories created in the course of this script
# running before exiting.
#
##############################################################################
##############################################################################
#
##############################################################################
############################## Define Variables ##############################
##############################################################################
# Some Params Exist For Future Portability
#
# Script Params for Jamf Pro
#
# $4 - Jamf API Username
# $5 - Jamf API Password
# $6 - Jamf Pro server address - Example: https://jamf.companyname.com/ (Optional - Will read from target Mac
# $7 - Application Name - Example: Crowdstrike Falcon
# $8 - Path to falonctrl binary - Example: /Applications/Falcon.app/Contents/Resources/falconctl
# $9 - Command Switch 1 - Example: diagnose
# Unused Params
# $10 - Command Switch 2 - (Currently unused)
# $11 - Full Path To Output Generated By Diagnostic Command Being Called - Example: /private/tmp/falconctl_diagnos* - (Currently unused, this is hard coded)
# 
# 
##############################################################################
##############################################################################
################################ Set Variables ###############################
##############################################################################
##############################################################################
# Check if the variables have been provided, ask for them if not
#
# Jamf API Username
apiUser="$4"
if [[ -z $apiUser ]]; then
	read -p "Jamf API Username:" apiUser
fi
#
# Jamf API User's password
apiPass="$5"
if [[ -z $apiPass ]]; then
	read -sp "Jamf API User Password:" apiPass
fi
#
# Jamf Pro Server Address
jssHost="$6"
if [[ -z $jssHost ]]; then
	jssHost=$( /usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url )
	else
	jssHost="$6"
fi
#
# Application Title
appName="$7"
if [[ -z $appName ]]; then
	read -sp "Application Title:" appName
fi
#
# Full path to script or binary to be run
diagnosticScript="$8"
if [[ -z $diagnosticScript ]]; then
	read -sp "Diagnostic Script:" diagnosticScript
fi
#
# Switch #1 to pass to the script or binary
diagnosticSwitch="$9"
if [[ -z $diagnosticSwitch ]]; then
	diagnosticSwitch=""
fi
#
# Switch #2 to pass to the script or binary
diagnosticSwitch2="$10"
if [[ -z $diagnosticSwitch2 ]]; then
	diagnosticSwitch2=""
fi
#
# Output path of log
diagnosticOutputPath="$11"
if [[ -z $diagnosticOutputPath ]]; then
	read -sp "Diagnostic Output Path:" diagnosticOutputPath
fi
##############################################################################
##############################################################################
# Set the possible HTTP status/error codes that could be returned by the API
httpCodes="200
201 Request to create or update object successful
204
400 Bad request
401 Authentication failed
403 Invalid permissions
404 Object/resource not found
409 Conflict
500 Internal server error"
#
# Get the system's serial number
serialNumber=`system_profiler SPHardwareDataType | awk '/Serial/ {print $4}' 2>&1`
#
###############################################################################
############################# Bearer Auth Token ###############################
###############################################################################
#
# Request and obtain a bearer authorization token to use when performing actions during
# the policy run attempt
#
# Create base64-encoded credentials
encodedCredentials=$( printf "$apiUser:$apiPass" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i - )
#
# Generate the authToken
authToken=$( /usr/bin/curl $jssHost"/uapi/auth/tokens" \
-s \
-X POST \
-H "Authorization: Basic $encodedCredentials" )
#
# parse authToken for the actual token, omit expiration
token=$( /usr/bin/awk -F \" '{ print $4 }' <<< "$authToken" | /usr/bin/xargs )
#
###############################################################################
########################## End Bearer Auth Token ##############################
###############################################################################
#
###############################################################################
##################### Define File And Directory Paths #########################
###############################################################################
#
# Logging stuff
# Define directory locations and log file names
tempDir="/private/tmp"
usersShared="/Users/Shared"
gatheredLogDir=$usersShared/gatheredLogs_$serialNumber
jamfPolicyLogDir=$gatheredLogDir
jamfPolicyLogName=$appName"_"$serialNumber"_"$(date +%Y%m%d-%H%M).log
jamfPolicyLogPath=$gatheredLogDir/$jamfPolicyLogName
jamfAPILogName=jamfAPILog_$serialNumber"_"$(date +%Y%m%d-%H%M).log
jamfAPILogPath=$usersShared/$jamfAPILogName
#
###############################################################################
################### End Define File And Directory Paths #######################
###############################################################################
#
###############################################################################
########################## Begin Logging For Step 1 ###########################
###############################################################################
#
[[ ! -d ${gatheredLogDir} ]]; mkdir -p $gatheredLogDir
set -xv; exec 1> $jamfPolicyLogPath 2>&1
#
###############################################################################
######################### Prompt User To Begin Step 1 #########################
###############################################################################
#
# Ask the user not to touch anything until the policy shows as finished in Self Service
osascript << EOF
  tell application "Finder"
  activate
  Display Dialog "Your Mac will now gather logs for $appName. \n \n After clicking continue, Console.app will open to display progress as this policy will take some time to complete. \n \n Do not touch anything until the policy shows completed in Self Service. \n \n Once logs are gathered, Console.app will relaunch and the logs will be uploaded to the JSS." buttons {"Continue"} giving up after 20
  end tell
EOF
#
# Open the log file in console so the user can see the progress
open $jamfPolicyLogPath &
#
# Find current user
CurrentConsoleUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
#
# Echo a reminder into Console for the user not to touch anything or close any apps/windows
#
echo -e "\n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n ############################################################################### \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
Running $appName Diagnostics \n
This May Take Some Time... \n
Please Don't Touch Anything $CurrentConsoleUser \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
\n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n "
# Gather log files
sh $diagnosticScript $diagnosticSwitch $diagnosticSwitch2
#
# Close the window for /private/tmp that falconctrl diagnose opened once complete
osascript -e 'tell application "Finder" to close Finder window "tmp"'  
#
# Close Console.app now that we're done collecting logs
killall "Console"
#
###############################################################################
###############################################################################
########################### End Logging For Step 1 ############################
###############################################################################
###############################################################################
#
###############################################################################
###############################################################################
################################ End Step 1 ###################################
###############################################################################
###############################################################################
#
###############################################################################
###############################################################################
########################## Begin Logging For Step 2 ###########################
###############################################################################
###############################################################################
#
# Redirect logs for the remainder of the policy to capture API interaction
set -xv; exec 1> $jamfAPILogPath 2>&1
#
###############################################################################
###############################################################################
######################### Prompt User To Begin Step 2 #########################
###############################################################################
###############################################################################
#
# Display notification that the diagnostic action has completed, and the logs will now be uploaded to the inventory record
osascript << EOF
  tell application "Finder"
  activate
  Display Dialog "Your Mac has completed gathering logs for $appName. \n \n Gathered logs will now be uploaded to Jamf and attached to the Mac's inventory record. \n \n Do not touch anything until the policy shows completed in Self Service. \n \n After clicking continue, Console.app will relaunch to display the file upload progress. \n \n Once the file has been attached to the computers inventory record, Console.app will close and a notification will display indicating the policy has completed." buttons {"Continue"} giving up after 20
  end tell
EOF
#
###############################################################################
###############################################################################
################################ Begin Step 2 #################################
###############################################################################
###############################################################################
#
# Open Console to view the upload progress
open $jamfAPILogPath &
#
# Move the .zip file containing the previously gathered logs into a staging directory with a known name
mv -fv /private/tmp/falconctl_diagnos* $gatheredLogDir
#
# Echo a reminder into Console for the user not to touch anything or close any apps/windows
#
echo -e "\n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n ############################################################################### \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
$appName Diagnostics Complete \n
Prepairing To Uploading Results To Jamf \n
Please Dont Touch Anything $CurrentConsoleUser \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
\n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n "
#
###############################################################################
###############################################################################
####################### Create Archive For Upload #############################
###############################################################################
###############################################################################
#
# Change ownership and permissions on the staging directory
chown -Rfv :staff $gatheredLogDir
chmod -Rfv 777 $gatheredLogDir
#
# Compress the directory we moved the Crowdstrike logs into so we have a .zip with a known name and path to send to the API
ditto -ck --rsrc --sequesterRsrc $gatheredLogDir $usersShared/"$jamfPolicyLogName".zip
#
# Set a single variable with the new .zip of the logs for uploading
logToAttach=$usersShared/"$jamfPolicyLogName".zip
#
# Change ownership and permissions on the .zip archive prior to uploading
chown -Rfv :staff $logToAttach
chmod -Rfv 777 $logToAttach
#
###############################################################################
###############################################################################
############################ End Create Archive ###############################
###############################################################################
###############################################################################
#
#
###############################################################################
###############################################################################
####################### Locate Computer ID In Jamf ############################
###############################################################################
###############################################################################
#
# Find the computers computer ID in Jamf, a requirement for attaching files to records
jssComputerID=$( /usr/bin/curl $jssHost"JSSResource/computers/match/"$serialNumber \
	-s \
	-X GET \
    -H "Authorization: Bearer $token" \
    -H 'Accept: text/xml' | xmllint --format - | grep "<id>" | cut -f2 -d">" | cut -f1 -d"<" )
##################################################################################
#
# Echo a reminder into Console for the user not to touch anything or close any apps/windows
echo -e "\n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n ############################################################################### \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
Uploading Results To Jamf \n
This May Take Some Time... \n
Please Dont Touch Anything $CurrentConsoleUser \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
\n \n "
#
###############################################################################
###############################################################################
####### Begin Archive Upload As Attachment On Computer Inventory Record #######
###############################################################################
###############################################################################
#
# Upload the file to the JSS and attach it to the record
attachFile=$( /usr/bin/curl \
	-s \
	-f \
	-w "%{http_code}" \
    -H "Authorization: Bearer $token" \
   $jssHost"JSSResource/fileuploads/computers/id/"$jssComputerID -F name=@$logToAttach -X POST )
#
##################################################################################
#
# Echo a reminder into Console for the user not to touch anything or close any apps/windows
echo -e "\n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n ############################################################################### \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
Upload Attempt Complete. \n
Cleaning Up \n
This Should Only Take A Moment... \n
Please Dont Touch Anything $CurrentConsoleUser \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
############################################################################### \n
\n \n "
#
##################################################################################
#
# Evaluate HTTP status code from curl attempt
resultStatus=${attachFile: -3}
code=$( /usr/bin/grep $resultStatus <<< $httpCodes )
#
# Close Console.app
killall "Console"
#
#
# Expire the Auth Token since we're done with it
/usr/bin/curl $jssHost"uapi/auth/invalidateToken" \
	-X POST \
	-H "Authorization: Bearer $token"
#
# Remove the staging directory the falconctrl_diagnose_xxxxxxxx.gz was staged in
function cleanUP {
	# Remove the directories created
	rm -Rfv $gatheredLogDir
	# Remove the log from the API upload
	rm -f $jamfAPILogPath
	# Remove the gathered log .zip
	rm -f $logToAttach
	}
#
# Display status dialog based on HTTP status code and exit
if [ "$code" = "204" ]; 
	then
		displayResults="display dialog \"$logToAttach has successfully been attached to the inventory record of $serialNumber\" with title \"Log Upload Sucessful\" buttons {\"OK\"} default button {\"OK\"}"
		/usr/bin/osascript -e "$displayResults"
        cleanUP
        exit 0
	elif [ "$code" = "200" ]; 
		then
			displayResults="display dialog \"$logToAttach has successfully been attached to the inventory record of $serialNumber\" with title \"Log Upload Sucessful\" buttons {\"OK\"} default button {\"OK\"}"
			/usr/bin/osascript -e "$displayResults"
            cleanUP
            exit 0
	else
		displayResults="display dialog \"Error uploading $logToAttach. \n \n HTTP Error Code: $code \n \n Review Logs For Additional Details.\" with title \"Error Uploading Attachment\" buttons {\"OK\"} default button {\"OK\"}"
		/usr/bin/osascript -e "$displayResults"
		open /Users/Shared
		open $jamfAPILogPath
		exit 1
fi
