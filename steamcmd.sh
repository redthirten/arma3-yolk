#!/bin/bash

# -----------------------------------------------------------------------------
# SteamCMD Bash Wrapper
# Author: Red-Thirten (David Wolfe)
# Date: 03/02/26
#
# Description:
#   Easily call SteamCMD (with error handling) via various arguments to
#   download/update an app and/or mods.
#
#   Mods Note: The calling parent script is responsible for positioning mods
#   in the correct location to accommodate the app that will use them.
#   SteamCMD does not like mod folders leaving their original download location,
#   so the following command is recommended to make a recursive hardlink copy
#   of the mod to its final required location (ie. an identical copy w/o using
#   additional disk space and will update automatically):
#   cp -al ~/Steam/steamapps/workshop/content/${GAME_ID}/${MOD_ID}/* ~/final/location/${MOD_ID}/
#
# Arguments:
#   $1 - Source file path (required)
#   $2 - Backup directory (required)
#
# Returns:
#   0 - Success
#   1 - Source file does not exist
#   2 - Backup failed
#
# Usage:
#   backup_file "/path/to/file.txt" "/backup/location"
# -----------------------------------------------------------------------------

## === CONSTANTS ===
STEAMCMD_DIR="${HOME}/steamcmd"                 # SteamCMD's directory containing steamcmd.sh
WORKSHOP_DIR="${HOME}/Steam/steamapps/workshop" # SteamCMD's directory containing workshop downloads
STEAMCMD_SCRIPT="${STEAMCMD_DIR}/runscript.txt" # Runscript file for SteamCMD (contains all commands SteamCMD will run)
STEAMCMD_LOG="${STEAMCMD_DIR}/steamcmd.log"     # Log file for SteamCMD

# Color Codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

## === ARGUMENT VARS ===
attempts=1
installDir=${HOME}
user="anonymous"
pass=""
auth=""
appID=
betaID="public"
betaPass=
hldsGame=
windows="0"
steamworks="1"
validate="0"
modsAppID=
mods=()

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --attempts)
            attempts=$2
            shift 2
            ;;
        --install-dir)
            installDir="$2"
            shift 2
            ;;
        --user)
            user="$2"
            shift 2
            ;;
        --pass)
            pass="$2"
            shift 2
            ;;
        --auth)
            auth="$2"
            shift 2
            ;;
        --app-id)
            appID="$2"
            shift 2
            ;;
        --beta-id)
            betaID="$2"
            shift 2
            ;;
        --beta-pass)
            betaPass="$2"
            shift 2
            ;;
        --hlds-game)
            hldsGame="$2"
            shift 2
            ;;
        --windows)
            windows="$2"
            shift 2
            ;;
        --add-redist)
            steamworks="$2"
            shift 2
            ;;
        --validate)
            validate="$2"
            shift 2
            ;;
        --mods-app-id)
            modsAppID="$2"
            shift 2
            ;;
        --)
            # Mod list at end
            shift
            mods=("$@")
            break
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

## === PREPARE STEAMCMD ===
echo -e "\n${GREEN}[SteamCMD]: ${CYAN}Starting checks for all updates...${NC}"
echo -e "\t(It is okay to ignore any \"SDL\", \"steamservice\", and \"thread priority\" errors during this process)"

# Create or clear existing runscript file
> ${STEAMCMD_SCRIPT}

if [[ "${windows}" == "1" ]]; then
    echo "@sSteamCmdForcePlatformType windows" >> ${STEAMCMD_SCRIPT}
fi

# Set default credential if empty string is somehow passed
if [ "${user}" == "" ]; then
    echo -e "\tSteam user is not set. Defaulting to anonymous user."
    user="anonymous"
fi
# (We don't write credentials to plain text file)

if [[ "${validate}" == "1" ]]; then
    echo -e "\t${CYAN}File validation enabled.${NC} (This may take extra time to complete)"
    validate="validate"
else
    validate=""
fi

if [[ "${steamworks}" == "1" ]]; then
    echo "app_update 1007 ${validate}" >> ${STEAMCMD_SCRIPT}
fi

if [[ -n ${hldsGame} ]]; then
    echo "app_set_config 90 mod ${hldsGame}" >> ${STEAMCMD_SCRIPT}
fi

if [[ ${betaID} != "public" ]]; then
    echo -e "\tDownload/Update of ${CYAN}\"${betaID}\" branch${NC} enabled."
    beta="-beta ${betaID}"
    if [[ -n ${betaPass} ]]; then
        beta+=" -betapassword ${betaPass}"
    fi
fi

if [[ -n "${appID}" ]]; then
    echo -e "\tChecking for ${CYAN}server${NC} updates with App ID: ${CYAN}${appID}${NC}"
    echo "app_update ${appID} ${beta} ${validate}" >> ${STEAMCMD_SCRIPT}
else
    echo -e "${GREEN}[SteamCMD]: ${RED}App ID not specified! ${YELLOW}Unable to process download/update.${NC}"
    exit 1
fi

