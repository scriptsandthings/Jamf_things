#!/bin/bash
#
# SMB_Share_Stats_Display.sh
#
# Displays current smb mountpoint stats using AppleScript
#
# v1.0
# 3.8.2022
#
# The output isn't beautiful or anything, but it's nice information to have.
#
# Greg Knackstedt
# https://github.com/gknackstedt/
# shitttyscripts@gmail.com
#
#
ShowSMBStatus=$(smbutil statshares -a)
Timestamp=$(date)

/usr/bin/osascript << EOF

tell application "Finder"

activate

display dialog "SMB share status for $USER at $Timestamp" & return & return & "NOTE: If formatting is difficult to read, copy/paste results into a text editor." & return & return & "$ShowSMBStatus" buttons {"================================================= Dismiss ================================================="} with icon caution

end tell

EOF


exit 0
