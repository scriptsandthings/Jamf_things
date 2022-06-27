# SCEP With Azure App Proxy + Jamf Pro

## Handy guide to get started:
https://macnotes.wordpress.com/2020/11/11/configuring-azure-web-application-proxy-for-jamf-pro-scep-certificates/

## Some additional notes:
1. Intune requires it's own NDES/SCEP server. You can't use the same server for both.
2. Don't try to load balance, you'll get rate limit/bad/max password attempt issues and fight it months.
#### Just do an active/passive failover, kinda lame but gives some DR and functions. **Literally spent 6 months with Microsoft and Jamf support on this.**
