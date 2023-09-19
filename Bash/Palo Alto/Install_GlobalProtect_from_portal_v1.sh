#!/bin/bash
#
vpnPortal="vpn-portal.domain.com"
# Download the GlobalProtect.pkg from the VPN portal
curl -o /tmp/GlobalProtect.pkg "https://$vpnPortal/global-protect/msi/GlobalProtect.pkg"
#
# Run the downloaded .pkg installer
sudo installer -allowUntrusted -pkg /tmp/GlobalProtect.pkg -target /
#
# Remove the downloaded installer from the /tmp/directory
rm -f /tmp/GlobalProtect.pkg
#
# Exit
exit 0
