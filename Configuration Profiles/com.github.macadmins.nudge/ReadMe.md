# Nudge - macOS Update Managment - 12.4 - v3.4.plist
### For Nudge version 1.1.7+
## About this profile

The following two keys may not be set (3 occurences total to enter the URL), and will need to be added/configured to point to the proper Jamf Self Service policy installation URLs for Intel and Apple Silicon for your macOS Monterey upgrade workflow. Also configure the iconLightPath / iconDarkPath if you'd like otherwise remove it if the OS isn't pre-cached prior to launching Nudge.

osVersionRequirements - Configured
- actionButtonPath - Self Service macOS Monterey Policy URL (architecture specific policies) - Install or View URL
- majorUpgradeAppPath - Self Service macOS Monterey Policy URL (architecture specific policies) - Install or View URL

userInterface
- actionButtonPath - Self Service macOS Monterey Policy URL (architecture specific policies) - Install or View URL
- iconLightPath - If you wish to customize the logo used or don't pre-cache the Install macOS Monterey.app on your clients, update this.
- iconDarkPath - If you wish to customize the logo used or don't pre-cache the Install macOS Monterey.app on your clients, update this.

## optionalFeatures - Configured

acceptableCameraUsage - Configured - True

acceptableScreenSharingUsage - Configured - True

aggressiveUserExperience - Configured - True

asynchronousSoftwareUpdate - Configured - True

attemptToBlockApplicationLaunches - Configured - True

attemptToFetchMajorUpgrade - Configured - True

blockedApplicationBundleIDs - Configured

Adobe Photoshop - com.adobe.Photoshop

Adobe Illustrator - com.adobe.Illustrator

Adobe InDesign - com.adobe.InDesign

Adobe Creative Cloud Desktop - com.adobe.acc.AdobeCreativeCloud

Adobe Acrobat Pro - com.adobe.Acrobat.Pro

Adobe Acrobat DC - com.adobe.Acrobat

Apple Keynote - com.apple.Keynote

Apple Xcode - com.apple.Xcode

Apple Pages - com.apple.iWork.Pages

Apple iWork - com.apple.iWork.Numbers

Apple Music - com.apple.Music

Apple iPhoto - com.apple.iPhoto

Apple Safari - com.apple.Safari

AutoDesk AutoCAD - com.autodesk.AutoCAD

GitHub Desktop - com.github.GitHub

Google Chrome - com.google.Chrome

Mozilla Firefox - org.mozilla.firefox

Brave Browser - com.brave.Browser

Tor Browser - org.torproject.torbrowser

Vivaldi - com.vivaldi.Vivaldi

Eclipse IDE - org.eclipse.eclipse

Spotify - com.spotify.client

Panic Transmit - com.panic.Transmit

Opera - com.operasoftware.Opera

Microsoft Word - com.microsoft.Word

Microsoft Powerpoint - com.microsoft.Powerpoint

Microsoft OneNote - com.microsoft.onenote.mac

Microsoft Excel - com.microsoft.Excel

Microsoft Edge - com.microsoft.edgemac

Microsoft Visual Studio Code - com.microsoft.VSCode

Google SketchUp - com.google.sketchuppro

Pandora - com.pandora.desktop

Terminal.app - com.apple.Terminal

Activity Monitor.app - com.apple.ActivityMonitor

Postman - com.postmanlabs.mac

MySQLWorkbench - com.oracle.workbench.MySQLWorkbench

Extensis Universal Type Client - com.extensis.UniversalTypeClient

Slack - com.tinyspeck.slackmacgap

FaceTime - com.apple.FaceTime

Apple Configurator - com.apple.configurator.ui

Discord - com.hnc.Discord

VMware Horizon Client - com.vmware.horizon

UTM - com.utmapp.UTM

VirtualBox - org.virtualbox.app.VirtualBox

Parallels Desktop - com.parallels.desktop.console

Adobe Lightroom - com.adobe.lightroomCC

Adobe Premiere Pro 2022 - com.adobe.PremierePro.22

Adobe Premiere Pro 2021 - com.adobe.PremierePro.21

Adobe Premiere Pro 2020 - com.adobe.PremierePro.20

Adobe Premiere Pro 2019 - com.adobe.PremierePro.19

Adobe Premiere Pro 2018 - com.adobe.PremierePro.18

JetBrains PyCharm Community Edition - com.jetbrains.pycharm.ce

JetBrains PyCharm Professional - com.jetbrains.pycharm

