#!/bin/zsh
label="" # if no label is sent to the script, this will be used

# Installomator
#
# Downloads and installs Applications
# 2020-2021 Installomator
#
# inspired by the download scripts from William Smith and Sander Schram
# 
# Contributers:
#    Armin Briegel - @scriptingosx
#    Isaac Ordonez - @issacatmann
#    Søren Theilgaard - @Theile
#    Adam Codega - @acodega
#
# with contributions from many others

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# NOTE: adjust these variables:

# set to 0 for production, 1 or 2 for debugging
# while debugging, items will be downloaded to the parent directory of this script
# also no actual installation will be performed
# debug mode 1 will download to the directory the script is run in, but will not check the version 
# debug mode 2 will download to the temp directory, check for blocking processes, check the version, but will not install anything or remove the current version
DEBUG=1

# notify behavior
NOTIFY=success
# options:
#   - success      notify the user on success
#   - silent       no notifications
#   - all          all notifications (great for Self Service installation)


# behavior when blocking processes are found
BLOCKING_PROCESS_ACTION=tell_user
# options:
#   - ignore       continue even when blocking processes are found
#   - quit         app will be told to quit nicely if running
#   - quit_kill    told to quit twice, then it will be killed
#                  Could be great for service apps if they do not respawn
#   - silent_fail  exit script without prompt or installation
#   - prompt_user  show a user dialog for each blocking process found
#                  abort after three attempts to quit
#                  (only if the user accepts to quit the apps, otherwise
#                  the update is canceled).
#   - prompt_user_then_kill
#                  show a user dialog for each blocking process found,
#                  attempt to quit two times, kill the process finally
#   - prompt_user_loop
#                  Like prompt-user, but clicking "Not Now", will just wait an hour,
#                  and then it will ask again.
#                  WARNING! It might block the MDM agent on the machine, as
#                  the scripts get stuck in waiting until the hour has passed,
#                  possibly blocking for other management actions in this time.
#   - tell_user    User will be shown a notification about the important update,
#                  but the user is only allowed to quit and continue, and then we
#                  ask the app to quit.
#   - tell_user_then_kill
#                  Show dialog 2 times, and if the quitting fails, the
#                  blocking processes will be killed.
#   - kill         kill process without prompting or giving the user a chance to save


# logo-icon used in dialog boxes if app is blocking
LOGO=appstore
# options:
#   - appstore      Icon is Apple App Store (default)
#   - jamf          JAMF Pro
#   - mosyleb       Mosyle Business
#   - mosylem       Mosyle Manager (Education)
#   - addigy        Addigy
# path can also be set in the command call, and if file exists, it will be used.
# Like 'LOGO="/System/Applications/App\ Store.app/Contents/Resources/AppIcon.icns"'
# (spaces have to be escaped).


# App Store apps handling
IGNORE_APP_STORE_APPS=no
# options:
#  - no            If the installed app is from App Store (which include VPP installed apps)
#                  it will not be touched, no matter its version (default)
#  - yes           Replace App Store (and VPP) version of the app and handle future
#                  updates using Installomator, even if latest version.
#                  Shouldn’t give any problems for the user in most cases.
#                  Known bad example: Slack will lose all settings.

# Owner of copied apps
SYSTEMOWNER=0
# options:
#  - 0             Current user will be owner of copied apps, just like if they
#                  installed it themselves (default).
#  - 1             root:wheel will be set on the copied app.
#                  Useful for shared machines.

# install behavior
INSTALL=""
# options:
#  -               When not set, the software will only be installed
#                  if it is newer/different in version
#  - force         Install even if it’s the same version


# Re-opening of closed app
REOPEN="yes"
# options:
#  - yes           App will be reopened if it was closed
#  - no            App not reopened

# Only let Installomator return the name of the label
# RETURN_LABEL_NAME=0
# options:
#   - 1      Installomator will return the name of the label and exit, so last line of
#            output will be that name. When Installomator is locally installed and we
#            use DEPNotify, then DEPNotify can present a more nice name to the user,
#            instead of just the label name.


# NOTE: How labels work

