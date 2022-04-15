#!/bin/zsh
############################
#
# There is an Extension Attribute (EA) Template to go along with this script.
#
############################
#
# Based upon the post by Jamf Nation user sdagley, but to remove a flag file set with the script in the provided link.
# Greg Knackstedt
# https://github.com/scriptsandthings/
# 2.12.2022
# Original Source by sdagley: https://community.jamf.com/t5/jamf-pro/add-a-system-to-a-smartgroup-using-self-service/m-p/238671
#
# This script is intended to be used as a script in a Jamf Pro Policy. It will remove a
# flag file previously placed on a Mac whos presence can be read by an EA script which in turn can
# be used as a Smart Group Criteria. This was created to allow Self Service initiated
# scoping of Configuration Profile deployments.
#
############################
#
# $4 - Path of directory containing the Flag File
# $5 - Name of Flag File to remove

FlagFilePath="$4"
FlagFileName="$5"

if [ -z "${FlagFilePath}" ] || [ -z "${FlagFileName}" ]; then
    echo "Both the path to the flag file and the flag file name must be provided"
    exit 1
fi

rm "${FlagFilePath}${FlagFileName}"

/usr/local/bin/jamf recon

exit 0
