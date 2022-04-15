# Suggestions for patch management

## 1. Build payloadless packages (.pkg files) containing Installomator as patch definitions

Build payloadless packages (.pkg files) containing Installomator, with a static defined tag and install variables for individual applications. 
These payloadless packages can easily be created with Jamf Composer by adding a Post-Install script to a package then removing the dummy file from the package. There are multiple other methods or tools to accomplish this.

This is a great article on Der Flounder by RTrouton to get you started with payloadless packages:

https://derflounder.wordpress.com/2014/06/01/understanding-payload-free-packages/

These paylodless packages based on Installomator can then be used as patch managment definitions with Jamf Pro for your applications on an ongoing basis without the need to repackage.

## 2. Jamf Pro will only use your primary DP if you're on-premise (this is key for a primary-remote fleet)

Jamf Pro will only use your primary DP if you're on-premise. This is important to note, as there is currently no way to set a different primary, or specify a failover DP for patch managment. If your primary DP is only accessible while on your network, Jamf Pro will log multiple failed attempts when trying to patch your applications. This will drag down your mySQL database performance and cause Jamf Pro to become unresponsive on a daily basis at about the same times each day. It is based on this that I reccomend to NOT use patch management as your primary method of patching unless you have an external hosted primary DP on a 3rd party CDN or are hosted on Jamf Pro Cloud.
