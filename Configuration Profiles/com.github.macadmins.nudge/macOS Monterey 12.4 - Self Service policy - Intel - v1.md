# macOS Monterey 12.4 - Self Service policy - Intel - v1
## General
### Trigger

None set

### Execution Frequency

Ongoing

<img width="907" alt="macOS Monterey 12 4 - Self Service policy - Intel  - v1 - 1" src="https://user-images.githubusercontent.com/52809959/173921492-7fe9cd41-c3fd-44ef-97ba-da27ce09cd95.png">

## Packages
### Latest version of[erase-install-XX.xx.pkg](https://github.com/grahampugh/erase-install) by Graham Pugh

<img width="921" alt="macOS Monterey 12 4 - Self Service policy - Intel  - v1 - 2" src="https://user-images.githubusercontent.com/52809959/173921510-b03812bd-ed3c-4d83-b29e-4cbe93345983.png">

## Scripts
### [macOS Monterey 12.4 - Self Service policy - Before script - Disk Space notification - v1.sh](https://github.com/scriptsandthings/Jamf_things/blob/master/Configuration%20Profiles/com.github.macadmins.nudge/macOS%20Monterey%2012.4%20-%20Self%20Service%20policy%20-%20Before%20script%20-%20Disk%20Space%20notification%20-%20v1.sh)

### Priority

Before

<img width="918" alt="macOS Monterey 12 4 - Self Service policy - Intel  - v1 - 3" src="https://user-images.githubusercontent.com/52809959/173921518-669ea1a0-cd2a-4fd8-a59b-a6da30e0f334.png">

## Files and Processes

<img width="922" alt="macOS Monterey 12 4 - Self Service policy - Intel  - v1 - 4" src="https://user-images.githubusercontent.com/52809959/173921528-b323e9d8-d027-406d-819e-dca0b267fb6e.png">

### Execute Command
/Library/Management/erase-install/erase-install.sh --reinstall --build=21F79 --depnotify --fs --check-power --power-wait-limit 300 --min-drive-space=45