# Each workflow label needs to be listed in the case statement below.
# for each label these variables can be set:
#
# - name: (required)
#   Name of the installed app.
#   This is used to derive many of the other variables.
#
# - type: (required)
#   The type of the installation. Possible values:
#     - dmg
#     - pkg
#     - zip
#     - tbz
#     - pkgInDmg
#     - pkgInZip
#     - appInDmgInZip
#     - updateronly     This last one is for labels that should only run an updateTool (see below)
#
# - packageID: (optional)
#   The package ID of a pkg
#   If given, will be used to find the version of installed software, instead of searching for an app.
#   Usefull if a pkg does not install an app.
#   See label installomator_st
#
# - downloadURL: (required)
#   URL to download the dmg.
#   Can be generated with a series of commands (see BBEdit for an example).
#
# - appNewVersion: (optional)
#   Version of the downloaded software.
#   If given, it will be compared to the installed version, to see if the download is different.
#   It does not check for newer or not, only different.
#
# - versionKey: (optional)
#   How we get version number from app. Possible values:
#     - CFBundleShortVersionString
#     - CFBundleVersion
#   Not all software titles uses fields the same. 
#   See Opera label.
#
# - appCustomVersion(){}: (optional function)
#   This function can be added to your label, if a specific custom
#   mechanism hs to be used for getting the installed version.
#   See labels zulujdk11, zulujdk13, zulujdk15
#
# - expectedTeamID: (required)
#   10-digit developer team ID.
#   Obtain the team ID by running:
#
#   - Applications (in dmgs or zips)
#     spctl -a -vv /Applications/BBEdit.app
#
#   - Pkgs
#     spctl -a -vv -t install ~/Downloads/desktoppr-0.2.pkg
#
#   The team ID is the ten-digit ID at the end of the line starting with 'origin='
#
# - archiveName: (optional)
#   The name of the downloaded file.
#   When not given the archiveName is derived from the $name.
#   Note: This has to be defined BEFORE calling downloadURLFromGit or
#   versionFromGit functions in the label.
#
# - appName: (optional)
#   File name of the app bundle in the dmg to verify and copy (include .app).
#   When not given, the appName is derived from the $name.
#
# - targetDir: (optional)
#   dmg or zip:
#     Applications will be copied to this directory.
#     Default value is '/Applications' for dmg and zip installations.
#   pkg:
#     targetDir is used as the install-location. Default is '/'.
#
# - blockingProcesses: (optional)
#   Array of process names that will block the installation or update.
#   If no blockingProcesses array is given the default will be:
#     blockingProcesses=( $name )
#   When a package contains multiple applications, _all_ should be listed, e.g:
#     blockingProcesses=( "Keynote" "Pages" "Numbers" )
#   When a workflow has no blocking processes, use
#     blockingProcesses=( NONE )
#
# - pkgName: (optional, only used for pkgInDmg, dmgInZip, and appInDmgInZip)
#   File name or path to the pkg/dmg file _inside_ the dmg or zip.
#   When not given the pkgName is derived from the $name
#
# - updateTool:
# - updateToolArguments:
#   When Installomator detects an existing installation of the application,
#   and the updateTool variable is set
#      $updateTool $updateArguments
#   Will be run instead of of downloading and installing a complete new version.
#   Use this when the updateTool does differential and optimized downloads.
#   e.g. msupdate on various Microsoft labels
#
# - updateToolRunAsCurrentUser:
#   When this variable is set (any value), $updateTool will be run as the current user.
#
# - CLIInstaller:
# - CLIArguments:
#   If the downloaded dmg is an installer that we can call using CLI, we can
#   use these two variables for what to call.
#   We need to define `name` for the installed app (to be version checked), as well as
#   `installerTool` for the installer app (if named differently than `name`. Installomator
#   will add the path to the folder/disk image with the binary, and it will be called like this:
     `$CLIInstaller $CLIArguments`
#   For most installations `CLIInstaller` should contain the `installerTool` for the CLI call
#   (if it’s the same).
#   We can support a whole range of other software titles by implementing this.
#   See label adobecreativeclouddesktop
#
# - installerTool:
#   Introduced as part of `CLIInstaller`. If the installer in the DMG or ZIP is named
#   differently than the installed app, then this variable can be used to name the
#   installer that should be located after mounting/expanding the downloaded archive.
#   See label adobecreativeclouddesktop
#
