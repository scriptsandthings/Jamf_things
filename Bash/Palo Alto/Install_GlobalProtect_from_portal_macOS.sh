#!/bin/bash
###############################################################################
###############################################################################
# Install GlobalProtect VPN Client - macOS.sh
###############################################################################
# v1.0
# 9.18.2023
# Greg Knackstedt
# shitttyscripts@gmail.com
# https://github.com/shitttyscripts/
###############################################################################
#
# This script leverages bash to automate the installation of the Palo Alto GlobalProtect VPN client on macOS.
#
# The script will download the GlobalProtect installer package from a given VPN portal.
# The portal can be either manually set via Jamf Pro script variables or automatically detected
# from the existing GlobalProtect configuration plist.
#
# The installer package is then run to install the GlobalProtect client.
# Finally, the downloaded installer package is removed to clean up.
#
# The script is intended to be deployed via Jamf Pro and expects the VPN portal address to be
# provided via the $4 script parameter in the Jamf Pro admin interface.
#
# If the VPN portal address is not provided, the script will look in the GlobalProtect configuration plist
# to try to determine the current portal address. The plist is checked in both system-wide and user-specific
# library folders.
#
###############################################################################
# Jamf Pro Script Parameters:
# $4 - VPN Portal Address (optional): The address of the VPN portal, e.g., "vpn-portal.domain.org".
#
# Note: The VPN portal address will be automatically detected if not provided.
#
###############################################################################
###############################################################################
################################# Script Body #################################
###############################################################################

# Check if $4 is set and use it as vpnPortal
if [[ -n "$4" ]]; then
    vpnPortal="$4"
else
    # Try to read system-wide plist first
    plistPath="/Library/Preferences/com.paloaltonetworks.GlobalProtect.plist"
    if [[ -f $plistPath ]]; then
        vpnPortal=$( /usr/libexec/PlistBuddy -c "Print :PanPortalList:0" $plistPath 2>/dev/null )
    else
        # Fall back to the current user's home directory
        plistPath="$HOME/Library/Preferences/com.paloaltonetworks.GlobalProtect.plist"
        if [[ -f $plistPath ]]; then
            vpnPortal=$( /usr/libexec/PlistBuddy -c "Print :PanPortalList:0" $plistPath 2>/dev/null )
        fi
    fi
    
    # Check if vpnPortal is still empty or null
    if [[ -z "$vpnPortal" ]]; then
        echo "Error: No VPN portal address found in plist or in \$4."
        exit 1
    fi
fi

# Download the GlobalProtect.pkg from the VPN portal
curl -o /tmp/GlobalProtect.pkg "https://$vpnPortal/global-protect/msi/GlobalProtect.pkg"

# Run the downloaded .pkg installer
sudo installer -allowUntrusted -pkg /tmp/GlobalProtect.pkg -target /

# Remove the downloaded installer from the /tmp/ directory
rm -f /tmp/GlobalProtect.pkg

# Exit
exit 0
