#!/bin/sh

# Extension Attribute to determine if Jamf Connect Login is enabled on system

# Uses authchanger to check if any JamfConnectLogin mechs are enabled
if [[ $( /usr/local/bin/authchanger -print | grep JamfConnectLogin ) != "" ]]; then
	/bin/echo "<result>Enabled</result>"
else
	/bin/echo "<result>Disabled</result>"
fi
