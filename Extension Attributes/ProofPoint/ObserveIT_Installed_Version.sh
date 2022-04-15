#!/bin/sh
########################################################################
# A script to collect information on if ProofPoint Observe IT
# is currently installed. Returns version number if installed,
# If ObserveIT is not installed then "Not Installed" will return back
#
# v1.0
# 3.9.2022
# Greg Knackstedt
# https://github.com/scriptsandthings/
# shitttyscripts@gmail.com
#
########################################################################
if [ -e /Library/PEA/agent ]
then 
  fileversion_number="/Library/PEA/agent/version"
	while read -r line; do
    version_number="$line"
     echo "<result>$version_number</result>"
	done < "$fileversion_number"
else
  echo "<result>Not Installed</result>"
fi
