# Suggestions for patch management

## 1. Build payload-less packages (.pkg files) containing Installomator as patch definitions

Build payload-less packages (.pkg files) containing [Installomator](https://github.com/Installomator/Installomator) (the script only), with a static defined tag and install variables for individual applications. 
These payload-less packages can easily be created with Jamf Composer by adding a Post-Install script to a package then removing the dummy file from the package. Paste the contents of the Installomator script into the Post-Install and modify for your requirements. There are multiple other methods or tools to accomplish this as well.

This is a great article on Der Flounder by rtrouton to get you started with payloadless packages:

https://derflounder.wordpress.com/2014/06/01/understanding-payload-free-packages/

These payload-less packages based on Installomator can then be used as patch management definitions with Jamf Pro for your applications on an ongoing basis without the need to repackage.

## 2. Jamf Pro will only use your primary DP if you're on-premise (this is key for a primary-remote fleet)

Jamf Pro will only use your primary DP if you're on-premise. This is important to note, as there is currently no way to set a different primary, or specify a failover DP for patch management. If your primary DP is only accessible while on your network, Jamf Pro will log multiple failed attempts when trying to patch your applications. This will drag down your mySQL database performance and cause Jamf Pro to become unresponsive on a daily basis at about the same times each day. It is based on this that I recommend to NOT use patch management as your primary method of patching unless you have an external hosted primary DP on a 3rd party CDN or are hosted on Jamf Pro Cloud.
