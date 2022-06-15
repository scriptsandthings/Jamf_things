#!/bin/bash
#
#############################
#############################
#
# macOS Monterey 12.4 - Self Service policy - Before script - Disk Space notification - v1.sh
#
# Greg Knackstedt
# shitttyscripts@gmail.com
# 6.15.2022
#
# Script to use notify users that macOS Monterey 12.4 will require 45GB of free space on Macintosh HD prior to starting the update install.
# Add to your Self Service macOS Monterey installation policy with a priority of 'Before".
#
#############################
#############################
loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }} ')
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
windowType="hud"
description="IMPORTANT: The macOS Monterey 12.4 update requires 45GB of free space on Macintosh HD to complete installation. 

To continue installing the update now, select 'Install macOS' below and the macOS Monterey 12.4 update will begin installation shortly. This update can take upwards of 35-45 minutes to complete. If you are unable to perform this update at this time or do not currently have 45GB of avaliable disk space, please select 'Cancel' to be prompted again later. 

If you attempt to run the macOS Monterey 12.4 update and encounter any issues such as the policy showing 'Complete' but the installer failing to launch, double check your avaliable free space on Macintosh HD and attempt the update again using a wired network connection.

If you require assistance, please contact corporate IT support by phone at 1-555-555-5555 or by email at support@email.address.

*Please quit out of open applications and save all working documents before selecting 'Install macOS'."

button1="Install macOS"
button2="Cancel"
icon="/Library/Application Support/branding_assets/AppIcons/VSandCO/black_background/install.png"
title="Important: macOS Monterey 12.4 requires 45GB free space"
alignDescription="left" 
alignHeading="center"
defaultButton="2"
timeout="900"

# JAMF Helper window as it appears for targeted computers
userChoice=$("$jamfHelper" -windowType "$windowType" -lockHUD -title "$title" -timeout "$timeout" -defaultButton "$defaultButton" -icon "$icon" -description "$description" -alignDescription "$alignDescription" -alignHeading "$alignHeading" -button1 "$button1" -button2 "$button2")

# If user selects "UPDATE"
if [ "$userChoice" == "0" ]; then
   echo "User clicked Install macOS; now downloading and installing updates."
   # Install ALL available software and security updates
# If user selects "Cancel"
elif [ "$userChoice" == "2" ]; then
   echo "User clicked Cancel or timeout was reached; now exiting."
   exit 0    
fi
exit 0
