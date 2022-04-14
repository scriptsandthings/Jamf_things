#!/bin/zsh
############################
#
# There is an Extension Attribute (EA) Template to go along with this script.
#
############################
# Utility - Create Flag File.sh
#
# Originally from Jamf Nation user sdagley
# https://community.jamf.com/t5/jamf-pro/add-a-system-to-a-smartgroup-using-self-service/m-p/238671
#
# This script is intended to be used as a script in a Jamf Pro Policy. It will create a
# flag file on a Mac that can be read by an EA script which in turn can
# be used as a Smart Group Criteria. This was created to allow Self Service initiated
# scoping of Configuration Profile deployments.
#
# $4 - Path of directory to save Flag File in (will be created if needed)
# $5 - Name of Flag File to create

FlagFilePath="$4"
FlagFileName="$5"

if [ -z "${FlagFilePath}" ] || [ -z "${FlagFileName}" ]; then
    echo "Both the path to the flag file and the flag file name must be provided"
    exit 1
fi

if [ ! -d "${FlagFilePath}" ]; then
    /bin/mkdir "${FlagFilePath}"
fi

/usr/bin/touch "${FlagFilePath}${FlagFileName}"

/usr/local/bin/jamf recon

exit 0
