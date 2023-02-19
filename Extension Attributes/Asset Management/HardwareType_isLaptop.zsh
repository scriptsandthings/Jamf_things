#!/bin/zsh
#
####################################################################
# HardwareType_isLaptop.zsh
#
# Extension attribute to identify if a system is a laptop or desktop by detecting the presence of a battery.
# Value will be "Yes" if system is a laptop or "No" if the system is a desktop. 
#
# Greg Knackstedt
# https://github.com/scriptsandthings/
# Shitttyscripts@gmail.com
#
####################################################################
#
# Check if system has an internal battery
isLaptop=$(/usr/sbin/ioreg -c AppleSmartBattery -r | awk '/BatteryInstalled/ {print $3}')
#
# Set result value
/bin/echo "<result>$isLaptop</result>"
