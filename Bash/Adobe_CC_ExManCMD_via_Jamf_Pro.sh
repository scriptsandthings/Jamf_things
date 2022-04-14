#!/bin/bash
#
#############################
#############################
#
# Greg Knackstedt
# 5.13.2021
#
# Script to use ExManCMD to install ZXP plugins for Adobe CC via Jamf Pro
#
#############################
#############################
#
# Variables
#
# Full path to directory containing ZXP file to install
ZXPDirectory="$4"
# ZXP File name
ZXPToInstall="$5"
# Full path to directory containing ExManCMD
exManDirectory="$6"
# Full path to ExManCMD
exManPath="$7"
#
#############################
#############################
#
# Script
#
# Change permissions on pre-staged installation files
chmod -Rf 777 "$ZXPDirectory"
chmod -Rf 777 "$exManDirectory"
#
# Call ExManCMD to install the .zxp file
."$exManPath" --install "$ZXPDirectory""$ZXPToInstall"
# Remove the staging files
rm -Rf "$ZXPDirectory"
rm -Rf "$exManDirectory"
