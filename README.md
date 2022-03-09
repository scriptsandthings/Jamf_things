# Jamf Things
Stuff I've created for use within Jamf Pro to make my life, the lives of our users, and the lives of our support staff a little easier. (Mostly to make my life easier though if we're being real here).

I'm just starting using GitHub to save some of my work in case I need to reference in the future, and to share the things I've found helpful with others since I've benifited from so many other people's GitHub pages and projects over the years; so the orginization and stuff here isn't great yet and probably won't be for a while..... I rather add a bunch of useful things so I don't forget to save them somewhere and lose them eventually, then spend time messing with markup language trying to make this README.me look good right now. (Insert that "Damn bitch, you live like this?" meme with Goofy in it)

## Scripts (Bash directory)
Script for migrating between JSSs when NAC is a pain so you use a 3rd wifi network.

Scripts for add/remove a computer to/from a static group by group ID by values defined in the Jamf script paramiters, using the Jamf API and bearer token authentication

Scripts to allow support associates add or remove a Mac from a static group via a Self Service policy which will prompt for the target Mac's serial, without the need for Jamf admin access. Uses the Jamf API and bearer token auth.

Script to check if a process is running by name, and keep sending killall to it until it isn't.

Script to uninstall Crowdstrike Falcon using Self Service to display a prompt for the system's maintnance token.

Script that can be used as an Extension Attribue in Jamf to tag a system's current physical location (City, State/Region) using the system's xurrent external facing IP address.


Default apps thing I don't think works. Needs to be run under the current user context. Could just take it and set the variables as hard coded values and then call it with jamf to accomplish the task most likely. More testing needed.


## Extension Attributes
One script that can be used as EAs for displaying the approximate "City,State" or "Locality,Region" a device appears to be located inusing it's current external IP address.
Two additional scripts/EAs that display either the City/Locality OR the State/Region a device appears to be located in using it's current external IP address
#### Note, if you're on VPN when running these and it's not a split-tunnel connection, there is a likely chance your location information will be returned based on the geographical location the endpoint for your VPN connection is located in.

Script to check if ProofPoint ObserveIT is installed, and report back the version if it is.

## JSON Schemas
com.vmware.horizon JSON schema for configuring VMWare Horizon Client preferences within the Jamf Pro GUI
