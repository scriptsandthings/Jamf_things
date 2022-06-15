# macOS Monterey 12.4 - Self Service policy - Intel - v1
## General
### Trigger

None set

### Execution Frequency

Ongoing

<img width="914" alt="macOS Monterey 12 4 - Self Service policy - Intel  - v1 - General" src="https://user-images.githubusercontent.com/52809959/173923807-0578650c-6797-4ae1-aa5c-5ea8831d5b72.png">

## Packages
### Latest version of[erase-install-XX.xx.pkg](https://github.com/grahampugh/erase-install) by Graham Pugh

<img width="918" alt="macOS Monterey 12 4 - Self Service policy - Intel  - v1 - Packages" src="https://user-images.githubusercontent.com/52809959/173923726-a06196e3-7e4c-470e-b347-f8e559557a3a.png">

## Scripts
### [macOS Monterey 12.4 - Self Service policy - Before script - Disk Space notification - v1.sh](https://github.com/scriptsandthings/Jamf_things/blob/master/Configuration%20Profiles/com.github.macadmins.nudge/macOS%20Monterey%2012.4%20-%20Self%20Service%20policy%20-%20Before%20script%20-%20Disk%20Space%20notification%20-%20v1.sh)

### Priority

Before

<img width="916" alt="macOS Monterey 12 4 - Self Service policy - Intel  - v1 - Scripts" src="https://user-images.githubusercontent.com/52809959/173923778-24f7072f-5b9f-49fe-b535-feb556814f26.png">

## Files and Processes

### Execute Command

/Library/Management/erase-install/erase-install.sh --reinstall --build=21F79 --depnotify --fs --check-power --power-wait-limit 300 --min-drive-space=45 --cleanup-after-use

<img width="924" alt="macOS Monterey 12 4 - Self Service policy - Intel  - v1 - Files and processes" src="https://user-images.githubusercontent.com/52809959/173923771-c4a72a7d-44c9-414c-af0a-caa0ccd76aaa.png">

