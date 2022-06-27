# macOS Monterey 12.4 - Self Service policy - Apple Silicon - v1
## General
### Trigger

None set

### Execution Frequency

Ongoing

<img width="910" alt="macOS Monterey 12 4 - Self Service policy - Apple Silicon  - v1 - General" src="https://user-images.githubusercontent.com/52809959/173923529-7f40005a-b0ce-43e3-8790-55678de3f70b.png">

## Packages
### Latest version of [erase-install-XX.xx.pkg](https://github.com/grahampugh/erase-install) by Graham Pugh
**NOTE: We had issues with erase-install-26.1.pkg** and **reverted back to erase-install-26.0.pkg** and **haven't had issues since reverting to v26.0.**

<img width="921" alt="macOS Monterey 12 4 - Self Service policy - Apple Silicon  - v1 - Packages" src="https://user-images.githubusercontent.com/52809959/173923579-33978fae-37f0-49ae-9df5-3818c23b6f4e.png">


## Scripts
### [macOS Monterey 12.4 - Self Service policy - Before script - Disk Space notification - v1.sh](https://gregknackstedt.com/Jamf_things/Configuration%20Profiles/com.github.macadmins.nudge/macOS%20Monterey%2012.4%20-%20Self%20Service%20policy%20-%20Before%20script%20-%20Disk%20Space%20notification%20-%20v1.1.sh)

### Priority

Before

<img width="915" alt="macOS Monterey 12 4 - Self Service policy - Apple Silicon  - v1 - Scripts" src="https://user-images.githubusercontent.com/52809959/173923612-6697ec2b-eead-4ced-8c9f-055edbb0c478.png">

## Files and Processes

### Execute Command

> /Library/Management/erase-install/erase-install.sh  --reinstall --build=21F79 --current-user --depnotify --fs --check-power --power-wait-limit 300 --min-drive-space=45 --cleanup-after-use

<img width="916" alt="macOS Monterey 12 4 - Self Service policy - Apple Silicon  - v1 - Files and Processes" src="https://user-images.githubusercontent.com/52809959/173923557-778d232b-9ec8-4c3d-9d53-e0dee38c6c1e.png">
