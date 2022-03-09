#!/bin/bash
#
# Create a symbolic link to a file defined in Jamf script prarams
#
# Greg Knackstedt
# 1.12.2022
# shitttyscripts@gmail.com
#
CurrentUser=$3
# old hardcoded target from Box drive
# Target="/Users/$CurrentUser/Library/CloudStorage/Box-Box"
Target="$4"
#
#
Destination="$5"
#
TimeStamp=$(date +%Y-%m-%d_%H-%M-%S)
#
########################################
function CheckForExistingBox
	{
		if [ -e "$Destination" ] 
			then
				echo "##################################"
				echo ""
  			  	echo "$Destination already exists."
 	    	   	echo "Renaming as Box Backup $TimeStamp" 
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
CheckForExistingBox
CreateSymlink

exit 0