JetBrains WebStorm - com.jetbrains.WebStorm

JetBrains PHPStorm - com.jetbrains.PhpStorm

JetBrains IntelliJ - com.jetbrains.intellij

DBeaver Ultimate - com.dbeaver.product.ultimate

DBeaver Community Edition - org.jkiss.dbeaver.core.product

DBeaver Enterprise - com.dbeaver.product.enterprise

Tableau Desktop - com.tableausoftware.tableaudesktop

CLO_Network_OnlineAuth.app - com.clo3d.security.clono

Docker - com.docker.docker

Gemini2 - com.macpaw.Gemini2

AutoDesk AutoCad 2017 - com.autodesk.AutoCAD2017

AutoDesk AutoCad 2018 - com.autodesk.AutoCAD2018

AutoDesk AutoCad 2019 - com.autodesk.AutoCAD2019

AutoDesk AutoCad 2020 - com.autodesk.AutoCAD2020

AutoDesk AutoCad 2021 - com.autodesk.AutoCAD2021

AutoDesk AutoCad 2022 - com.autodesk.AutoCAD2022

enforceMinorUpdates - True

## osVersionRequirements - Configured - macOS Monterey + macOS Big Sur Clients (targetedOSVersionsRule = default)

aboutUpdateURL - https://support.apple.com/en-us/HT212585

actionButtonPath - Configured - Self Service macOS Monterey Policy URL (architecture specific policies) - Install or View URL

majorUpgradeAppPath - Configured - Self Service macOS Monterey Policy URL (architecture specific policies) - Install or View URL

requiredInstallationDate - Configured - 2022-06-23T00:00:01Z

requiredMinimumOSVersion - Configured - 12.4

targetedOSVersionsRule - Configured - "default"

## userExperience - Configured

allowGracePeriods - Configured - true

allowUserQuitDeferrals - Configured - true

allowedDeferrals - Configured - 15

allowedDeferralsUntilForcedSecondaryQuitButton - Configured - 5

approachingRefreshCycle - Configured - 3600

approachingWindowTime - Configured - 96

elapsedRefreshCycle - Configured - 60

gracePeriodInstallDelay - Configured - 24

gracePeriodLaunchDelay - Configured - 4

gracePeriodPath - Configured - /private/var/db/.AppleSetupDone

imminentRefreshCycle - Configured - 120

imminentWindowTime - Configured - 48

initialRefreshCycle - Configured - 9000

maxRandomDelayInSeconds - Configured - 1200

randomDelay - Configured - false



## userInterface - Configured

actionButtonPath - Configured - Self Service macOS Monterey Policy URL (architecture specific policies) - Install URL

iconLightPath - Configured - "/Applications/Install macOS Monterey.app/Contents/Resources/InstallAssistant.icns"

iconDarkPath - Configured - "/Applications/Install macOS Monterey.app/Contents/Resources/InstallAssistant.icns"

showDeferralCount - Configured - true

simpleMode - Configured - false

singleQuitButton - Configured - false



## updateElements - Configured

#### updateElement - Dictionary 1

language - Configured - "en"

actionButtonText - Configured - "Install Update Now"

customDeferralButtonText - Configured - "Select a Date and Time"

customDeferralDropdownText - Configured - "Schedule Reminder"

informationButtonText - Configured - "About This Update"

mainContentHeader - Configured - "Your Mac will need to reboot in order to complete update installation."

mainContentNote - "An Important Note Regarding Required Updates"

mainContentSubHeader - Configured - "Updates may take up to 30-45 minutes to install"

mainContentText - Configured - "An fully up-to-date macOS is required to ensure that IT Support can your accurately protect and support your Mac, so it can continue to provide you with the best user experience possible everyday.\n\nThis update must be installed on your Mac prior to Thursday June 23, 2022. If you do not update your Mac prior to the installation deadline, you may lose access to applications necessary for your day-to-day tasks until it is installed.\n\nTo begin the install now, simply click the blue “Install Update Now” button above and follow the provided steps. To schedule a reminder to install later, click “I Understand” or "Schedule Reminder" below."

mainHeader - Configured - "macOS Monterey 12.4 update required"

oneDayDeferralButtonText - Configured - "Tomorrow"

oneHourDeferralButtonText - Configured - "One Hour"

mainHeader - Configured - "macOS Monterey 12.4 update required"

primaryQuitButtonText - Configured - "Later"

secondaryQuitButtonText - Configured - "I Understand"

subHeader - Configured - "A friendly reminder from corporate IT Support"
