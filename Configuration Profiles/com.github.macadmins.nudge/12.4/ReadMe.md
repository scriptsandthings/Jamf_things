# Nudge - macOS Update Management - 12.4 - v40.plist
### For Nudge version 1.1.7+

[Download Nudge - macOS Update Management - 12.4 - v4.0.plist](https://www.gregknackstedt.com/Jamf_things/Configuration%20Profiles/com.github.macadmins.nudge/12.4/Nudge%20-%20macOS%20Update%20Management%20-%2012.4%20-%20v4.0.plist) 
- Create one for Intel and one for Apple Silicon. 
- Configure platform specific policies in Jamf and point *actionButtonPath* and *majorUpgradeAppPath* to the platform specific Self Service policy URLs 

![alt text](https://www.gregknackstedt.com/Jamf_things/Configuration%20Profiles/com.github.macadmins.nudge/12.4/Nudge%20-%20macOS%20Update%20Management%20-%2012.4%20-%20v3.3.png)

# About this .plist

## Jamf Policy Examples / Scripts

- [macOS Monterey 12.4 - Self Service policy - Apple Silicon](https://www.gregknackstedt.com/Jamf_things/Configuration%20Profiles/com.github.macadmins.nudge/12.4/macOS%20Monterey%2012.4%20-%20Self%20Service%20policy%20-%20Apple%20Silicon%20-%20v1/)
- [macOS Monterey 12.4 - Self Service policy - Intel](https://www.gregknackstedt.com/Jamf_things/Configuration%20Profiles/com.github.macadmins.nudge/12.4/macOS%20Monterey%2012.4%20-%20Self%20Service%20policy%20-%20Intel%20-%20v1/)

#### OPTIONAL: Pre-Install disk space notification policy
- [macOS Monterey 12.4 - Self Service policy - Before script - Disk Space notification - v1.1.sh](https://www.gregknackstedt.com/Jamf_things/Configuration%20Profiles/com.github.macadmins.nudge/12.4/macOS%20Monterey%2012.4%20-%20Self%20Service%20policy%20-%20Before%20script%20-%20Disk%20Space%20notification%20-%20v1.1.sh)

The following keys will need to be configured (or removed) depending on your environment. Also configure the iconLightPath / iconDarkPath if you'd like otherwise remove it if the OS isn't pre-cached prior to launching Nudge.

**osVersionRequirements**
- actionButtonPath - Self Service macOS Monterey Policy URL (architecture specific policies) - Install or View URL
- majorUpgradeAppPath - Self Service macOS Monterey Policy URL (architecture specific policies) - Install or View URL
- **requiredInstallationDate**: Set the Nudge / macOS update install deadline. *Currently set for June 23rd, 2022*: "2022-06-23T00:00:00Z"

**userInterface**
- actionButtonPath - Self Service macOS Monterey Policy URL (architecture specific policies) - Install or View URL
- iconLightPath - If you wish to customize the logo used or don't pre-cache the Install macOS Monterey.app on your clients, update this.
- iconDarkPath - If you wish to customize the logo used or don't pre-cache the Install macOS Monterey.app on your clients, update this.

## .plist keys

### optionalFeatures - Configured
- acceptableCameraUsage - Configured - true
- acceptableScreenSharingUsage - Configured - true
- aggressiveUserExperience - Configured - true
- aggressiveUserFullScreenExperience - Configured - True
- asynchronousSoftwareUpdate - Configured - true
- attemptToBlockApplicationLaunches - Configured - true
- attemptToFetchMajorUpgrade - Not Configured
- enforceMinorUpdates - Configured - True
- blockedApplicationBundleIDs - Configured
##### blockedApplicationBundleIDs:
- Adobe Acrobat DC - com.adobe.Acrobat
- Adobe Acrobat Pro - com.adobe.Acrobat.Pro
- Adobe Creative Cloud Desktop - com.adobe.acc.AdobeCreativeCloud
- Adobe Illustrator - com.adobe.Illustrator
- Adobe InDesign - com.adobe.InDesign
- Adobe Lightroom - com.adobe.lightroomCC
- Adobe Photoshop - com.adobe.Photoshop
- Adobe Premiere Pro 2018 - com.adobe.PremierePro.18
- Adobe Premiere Pro 2019 - com.adobe.PremierePro.19
- Adobe Premiere Pro 2020 - com.adobe.PremierePro.20
- Adobe Premiere Pro 2021 - com.adobe.PremierePro.21
- Adobe Premiere Pro 2022 - com.adobe.PremierePro.22
- Apple Configurator - com.apple.configurator.ui
- Apple FaceTime - com.apple.FaceTime
- Apple iPhoto - com.apple.iPhoto
- Apple Keynote - com.apple.Keynote
- Apple Music - com.apple.Music
- Apple Numbers - com.apple.iWork.Numbers
- Apple Pages - com.apple.iWork.Pages
- Apple Safari - com.apple.Safari
- Apple Xcode - com.apple.Xcode
- Apple/macOS Activity Monitor.app - com.apple.ActivityMonitor
- Apple/macOS Terminal.app - com.apple.Terminal
- AutoDesk AutoCAD - com.autodesk.AutoCAD
- AutoDesk AutoCad 2017 - com.autodesk.AutoCAD2017
- AutoDesk AutoCad 2018 - com.autodesk.AutoCAD2018
- AutoDesk AutoCad 2019 - com.autodesk.AutoCAD2019
- AutoDesk AutoCad 2020 - com.autodesk.AutoCAD2020
- AutoDesk AutoCad 2021 - com.autodesk.AutoCAD2021
- AutoDesk AutoCad 2022 - com.autodesk.AutoCAD2022
- Brave Browser - com.brave.Browser
- CLO_Network_OnlineAuth.app - com.clo3d.security.clono
- DBeaver Community Edition - org.jkiss.dbeaver.core.product
- DBeaver Enterprise - com.dbeaver.product.enterprise
- DBeaver Ultimate - com.dbeaver.product.ultimate
- Discord - com.hnc.Discord
- Docker - com.docker.docker
- Eclipse IDE - org.eclipse.eclipse
- Extensis Universal Type Client - com.extensis.UniversalTypeClient
- Gemini2 - com.macpaw.Gemini2
- GitHub Desktop - com.github.GitHub
- Google Chrome - com.google.Chrome
- Google SketchUp - com.google.sketchuppro
- JetBrains IntelliJ - com.jetbrains.intellij
- JetBrains PHPStorm - com.jetbrains.PhpStorm
- JetBrains PyCharm Community Edition - com.jetbrains.pycharm.ce
- JetBrains PyCharm Professional - com.jetbrains.pycharm
- JetBrains WebStorm - com.jetbrains.WebStorm
- Microsoft Edge - com.microsoft.edgemac
- Microsoft Excel - com.microsoft.Excel
- Microsoft OneNote - com.microsoft.onenote.mac
- Microsoft Powerpoint - com.microsoft.Powerpoint
- Microsoft Visual Studio Code - com.microsoft.VSCode
- Microsoft Word - com.microsoft.Word
- Mozilla Firefox - org.mozilla.firefox
- MySQLWorkbench - com.oracle.workbench.MySQLWorkbench
- Opera - com.operasoftware.Opera
- Pandora - com.pandora.desktop
- Panic Transmit - com.panic.Transmit
- Parallels Desktop - com.parallels.desktop.console
- Postman - com.postmanlabs.mac
- Slack - com.tinyspeck.slackmacgap
- Spotify - com.spotify.client
- Tableau Desktop - com.tableausoftware.tableaudesktop
- Tor Browser - org.torproject.torbrowser
- UTM - com.utmapp.UTM
- VirtualBox - org.virtualbox.app.VirtualBox
- Vivaldi - com.vivaldi.Vivaldi
- VMware Horizon Client - com.vmware.horizon

### osVersionRequirements - Configured - macOS Monterey + macOS Big Sur Clients (targetedOSVersionsRule = default)
- aboutUpdateURL - https://support.apple.com/en-us/HT212585
- actionButtonPath - Configured - Self Service macOS Monterey Policy URL (architecture specific policies) - Install URL
- majorUpgradeAppPath - Configured - Self Service macOS Monterey Policy URL (architecture specific policies) - Install URL
- requiredInstallationDate - Configured - 2022-06-23T00:00:01Z
- requiredMinimumOSVersion - Configured - 12.4
- targetedOSVersions - Configured - 11.0.1 ,11.1 ,11.2 ,11.2.1 ,11.2.2 ,11.2.3 ,11.3 ,11.3.1 ,11.4 ,11.5 ,11.5.1 ,11.5.2 ,11.6 ,11.6.1 ,11.6.2 ,11.6.3 ,11.6.4 ,11.6.5 ,11.6.6 ,11.6.7 ,12.0.1 ,12.1 ,12.2 ,12.2.1 ,12.3 ,12.3.1
- targetedOSVersionsRule - Configured - "default"

### userExperience - Configured
- allowGracePeriods - Configured - true
- allowUserQuitDeferrals - Configured - true
- allowedDeferrals - Configured - 15
- allowedDeferralsUntilForcedSecondaryQuitButton - Configured - 5
- approachingRefreshCycle - Configured - 3600
- approachingWindowTime - Configured - 96
- elapsedRefreshCycle - Configured - 60
- gracePeriodInstallDelay - Configured - 24
- gracePeriodLaunchDelay - Configured - 4
- gracePeriodPath - Configured - /private/var/db/.AppleSetupDone
- imminentRefreshCycle - Configured - 120
- imminentWindowTime - Configured - 48
- initialRefreshCycle - Configured - 9000
- maxRandomDelayInSeconds - Configured - 1200
- randomDelay - Configured - false

## userInterface - Configured
- actionButtonPath - Configured - Self Service macOS Monterey Policy URL (architecture specific policies) - Install URL
- iconLightPath - Configured - "/Applications/Install macOS Monterey.app/Contents/Resources/InstallAssistant.icns"
- iconDarkPath - Configured - "/Applications/Install macOS Monterey.app/Contents/Resources/InstallAssistant.icns"
- showDeferralCount - Configured - true
- simpleMode - Configured - false
- singleQuitButton - Configured - false

### updateElements - Configured
#### updateElement - Dictionary 1
- language - Configured - "en"
- actionButtonText - Configured - "Install Update Now"
- customDeferralButtonText - Configured - "Select a Date and Time"
- customDeferralDropdownText - Configured - "Schedule Reminder"
- informationButtonText - Configured - "About This Update"
- oneDayDeferralButtonText - Configured "Tomorrow"
- oneHourDeferralButtonText - Configured - "One Hour"
- mainContentHeader - Configured - "Your Mac will need to reboot in order to complete update installation."
- mainContentNote - "An Important Note Regarding Required Updates"
- mainContentSubHeader - Configured - "Updates may take up to 30-45 minutes to install"
- mainContentText - Configured - "A fully up-to-date macOS is required to ensure that IT Support can your accurately protect and support your Mac, so it can continue to provide you with the best user experience possible everyday.\n\nThis update must be installed on your Mac prior to Thursday June 23rd, 2022. If you do not update your Mac prior to the installation deadline, you may lose access to applications necessary for your day-to-day tasks until it is installed.\n\nTo begin the install now, simply click the blue 'Install Update Now' button above and follow the provided steps. To schedule a reminder to install later, click 'I Understand' or 'Schedule Reminder' below."
- mainHeader - Configured - "macOS Monterey 12.4 update required"
- primaryQuitButtonText - Configured - "Later"
- secondaryQuitButtonText - Configured - "I Understand"
- subHeader - Configured - "A friendly reminder from corporate IT Support"
