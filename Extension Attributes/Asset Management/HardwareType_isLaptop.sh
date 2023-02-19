#!/bin/bash
#
# Script tested as working in bash + zsh
####################################################################
# HardwareType_isLaptop
# v1.1
#
# Extension attribute to identify if a system is a laptop or desktop by detecting the presence of a battery.
# Value will be "Yes" if system is a laptop or "No" if the system is a desktop. 
#
# Greg Knackstedt
# https://github.com/scriptsandthings/
# Shitttyscripts@gmail.com
# 2.18.2023
#
####################################################################
#
# Check if system has an internal battery
isLaptop=$(/usr/sbin/ioreg -c AppleSmartBattery -r | awk '/BatteryInstalled/ {print $3}')
#
# If system is a laptop, set result to Yes
if [[ $isLaptop == "Yes" ]]; then
	echo "System is a laptop"
 	result="Yes"
else
# Else system is a desktop, set result to No
	echo "System is a desktop"
	result="No"
fi
# Echo the result for collection
/bin/echo "<result>$result</result>"
