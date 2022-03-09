#!/bin/zsh
#
ScriptName="Display_Network_Info_With_Self_Service"
#
#
# NOTE: This script can only be executed on systems running macOS Monterey (and presumably versions after Monterey).
# Previous versions of macOS do not include the "networkQuality" binary, which will cause the script to spit back an error.
#
#
# This script displays an AppleScript dialog showing the IP addresses of the
# default Ethernet and Airport interfaces (by just showing the first couple enX addresses), 
# as well as IP addresses for Cisco AnyConnect and Palo Alto GlobalProtect VPN.
# Script also runs the "networkQuality" command to test upload/download speeds,
# displaying the results via an AppleScript dialog.
#
# The output isn't beautiful or anything, but it's nice information to have.
#
# v1.0
# 3.8.2022
#
# Greg Knackstedt
# https://github.com/gknackstedt/
# shitttyscripts@gmail.com
#
Timestamp=$(date)

CurrentConsoleUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')

GP_IP=$(ifconfig | grep -e "-->" | sed 's/\|/ /'|awk '{print $2}')

OSInfo=$(sw_vers)

HardwareInfo=$(/usr/sbin/system_profiler SPHardwareDataType)

SN=`system_profiler SPHardwareDataType | awk '/Serial/ {print $4}' 2>&1`

en0=`ipconfig getifaddr en0 2>&1`

en1=`ipconfig getifaddr en1 2>&1`

en2=`ipconfig getifaddr en2 2>&1`

en3=`ipconfig getifaddr en3 2>&1`

en4=`ipconfig getifaddr en4 2>&1`

VPN=$(/sbin/ifconfig "utun0" 2>/dev/null | \
/usr/bin/sed -n -e 's|^[[:space:]]*inet \([0-9.]*\).*|\1|p' 2>&1)

VPN1=$(/sbin/ifconfig "utun1" 2>/dev/null | \
/usr/bin/sed -n -e 's|^[[:space:]]*inet \([0-9.]*\).*|\1|p' 2>&1)

VPN2=$(/sbin/ifconfig "utun2" 2>/dev/null | \
/usr/bin/sed -n -e 's|^[[:space:]]*inet \([0-9.]*\).*|\1|p' 2>&1)

GPD=$(/sbin/ifconfig "gpd0" 2>/dev/null | \
/usr/bin/sed -n -e 's|^[[:space:]]*inet \([0-9.]*\).*|\1|p' 2>&1)

GPD1=$(/sbin/ifconfig "gpd1" 2>/dev/null | \
/usr/bin/sed -n -e 's|^[[:space:]]*inet \([0-9.]*\).*|\1|p' 2>&1)

if [ "$en0" = "get if addr en0 failed, (os/kern) failure" ]; then

en0="en0 unavailable"

fi

if [ "$en1" = "get if addr en1 failed, (os/kern) failure" ]; then

en1="en1 unavailable"

fi

if [ "$en2" = "get if addr en2 failed, (os/kern) failure" ]; then

en2="en2 unavailable"

fi

if [ "$en3" = "get if addr en3 failed, (os/kern) failure" ]; then

en3="en3 unavailable"

fi

if [ "$en4" = "get if addr en4 failed, (os/kern) failure" ]; then

en4="en4 unavailable"

fi

/usr/bin/osascript << EOF
set testResults to do shell script "networkQuality -v"

tell application "Finder"

activate

display dialog "------- $ScriptName -------" & return & return & "Test ran on: $Timestamp" & return & return & "Serial Number: $SN" & return & "Current User: $CurrentConsoleUser" & return & return & "Network Speed Test Results:" & testResults & return & return & "Wifi and Ethernet IP Addresses:" & return & "$en0" & return & "$en1" & return & "$en2" & return & "$en3" & return & "$en4" & return & return & "GlobalProtect VPN IP Address:" & return & "$GP_IP" & return & "$GPD" & return & "$GPD1" & return & return & "Cisco AnyConnect VPN IP Address:" & return &"$VPN" & return & "$VPN1" & return & "$VPN2" buttons {"OK"} with icon caution

end tell

EOF


exit 0
