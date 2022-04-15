#!/bin/zsh
########################################################
#
# Script to use swda to set default applications for UTIs
# as defined by Jamf parameters
# 
# Note: I don't think this works, as it must be run under the local user context. Saving to be repositioned at a later date.
#
# swda_jamf_params.sh
# 1.0
# 2.13.2022
# Greg Knackstedt
# shitttyscripts@gmail.com
#
########################################################
#
# swda binary location
swdaBinary="/usr/local/bin/swda"
# find current console user
CurrentConsoleUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
#
########################################################
#
# Define application to set as default
AppPath1="$4"
#
# Set handler switch
handlerSwitch="$5"
#
# Define App UTIs to assign to the application specified
AppUTI1="$6"
AppUTI2="$7"
AppUTI3="$8"
AppUTI4="$9"
AppUTI5="$10"
AppUTI6="$11"
#
########################################################
# 
# Exit function
#
function NotifyScriptComplete
	{
	echo "##########################"
	echo ""
	echo "Defaults set for $AppPath1"
	echo ""
	echo "##########################"
	exit 0
	}
#
########################################################
#
# Set UTIs based on entered parameters in Jamf Pro
#
if [ "$handlerSwitch" = "UTI" ]
	then
		echo "##########################"
		echo ""
		echo "Setting $AppPath1 as default for $AppUTI1"
		echo ""
		echo "##########################"
		$swdaBinary setHandler --app $AppPath1 --UTI $AppUTI1
		if [ $AppUTI2 != "" ]
			then
				echo "##########################"
				echo ""
				echo "Setting $AppPath1 as default for $AppUTI2"
				echo ""
				echo "##########################"
				$swdaBinary setHandler --app $AppPath1 --UTI $AppUTI2
				if [ $AppUTI3 != "" ]
					then
						echo "##########################"
						echo ""
						echo "Setting $AppPath1 as default for $AppUTI3"
						echo ""
						echo "##########################"
						$swdaBinary setHandler --app $AppPath1 --UTI $AppUTI3
						if [ $AppUTI4 != "" ]
							then
								echo "##########################"
								echo ""
								echo "Setting $AppPath1 as default for $AppUTI4"
								echo ""
								echo "##########################"
								$swdaBinary setHandler --app $AppPath1 --UTI $AppUTI4
								if [ $AppUTI5 != "" ]
									then
										echo "##########################"
										echo ""
										echo "Setting $AppPath1 as default for $AppUTI5"
										echo ""
										echo "##########################"
										$swdaBinary setHandler --app $AppPath1 --UTI $AppUTI5
										if [ $AppUTI6 != "" ]
											then
												echo "##########################"
												echo ""
												echo "Setting $AppPath1 as default for $AppUTI6"
												echo ""
												echo "##########################"
												$swdaBinary setHandler --app $AppPath1 --UTI $AppUTI6
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
	if [ "$handlerSwitch" != "UTI" ]
		then
			echo "##########################"
			echo ""
			echo "Setting $AppPath1 as default for $handlerSwitch"
			echo ""
			echo "##########################"
			$swdaBinary setHandler --app $AppPath1 --$handlerSwitch
			echo ""
			echo "##########################"
			NotifyScriptComplete
	fi
	echo "##########################"
	echo ""
	echo "No app UTIs were entered for $AppPath1"
	echo "No changes made."
	echo ""
	echo "##########################"
	exit 0
fi
exit 0