if [[ -n "${modsAppID}" && ${#mods[@]} -gt 0 ]]; then
    echo -e "\tChecking the following ${CYAN}Workshop mod IDs${NC} for updates: ${mods[@]}"
    for modID in "${mods[@]}"; do
        echo "workshop_download_item ${modsAppID} $modID" >> ${STEAMCMD_SCRIPT}
    done
fi

echo "quit" >> ${STEAMCMD_SCRIPT}

# Clear previous SteamCMD log if present
if [[ -f "${STEAMCMD_LOG}" ]]; then
    rm -f "${STEAMCMD_LOG:?}"
fi

updateAttempt=0
# Loop for specified number of attempts
while (( $updateAttempt < $attempts )); do
    # Increment attempt counter
    updateAttempt=$((updateAttempt+1))

    # Notify if not first attempt
    if (( $updateAttempt > 1 )); then
        echo -e "\t${YELLOW}Re-Attempting download/update in 3 seconds...${NC} (Attempt ${CYAN}${updateAttempt}${NC} of ${CYAN}${attempts}${NC})\n"
        sleep 3
    fi

    # Run SteamCMD with script file
    ${STEAMCMD_DIR}/steamcmd.sh +force_install_dir ${installDir} +login "${user}" "${pass}" "${auth}" +runscript ${STEAMCMD_SCRIPT}
    # echo -e "Running SteamCMD..."

    # Error checking for SteamCMD
    steamcmdExitCode=${PIPESTATUS[0]}
    loggedErrors=$(grep -i "error\|failed" "${STEAMCMD_LOG}" | grep -iv "setlocal\|SDL\|steamservice\|thread priority\|libcurl")
    if [[ -n ${loggedErrors} ]]; then # Catch errors (ignore setlocale, SDL, steamservice, thread priority, and libcurl warnings)
        # Soft errors
        if [[ -n $(grep -i "Timeout downloading item" "${STEAMCMD_LOG}") ]]; then # Mod download timeout
            echo -e "\n${YELLOW}[SteamCMD]: ${NC}A Steam Workshop mod timed out while downloading."
            echo -e "\t(This is expected for large mods that are multiple gigabytes in size)"
        elif [[ -n $(grep -i "0x402\|0x6\|0x602" "${STEAMCMD_LOG}") ]]; then # Connection issue with Steam
            echo -e "\n${YELLOW}[SteamCMD]: ${NC}Connection issue with Steam servers."
            echo -e "\t(Steam servers may currently be down, or a connection cannot be made reliably)"
        # Fatal errors
        elif [[ -n $(grep -i "Password check for AppId" "${STEAMCMD_LOG}") ]]; then # Incorrect beta branch password
            echo -e "\n${RED}[SteamCMD]: Incorrect password given for beta branch \"${betaID}\"${NC}"
            exit 1
        elif [[ -n $(grep -i "Invalid Password\|two-factor\|No subscription" "${STEAMCMD_LOG}") ]]; then # Wrong username/password, Steam Guard is turned on, or host is using anonymous account
            echo -e "\n${RED}[SteamCMD]: Cannot login to Steam - Improperly configured account and/or credentials${NC}"
            echo -e "\t${YELLOW}Please contact your administrator/host and give them the following message:${NC}"
            echo -e "\t${CYAN}Your Egg, or your client's server, is not configured with valid Steam credentials.${NC}"
            echo -e "\t${CYAN}Either the username/password is wrong, or Steam Guard is not fully disabled${NC}"
            echo -e "\t${CYAN}in accordance to this Egg's documentation/README.${NC}\n"
            exit 1
        elif [[ -n $(grep -i "Download item" "${STEAMCMD_LOG}") ]]; then # Steam account does not own base game for mod downloads, or unknown
            echo -e "\n${RED}[SteamCMD]: Unknown Steam Workshop mod download error${NC}"
            echo -e "\t${YELLOW}While unknown, this error may be due to your host's Steam account not owning the base game.${NC}"
            echo -e "\t${YELLOW}(Please contact your administrator/host if this issue persists)${NC}\n"
            exit 1
        elif [[ -n $(grep -i "0x202\|0x212" "${STEAMCMD_LOG}") ]]; then # Not enough disk space
            echo -e "\n${RED}[SteamCMD]: Unable to complete download - Not enough storage${NC}"
            echo -e "\t${YELLOW}You have run out of your allotted disk space.${NC}"
            echo -e "\t${YELLOW}Please contact your administrator/host for potential storage upgrades.${NC}\n"
            exit 1
        elif [[ -n $(grep -i "0x606" "${STEAMCMD_LOG}") ]]; then # Disk write failure
            echo -e "\n${RED}[SteamCMD]: Unable to complete download - Disk write failure${NC}"
            echo -e "\t${YELLOW}This is normally caused by directory permissions issues,${NC}"
            echo -e "\t${YELLOW}but could be a more serious hardware issue.${NC}"
            echo -e "\t${YELLOW}(Please contact your administrator/host if this issue persists)${NC}\n"
            exit 1
        else # Unknown caught error
            echo -e "\n${RED}[SteamCMD]: ${YELLOW}An unknown error has occurred with SteamCMD.${NC}"
            echo -e "SteamCMD Errors:\n${loggedErrors}"
            echo -e "\t${YELLOW}(Please contact your administrator/host if this issue persists)${NC}\n"
            exit 1
        fi
    elif [[ $steamcmdExitCode != 0 ]]; then # Unknown fatal error
        echo -e "\n${RED}[UPDATE]: SteamCMD has crashed for an unknown reason!${NC} (Exit code: ${CYAN}${steamcmdExitCode}${NC})"
        echo -e "\t${YELLOW}(Please contact your administrator/host for support)${NC}\n"
        cp -r /tmp/dumps ./dumps
        exit $steamcmdExitCode
    else # Success!
        break
    fi
    
    # Notify if failed last attempt
    if (( $updateAttempt == $attempts )); then
        echo -e "\t${RED}Final attempt made! ${YELLOW}Unable to complete mod download/update. ${CYAN}Skipping...${NC}"
        echo -e "\t(You may try again later, or manually upload files to your server via SFTP)"
        exit 1
    fi
done

echo -e "\n${GREEN}[SteamCMD]: Update check complete!${NC}"
exit 0