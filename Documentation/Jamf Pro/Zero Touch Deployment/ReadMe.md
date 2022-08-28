
### Basic foundation for a true zero-touch deployment of macOS from Jamf Pro
1. Unprotected/auth free HTTP file share to host pre-stage enrollment packages (Jamf Cloud DP works)
2. Signing Certificate (DeveloperID Installer Cert from Apple or Self Signed Signing Cert from Jamf Pro)
3. Package manifest file created for each pre-stage package
4. Enrollment Customization (optional but reccomended to suggest a wired network connection to users)
5. Pre-Stage Enrollment configuration
6. Jamf Connect Login (depending on IdP, may be optional)
7. DEPNotify
8. Jamf DEPNotify Starter Script
9. Optional/Environment dependent: FileVault
10. Optional/Environment dependent: macOSLAPS
