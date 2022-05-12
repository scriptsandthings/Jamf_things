
#!/bin/bash
#
####################################
#
# Fiery_Staged_Driver_Uninstall_v1.sh
#
# Silently uninstalls Fiery Printer Drivers with help of .app staged in /tmp
# v1.0
# https://github.com/scriptsandthings
#
# Greg Knackstedt
# 5.12.2022
#

#
sudo /tmp/Fiery\ Printer\ Driver\ Installer.app/Contents/Resources/User\ Software/OSX/Printer\ Driver/Installer\ Wizard.app/Contents/MacOS/Fiery\ Printer\ Driver\ Installer remove
#
# Delete staged Fiery driver .app
sudo rm -Rf /tmp/Fiery\ Printer\ Driver\ Installer.app

exit 0
