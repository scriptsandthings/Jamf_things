#!/bin/bash
#
# Create a symbolic link to a file defined in Jamf script prarams
#
# Greg Knackstedt
# 1.12.2022
# shitttyscripts@gmail.com
#
CurrentUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
Target="$4"
Destination="$5"
TimeStamp=$(date +%Y-%m-%d_%H-%M-%S)
#
#########################################
# Make sure we're not replacing a directory or existing file with a symlink...
function CheckForExisting
	{
		if [ -e "$Destination" ] 
			then
				echo "##################################"
				echo ""
  			  	echo "$Destination already exists."
 	    	   	echo "Renaming as $Destination\ Backup\ $TimeStamp" 
				mv "$Destination" "$Destination"\ Backup\ "$TimeStamp"
			else
				echo "##################################"
				echo ""
 			   	echo "$Destination does not exist."
		fi
	}
	
function CreateSymlink
	{
		echo ""
		echo "##################################"
		echo "### Creating Symbolic Link ###"
		echo "##################################"
		echo ""
		echo "##################################"
		echo "Target directory: $Target"
		echo "##################################"
		echo ""
		echo "##################################"
		echo "Destination: $Destination"
		echo ""
		echo "##################################"
		ln -s "$Target" "$Destination"
		echo "Symbolic link created"
		echo "##################################"
	}
#
#
#####################################
CheckForExisting
CreateSymlink

exit 0
