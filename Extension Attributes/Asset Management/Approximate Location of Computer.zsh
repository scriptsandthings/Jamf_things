#!/bin/zsh
# Gets the system's approximate physical location by using its current external facing IP
# Displays the City, State, and Country info returned from ip-api.com.
#
# v2.0
# 3.28.2023
#
# Greg Knackstedt
# https://github.com/scriptsandthings/
# Shitttyscripts@gmail.com
#
####################################
#
# Get the current external IP address
myIP=$(curl -L -s --max-time 10 http://checkip.dyndns.org | egrep -o -m 1 '([[:digit:]]{1,3}.){3}[[:digit:]]{1,3}')
# Use the IP address to identify the current City
City=$(curl -L -s --max-time 10 "http://ip-api.com/line/$myIP?fields=city")
# Use the IP address to identify the current State or Region
State=$(curl -L -s --max-time 10 "http://ip-api.com/line/$myIP?fields=regionName")
# Use the IP address to identify the current Country
Country=$(curl -L -s --max-time 10 "http://ip-api.com/line/$myIP?fields=country")
#
# Display the results in a format that can be used as an extension attribute
echo "<result>$City, $State - $Country</result>"
exit 0
