# Nudge - macOS Update Management - 12.5 - v1.3.plist
### For Nudge version 1.1.7+
## About this profile

This .plist is to assist in configuring Nudge to prompt users with clients running macOS Monterey 12.0.1-12.4 (Intel and Apple Silicon) to install the macOS 12.5 update via Apple Software Update.

The following keys will need to be configured (or removed) depending on your environment. Also configure the iconLightPath / iconDarkPath if you'd like otherwise remove it if the OS isn't pre-cached prior to launching Nudge.

optionalFeatures
- **blockedApplicationBundleIDs**: 69 applications are currently listed within blockedApplicationBundleIDs. Customize this for your environment, or to not block/restrict applications in your profile set **attemptToBlockApplicationLaunches** to "false" and set **blockedApplicationBundleIDs** to "Not Configured".

osVersionRequirements
- **requiredInstallationDate**: Set the Nudge / macOS update install deadline. *Currently set for September 15th, 2022*: "2022-09-15T00:00:00Z"

userInterface
- **iconLightPath**: If you wish to customize the logo, update this. Requires image file be pre-staged/pre-deployed to client systems prior to activating Nudge.
- **iconDarkPath**: If you wish to customize the logo, update this. Requires image file be pre-staged/pre-deployed to client systems prior to activating Nudge.

## .plist Key Values:

### optionalFeatures - Configured
- acceptableCameraUsage - Configured - true
- acceptableScreenSharingUsage - Configured - true
- aggressiveUserExperience - Configured - true
- aggressiveUserFullScreenExperience - Configured - true
- asynchronousSoftwareUpdate - Configured - true
- attemptToBlockApplicationLaunches - Configured - true
- attemptToFetchMajorUpgrade - Not Configured
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
- VMware Horizon Client - com.vmware.horizonenforceMinorUpdates - Configured - true

### osVersionRequirements - Configured - macOS Monterey + (targetedOSVersionsRule = default)

- aboutUpdateURL - https://support.apple.com/en-us/HT212585
- actionButtonPath - Not Configured
- majorUpgradeAppPath - Not Configured
- requiredInstallationDate - Configured - 2022-09-15T00:00:01Z
- requiredMinimumOSVersion - Configured - 12.5
- targetedOSVersions - Configured - 12.0.1, 12.1, 12.2, 12.2.1, 12.3, 12.3.1, 12.4
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


### userInterface - Configured
- iconLightPath - Configured - "/Library/Application Support/Corp_Branding/Light/install.png"
- iconDarkPath - Configured - "/Library/Application Support/Corp_Branding/Dark/install.png"
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
- mainContentText - Configured - "A fully up-to-date macOS is required to ensure that IT Support can your accurately protect and support your Mac, so it can continue to provide you with the best user experience possible everyday.\n\nThis update must be installed on your Mac prior to Thursday September 15th, 2022. If you do not update your Mac prior to the installation deadline, you may lose access to applications necessary for your day-to-day tasks until it is installed.\n\nTo begin the install now, simply click the blue 'Install Update Now' button above and follow the provided steps. To schedule a reminder to install later, click 'I Understand' or 'Schedule Reminder' below."
- mainHeader - Configured - "macOS Monterey 12.5 update required"
- primaryQuitButtonText - Configured - "Later"
- secondaryQuitButtonText - Configured - "I Understand"
- subHeader - Configured - "A friendly reminder from corporate IT Support"
