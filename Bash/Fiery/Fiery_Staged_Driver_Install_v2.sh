#!/bin/bash
#
####################################
#
# Fiery_Staged_Driver_Install_v2.sh
#
# Install Fiery Printer Driver from .app staged in /tmp
# v2.0
# https://github.com/scriptsandthings
#
# Greg Knackstedt
# 5.12.2022
#

#
sudo /tmp/Fiery\ Printer\ Driver\ Installer.app/Contents/Resources/User\ Software/OSX/Printer\ Driver/Installer\ Wizard.app/Contents/MacOS/Fiery\ Printer\ Driver\ Installer install
#
# Delete staged Fiery driver .app
sudo rm -Rf /tmp/Fiery\ Printer\ Driver\ Installer.app

exit 0
