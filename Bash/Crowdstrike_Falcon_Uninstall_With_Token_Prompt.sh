#!/bin/bash
#####################################
#####################################
# Script to be used with Jamf Self Service to uninstall Crowdstrike Falcon, displaying a GUI prompt for the user to enter the Mac's unique maintnance token
#
# v1.0
# 3.7.2022
#
# Greg Knackstedt
# shitttyscripts@gmail.com
# https://github.com/gknackstedt/
#
###### Things to add/fix with this script in the future #####
# 1. Add logic that allows the script to run the uninstall command without the -t --maintenance-token flags for systems that the system/kernel extensions 
# are no longer loaded or damaged, which causes the Crowdstrike uninstall protection to no longer be enforced, resulting in an error if those flags
# are passed at the time the uninstall command is run.
#
# 2. Valid exit codes/messages passed to the log via echo for display in the Jamf policy log based on the result of the uninstall attempt, 
# instead of just copping out by saying "Uninstall complete", throwing an exit 0, and relying on the person 
# running the policy to figure out if it was successful or not by completing an addtional task/check manually outside of Self Service.
#
#####################################
#####################################
#
# Display a prompt in the GUI to ask the user for the maintenance token using osascript
token=$( /usr/bin/osascript <<EOT
tell application "System Events"
activate
display dialog "To uninstall Crowdstrike, Enter this Mac's Crowdstrike Maintenance Token. You will have to reach out to a member of IT Security to retrieve this token." default answer ""
if button returned of result is "OK" then
set tokencode to text returned of result
return tokencode
end if
if button returned of result is "Cancel" then
error number -128
end if
end tell
EOT)
#
echo "########################"
echo "The Crowdstrike Maintenance Token entered was: $token"
echo "########################"
# Run the uninstall command using expect to watch for the prompt to enter the maintnance token.
# Then return the $token previously entered by the user in the osascript prompt to complete the uninstall
echo "########################"
echo "Uninstalling Crowdstrike Falcon using the previously entered token"
echo "########################"
/usr/bin/expect -c "
	spawn sudo /Applications/Falcon.app/Contents/Resources/falconctl uninstall -t --maintenance-token
	expect \"Falcon Maintenance Token:\"
	send $token
	send \r
	expect eof
	"
echo "########################"
echo "Crowdstrike Falcon Uninstall Script Complete."
echo "Be sure to re-install Crowdstrike to bring system into compliance."
echo "########################"
exit 0
