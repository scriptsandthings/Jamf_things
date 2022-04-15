#!/bin/zsh
#
# Jamf_Kill_Running_Process.zsh
# v1.0
# 3.1.2022
# Greg Knackstedt
# shitttyscripts@gmail.com
#
###########################################
# Script to check if a process is running, 
# and if found send the "killall" command 
# until the process is no longer running.
# Uses Jamf script param 4 to define the process name.
#############################################
# define the target process
killMe="$4"
#
echo "#########################"
echo "#########################"
echo "Checking if the process $killMe is running"
echo "#########################"
echo "#########################"
#
# Check if the process is running
if pgrep $killMe; then
    echo "#########################"
    echo "Found process $killMe running on system..."
	echo "#########################"
    # While the process is running, do a loop to shut it down
    while pgrep $killMe;
    	do
        	echo "#########################"
			echo "#########################"
			echo "Closing $killMe...."
			echo "#########################"
            # send kill command to process name
   			killall "$killMe"
  			sleep 1
		done

fi
echo "#########################"
echo "#########################"
echo "The process $killMe is not running."
echo "#########################"
echo "#########################"
