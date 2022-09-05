#!/bin/zsh
########################################################
#
#
# Jamf - Call Other Policies By Trigger.sh
# v2.0
# 9.3.2022
# Greg Knackstedt
# shitttyscripts@gmail.com
# https://github.com/scriptsandthings
#
########################################################
#
# swda binary location
jamfBinary="/usr/local/jamf/bin/jamf"
# find current console user
CurrentConsoleUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
#
########################################################
#
# Define command to run against jamf binary
jamfCommand="$4"
#
# Define trigger for commands
jamfTrigger="$5"
#
# Define policy custom triggers to run
jamfEvent6="$6"
jamfEvent7="$7"
jamfEvent8="$8"
jamfEvent9="$9"
jamfEvent10="${10}"
jamfEvent11="${11}"
#
########################################################
# 
# Exit function
#
function NotifyScriptComplete
	{
	echo "##########################"
	echo ""
    echo "Jamf Policies Completed"
    echo "See Individual Policy Logs For Details."
	echo "The following Policies Were Called:"
	echo "$jamfEvent6"
	echo "$jamfEvent7"
	echo "$jamfEvent8"
	echo "$jamfEvent9"
	echo "$jamfEvent10"
	echo "$jamfEvent11"
	echo ""
	echo "##########################"
	exit 0
	}
#
########################################################
#
# Set UTIs based on entered parameters in Jamf Pro
#

if [ "$jamfCommand" = "policy" ]
	then
		echo "##########################"
		echo ""
		echo "Running jamf $jamfCommand $jamfTrigger $jamfEvent6"
		echo ""
		echo "##########################"
		$jamfBinary "$jamfCommand" "$jamfTrigger" "$jamfEvent6"
    	        sleep 10
		if [ -n "$jamfEvent7" ]
			then
				echo "##########################"
				echo ""
				echo "Running jamf $jamfCommand $jamfTrigger $jamfEvent7"
				echo ""
				echo "##########################"
				$jamfBinary "$jamfCommand" "$jamfTrigger" "$jamfEvent7"
         		        sleep 10
				if [ -n "$jamfEvent8" ]
					then
						echo "##########################"
						echo ""
						echo "Running jamf $jamfCommand $jamfTrigger $jamfEvent8"
						echo ""
						echo "##########################"
						$jamfBinary "$jamfCommand" "$jamfTrigger" "$jamfEvent8"
              			                sleep 10
						if [ -n "$jamfEvent" ]
							then
								echo "##########################"
								echo ""
								echo "Running jamf $jamfCommand $jamfTrigger $jamfEvent9"
								echo ""
								echo "##########################"
								$jamfBinary "$jamfCommand" "$jamfTrigger" "$jamfEvent9"
                         				        sleep 10
								if [ -n "$jamfEvent10" ]
									then
										echo "##########################"
										echo ""
										echo "Running jamf $jamfCommand $jamfTrigger $jamfEvent10"
										echo ""
										echo "##########################"
										$jamfBinary "$jamfCommand" "$jamfTrigger" "$jamfEvent10"
                                   					        sleep 10
										if [ -n "$jamfEvent11" ]
											then
												echo "##########################"
												echo ""
												echo "Running jamf $jamfCommand $jamfTrigger $jamfEvent11"
												echo ""
												echo "##########################"
												$jamfBinary "$jamfCommand" "$jamfTrigger" "$jamfEvent11"
                                           						        sleep 10
												NotifyScriptComplete
											else
												NotifyScriptComplete
										fi
									else
										NotifyScriptComplete
								fi			
							else
								NotifyScriptComplete
						fi		
					else
						NotifyScriptComplete
				fi
			else
				NotifyScriptComplete
		fi
	else
	if [ "$jamfcommand" != "policy" ]
		then
			echo "##########################"
			echo ""
			echo "Running jamf $jamfCommand $jamfTrigger"
			echo ""
			echo "##########################"
			$jamfBinary "$jamfCommand" "$jamfTrigger" "$jamfEvent6"
         	        sleep 10
			echo ""
			echo "##########################"
			echo ""
			echo "Completed $jamfCommand $jamfTrigger"
			echo ""
			echo "##########################"
            exit 0
	fi
	echo "##########################"
	echo ""
	echo "No commands were entered for jamf to run"
	echo "No changes made."
	echo ""
	echo "##########################"
	exit 1
fi
