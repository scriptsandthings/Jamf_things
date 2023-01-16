#!/bin/bash
#
####################################
#
# Fiery_Staged_Driver_Install.sh
#
# Install Fiery Printer Driver from .app staged on client
# v2.5
#
#####################################
#
# Greg Knackstedt
# 1.16.2023
# https://github.com/scriptsandthings
# shitttyscripts@gmail.com
#
#####################################
#
FieryDriverPreStaged="${4:-"/tmp/Fiery Printer Driver Installer.app"}"
#
sudo "$FieryDriverPreStaged"/Contents/Resources/User\ Software/OSX/Printer\ Driver/Installer\ Wizard.app/Contents/MacOS/Fiery\ Printer\ Driver\ Installer install
#
# Delete staged Fiery driver .app
rm -Rf "$FieryDriverPreStaged"

exit 0
