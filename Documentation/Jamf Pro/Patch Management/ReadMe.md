# Suggestions for patch management

## 1. Build payloadless packages (.pkg files) containing Installomator as patch definitions

Build payloadless packages (.pkg files) containing Installomator, with a static defined tag and install variables for individual applications. 
These payloadless packages can easily be created with Jamf Composer by adding a Post-Install script to a package then removing the dummy file from the package. There are multiple other methods or tools to accomplish this.

This is a great article on Der Flounder by RTrouton to get you started with payloadless packages:

https://derflounder.wordpress.com/2014/06/01/understanding-payload-free-packages/

These paylodless packages based on Installomator can then be used as patch managment definitions with Jamf Pro for your applications on an ongoing basis without the need to repackage.
