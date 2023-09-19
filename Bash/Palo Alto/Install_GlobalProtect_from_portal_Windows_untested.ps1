###############################################################################
###############################################################################
# Install GlobalProtect VPN Client - Windows.ps1
###############################################################################
# v1.0a
# 9.18.2023
# Greg Knackstedt
# shitttyscripts@gmail.com
# https://github.com/shitttyscripts/
###############################################################################
#
# This script leverages PowerShell to automate the installation of the Palo Alto GlobalProtect VPN client on Windows.
#
# The script will download the GlobalProtect MSI installer from a given VPN portal.
# The portal can be either manually set via Intune or Microsoft Endpoint Manager script variables
# or automatically detected from the existing GlobalProtect configuration in the Windows Registry.
#
# The installer is then run to install the GlobalProtect client.
# Finally, the downloaded installer is removed to clean up.
#
# This script is intended to be deployed via Microsoft Intune and expects the VPN portal address to be
# provided via custom script parameters or variables within Intune.
#
# If the VPN portal address is not provided, the script will look in the Windows Registry to try
# to determine the current portal address.
#
###############################################################################
# Intune Script Parameters:
# TODO: Define any custom parameters or variables to be used within Intune, if applicable.
#
# Note: The VPN portal address will be automatically detected if not provided.
#
###############################################################################
###############################################################################
################################# Script Body #################################
###############################################################################

# Set default VPN portal, replace with Intune parameter if available.
$vpnPortal = "default-portal-address"

# TODO: Replace this with fetching the VPN portal from Intune parameters, if applicable.
# e.g., $vpnPortal = $Env:vpnPortalFromIntune

# Check if the registry entry exists for GlobalProtect portal
if (Test-Path "HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect\PanSetup") {
    $regPortal = Get-ItemProperty -Path "HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect\PanSetup" -Name "PanPortalList" -ErrorAction SilentlyContinue
    if ($null -ne $regPortal.PanPortalList) {
        $vpnPortal = $regPortal.PanPortalList
    }
}

# Download the GlobalProtect.msi from the VPN portal
Invoke-WebRequest -Uri "https://$vpnPortal/global-protect/msi/GlobalProtect.msi" -OutFile "$env:TEMP\GlobalProtect.msi"

# Install GlobalProtect
Start-Process "msiexec.exe" -ArgumentList "/i $env:TEMP\GlobalProtect.msi /quiet" -Wait

# Remove the downloaded installer
Remove-Item -Path "$env:TEMP\GlobalProtect.msi" -Force
