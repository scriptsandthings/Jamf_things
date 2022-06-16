#!/bin/bash
#
# Fix_Jamf_recon_Stuck_at_App_Store_and_Gatekeeper_Status_v1.sh
# relaunches com.apple.softwareupdated daemon which can cause Jamf recon to hang
#
#####################################
#
# Greg Knackstedt
# shitttyscripts@gmail.com
# 06.16.2022
#
#####################################
#
sudo launchctl kickstart -k system/com.apple.softwareupdated
#
exit 0
