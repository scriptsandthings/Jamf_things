# Jamf Pro Zero Touch/PreStage Enrollment
#### [Jamf Documentation for Jamf Pro 10.40.0](https://docs.jamf.com/10.40.0/jamf-pro/documentation/Computer_PreStage_Enrollments.html)

### Basic foundation for a true zero-touch deployment of macOS from Jamf Pro
1. Unprotected/auth free external facing HTTP/HTTPS file share to host pre-stage enrollment packages (Jamf Cloud DP works)
2. Signing Certificate - ([DeveloperID Installer Cert from Apple](https://docs.jamf.com/technical-articles/Obtaining_an_Installer_Certificate_from_Apple.html) AND [Apple Trusted Root Certificates](https://support.apple.com/en-us/HT209143) or [Self Signed Signing Cert from Jamf Pro](https://docs.jamf.com/technical-articles/Creating_a_Signing_Certificate_Using_Jamf_Pros_Built-in_CA_to_Use_for_Signing_Configuration_Profiles_and_Packages.html)) all PreStage Enrollment packages must be signed with a cert trusted by the client at time of install
3. Package manifest file - ([Example and utility here](https://github.com/scriptsandthings/Jamf_things/tree/master/Documentation/Jamf%20Pro/Zero%20Touch%20Deployment/Manifest%20Files)) - created for each PreStage Enrollment package 
- *For Jamf Cloud: Upload package via Jamf Web GUI Settings>Packages to bypass manifest requirement*
4. [Enrollment Customization](https://docs.jamf.com/10.40.0/jamf-pro/documentation/Enrollment_Customization_Settings.html#ID-0000a9bc) (optional but reccomended to suggest a wired network connection to users)
5. [Pre-Stage Enrollment](https://docs.jamf.com/10.40.0/jamf-pro/documentation/Computer_PreStage_Enrollments.html) configuration
6. Jamf Connect Login (depending on IdP, may be optional)
7. [DEPNotify](https://gitlab.com/Mactroll/DEPNotify)
8. Jamf's [DEPNotify Starter Script](https://github.com/jamf/DEPNotify-Starter)
9. Optional/Environment dependent: FileVault
10. Optional/Environment dependent: [macOSLAPS](https://github.com/joshua-d-miller/macOSLAPS)
