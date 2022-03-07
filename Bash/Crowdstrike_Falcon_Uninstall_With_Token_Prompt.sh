#!/bin/bash
#
# Uninstall Crowdstrike Falcon prompting the user for maintenance token in the GUI
#
# Greg Knackstedt
# shitttyscripts@gmail.com
# https://github.com/gknackstedt/
# 2.28.2022
# v1.0
#
# Prompt user for maintenance token
token=$( /usr/bin/osascript <<EOT
tell application "System Events"
activate
display dialog "Enter the device's Crowdstrike Maintenance Token" default answer ""
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

# Run the uninstall command and enter the token when prompted
/usr/bin/expect -c "
	spawn sudo /Applications/Falcon.app/Contents/Resources/falconctl uninstall -t --maintenance-token
	expect \"Falcon Maintenance Token:\"
	send $token
	send \r
	expect eof
	"
