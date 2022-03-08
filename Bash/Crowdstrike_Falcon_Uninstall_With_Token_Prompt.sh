#!/bin/bash
#
# Script to be used with Jamf Self Service to uninstall Crowdstrike Falcon, displaying a GUI prompt for the user to enter the Mac's unique maintnance token
#
# Greg Knackstedt
# shitttyscripts@gmail.com
# https://github.com/gknackstedt/
# 2.28.2022
# v1.0
#
# Display a prompt to ask the user for the maintenance token
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
echo "########################"
echo "Token entered as $token"
echo "########################"
echo "########################"
# Run the uninstall command using expect to watch for the prompt to enter the maintnance token.
# Then return the token previously entered by the user to validate and complete the uninstall
echo "########################"
echo "########################"
echo "Uninstalling Crowdstrike Falcon using the previously entered token"
echo "########################"
echo "########################"
/usr/bin/expect -c "
	spawn sudo /Applications/Falcon.app/Contents/Resources/falconctl uninstall -t --maintenance-token
	expect \"Falcon Maintenance Token:\"
	send $token
	send \r
	expect eof
	"
echo "########################"
echo "########################"
echo "Crowdstrike Falcon Uninstall Script Complete."
echo "Be sure to re-install Crowdstrike to bring system into compliance."
echo "########################"
echo "########################"
exit 0
