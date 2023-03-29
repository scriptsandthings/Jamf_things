#!/bin/zsh
#
##########################################################
#
# Jamf Pro Extension Attribute
# Last 5 Privileges.app reasons.sh
# Version 1.0
# 3.29.2023
#
# This script records the last 5 reasons an end user needs to request local admin rights
# using Privileges.app on macOS from https://github.com/SAP/macOS-enterprise-privileges
# and records the information into Jamf Pro as documented here:
# https://learn.jamf.com/bundle/jamf-pro-documentation-current/page/Computer_Extension_Attributes.html.
#
# The purpose of this script is to improve the end user support experience and for future security audits.
# It is not meant to be intrusive or an invasion of privacy. 
# 
# This script was created by Greg Knackstedt (https://github.com/scriptsandthings/) with assistance from ChatGPT.
# Contact information: Shitttyscripts@gmail.com
#
##########################################################
#
# set the path to the log file we want to search
log_file='/private/var/log/privileges.log'

# read each line of the log file
while read -r line; do
    # if the line contains the pattern 'reason:', extract the date and reason
    if [[ "$line" == *reason:* ]]; then
        # extract the date and time from the line using grep
        date=$(echo "$line" | grep -oE '\b[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\b')
        # extract the reason from the line using sed
        reason=$(echo "$line" | sed 's/.*reason:/reason:/;s/ on MachineID:.*//')
        # append the date and reason to the result output
        result+="${date} ${reason}\n"
    fi
# read from the log file
done < "$log_file"


# read and save the resulting output to the variable $eaResult
# use tail to limit the output to the last 5 matching lines
eaResult=$( echo "$result" | tail -n 5 )

# print the result output to the console
echo "<result>$eaResult</result>"

# Exit the script
exit 0
