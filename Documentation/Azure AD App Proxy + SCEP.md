https://macnotes.wordpress.com/2020/11/11/configuring-azure-web-application-proxy-for-jamf-pro-scep-certificates/

Don't try to load balance, you'll get rate limit/bad/max password attempt issues and fight it forever.
Just do an active/passive failover, kinda lame but gives some DR and functions.
