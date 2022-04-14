#!/bin/zsh
#######################
# 
# To pair with script to create flag file.
#
#######################
#
# Originally from Jamf Nation user sdagley
# https://community.jamf.com/t5/jamf-pro/add-a-system-to-a-smartgroup-using-self-service/m-p/238671
#
# EA - Template Check For Flag File.sh
#
# One strategy for enabling a Jamf Pro Policy or Configuration Profile is using a Smart Group
# to identify Macs that the Policy or Profile should be deployed to. Some criteria is
# needed to identify a Mac as a member of the target Smart Group. This EA template is a
# mechanism for doing that. If a file exists with the specified name at the specified path
# it will return True, otherwise it returns False. 

FlagFilePath="/Library/SomeOrg/"
FlagFileName="flagfile"
result="False"

if [ -e "${FlagFilePath}${FlagFileName}" ]; then
    result="True"
fi

echo "<result>$result</result>"
