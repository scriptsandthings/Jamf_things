# ShitttyJamf
Jamf things

#### Scripts
Script for migrating between JSSs when NAC is a pain so you use a 3rd wifi network.

Scripts for add/remove a computer to/from a static group by group ID by values defined in the Jamf script paramiters, using the Jamf API and bearer token authentication

Scripts to allow support associates add or remove a Mac from a static group via a Self Service policy which will prompt for the target Mac's serial, without the need for Jamf admin access. Uses the Jamf API and bearer token auth.

Script to check if a process is running by name, and keep sending killall to it until it isn't.

Script to uninstall Crowdstrike Falcon using Self Service to display a prompt for the system's maintnance token.

Script that can be used as an Extension Attribue in Jamf to tag a system's current physical location (City, State/Region) using the system's xurrent external facing IP address.


Default apps thing I don't think works. Needs to be run under the current user context. Could just take it and set the variables as hard coded values and then call it with jamf to accomplish the task most likely. More testing needed.


#### Extension Attributes
One script that can be used as EAs for displaying the approximate "City,State" or "Locality,Region" a device appears to be located inusing it's current external IP address.
Two additional scripts/EAs that display either the City/Locality OR the State/Region a device appears to be located in using it's current external IP address
### Note, if you're on VPN when running these and it's not a split-tunnel connection, there is a likely chance your location information will be returned based on the geographical location the endpoint for your VPN connection is located in.
