#!/bin/bash
# Script to use ExManCMD to install ZXP plugins for Adobe CC
# Variables
ZXPDirectory="$4"
ZXPToInstall="$5"
exManDirectory="$6"
exManPath="$7"
# Change permissions on pre-staged installation files
chmod -Rf 777 "$ZXPDirectory"
chmod -Rf 777 "$exManDirectory"
#
# Call ExManCMD to install the .zxp file
."$exManPath" --install "$ZXPDirectory""$ZXPToInstall"
# Remove the staging files
rm -Rf "$ZXPDirectory"
rm -Rf "$exManDirectory"
