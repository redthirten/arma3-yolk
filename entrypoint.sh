#!/bin/bash

## File: Arma 3 Yolk Entrypoint - entrypoint.sh
## Author: David Wolfe (Red-Thirten)
## Contributors: Aussie Server Hosts (https://aussieserverhosts.com/), Stephen White (SilK)
## Date: 2025/03/20
## License: MIT License

## === CONSTANTS ===
STEAMCMD_DIR="./steamcmd"                 # SteamCMD's directory containing steamcmd.sh
WORKSHOP_DIR="./Steam/steamapps/workshop" # SteamCMD's directory containing workshop downloads
STEAMCMD_LOG="${STEAMCMD_DIR}/steamcmd.log"     # Log file for SteamCMD
GAME_ID=107410                                  # SteamCMD ID for the Arma 3 GAME (not server). Only used for Workshop mod downloads.
EGG_URL='https://github.com/parkervcp/eggs/tree/master/game_eggs/steamcmd_servers/arma/arma3'   # URL for Pterodactyl Egg & Info (only used as info to legacy users)

# Color Codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

## === ENVIRONMENT VARS ===
# STARTUP, STARTUP_PARAMS, STEAM_USER, STEAM_PASS, SERVER_BINARY, MOD_FILE, MODIFICATIONS, SERVERMODS, OPTIONALMODS, UPDATE_SERVER,
# CLEAR_CACHE, VALIDATE_SERVER, MODS_LOWERCASE, PROFILING_BRANCH, CDLC, STEAMCMD_APPID, HC_NUM, SERVER_PASSWORD, HC_HIDE, STEAMCMD_ATTEMPTS, BASIC_URL

## === GLOBAL VARS ===
# validateServer, betaBranch, updateAttempt, modifiedStartup, allMods, clientMods

## === DEFINE FUNCTIONS ===

# Runs SteamCMD with specified variables and performs error handling.
function RunSteamCMD { #[Input: int server=0 mod=1 optional_mod=2; int id]
    # Clear previous SteamCMD log
    if [[ -f "${STEAMCMD_LOG}" ]]; then
        rm -f "${STEAMCMD_LOG:?}"
    fi

    updateAttempt=0
    # Loop for specified number of attempts
    while (( $updateAttempt < $STEAMCMD_ATTEMPTS )); do
        # Increment attempt counter
        updateAttempt=$((updateAttempt+1))

        # Notify if not first attempt
        if (( $updateAttempt > 1 )); then
            echo -e "\t${YELLOW}Re-Attempting download/update in 3 seconds...${NC} (Attempt ${CYAN}${updateAttempt}${NC} of ${CYAN}${STEAMCMD_ATTEMPTS}${NC})\n"
            sleep 3
        fi

        # Check if updating server or mod
        if [[ $1 == 0 ]]; then # Server
            # numactl --physcpubind=+0 ${steamcmdDir}/steamcmd.sh +force_install_dir /home/container "+login \"${STEAM_USER}\" \"${STEAM_PASS}\"" +app_update $2 $betaBranch $validateServer +quit | tee -a "${steamcmdLog}"
            ${steamcmdDir}/steamcmd.sh +force_install_dir ./ "+login \"${STEAM_USER}\" \"${STEAM_PASS}\"" +app_update $2 ${betaBranch} ${validateServer} +quit | tee -a "${steamcmdLog}"
        else # Mod
            # numactl --physcpubind=+0 ${steamcmdDir}/steamcmd.sh "+login \"${STEAM_USER}\" \"${STEAM_PASS}\"" +workshop_download_item $GAME_ID $2 +quit | tee -a "${steamcmdLog}"
            ${steamcmdDir}/steamcmd.sh "+login \"${STEAM_USER}\" \"${STEAM_PASS}\"" +workshop_download_item ${GAME_ID} $2 +quit | tee -a "${steamcmdLog}"
        fi

        # Error checking for SteamCMD
        steamcmdExitCode=${PIPESTATUS[0]}
        loggedErrors=$(grep -i "error\|failed" "${steamcmdLog}" | grep -iv "setlocal\|SDL\|steamservice\|thread\|libcurl")
        if [[ -n ${loggedErrors} ]]; then # Catch errors (ignore setlocale, SDL, steamservice, thread priority, and libcurl warnings)
            # Soft errors
            if [[ -n $(grep -i "Timeout downloading item" "${STEAMCMD_LOG}") ]]; then # Mod download timeout
                echo -e "\n${YELLOW}[UPDATE]: ${NC}Timeout downloading Steam Workshop mod: \"${CYAN}${modName}${NC}\" (${CYAN}${2}${NC})"
                echo -e "\t(This is expected for particularly large mods)"
            elif [[ -n $(grep -i "0x402\|0x6\|0x602" "${STEAMCMD_LOG}") ]]; then # Connection issue with Steam
                echo -e "\n${YELLOW}[UPDATE]: ${NC}Connection issue with Steam servers."
                echo -e "\t(Steam servers may currently be down, or a connection cannot be made reliably)"
            # Hard errors
            elif [[ -n $(grep -i "Password check for AppId" "${STEAMCMD_LOG}") ]]; then # Incorrect beta branch password
                echo -e "\n${RED}[UPDATE]: ${YELLOW}Incorrect password given for beta branch \"${betaBranch}\". ${CYAN}Skipping download...${NC}"
                echo -e "\t(Please contact the maintainer of this image; an update may be required)"
                break
            # Fatal errors
            elif [[ -n $(grep -i "Invalid Password\|two-factor\|No subscription" "${STEAMCMD_LOG}") ]]; then # Wrong username/password, Steam Guard is turned on, or host is using anonymous account
                echo -e "\n${RED}[UPDATE]: Cannot login to Steam - Improperly configured account and/or credentials"
                echo -e "\t${YELLOW}Please contact your administrator/host and give them the following message:${NC}"
                echo -e "\t${CYAN}Your Egg, or your client's server, is not configured with valid Steam credentials.${NC}"
                echo -e "\t${CYAN}Either the username/password is wrong, or Steam Guard is not fully disabled"
                echo -e "\t${CYAN}in accordance to this Egg's documentation/README.${NC}\n"
                exit 1
            elif [[ -n $(grep -i "Download item" "${STEAMCMD_LOG}") ]]; then # Steam account does not own base game for mod downloads, or unknown
                echo -e "\n${RED}[UPDATE]: Cannot download mod - Download failed"
                echo -e "\t${YELLOW}While unknown, this error is likely due to your host's Steam account not owning the base game.${NC}"
                echo -e "\t${YELLOW}(Please contact your administrator/host if this issue persists)${NC}\n"
                exit 1
            elif [[ -n $(grep -i "0x202\|0x212" "${STEAMCMD_LOG}") ]]; then # Not enough disk space
                echo -e "\n${RED}[UPDATE]: Unable to complete download - Not enough storage"
                echo -e "\t${YELLOW}You have run out of your allotted disk space.${NC}"
                echo -e "\t${YELLOW}Please contact your administrator/host for potential storage upgrades.${NC}\n"
                exit 1
            elif [[ -n $(grep -i "0x606" "${STEAMCMD_LOG}") ]]; then # Disk write failure
                echo -e "\n${RED}[UPDATE]: Unable to complete download - Disk write failure"
                echo -e "\t${YELLOW}This is normally caused by directory permissions issues,"
                echo -e "\t${YELLOW}but could be a more serious hardware issue.${NC}"
                echo -e "\t${YELLOW}(Please contact your administrator/host if this issue persists)${NC}\n"
                exit 1
            else # Unknown caught error
                echo -e "\n${RED}[UPDATE]: ${YELLOW}An unknown error has occurred with SteamCMD. ${CYAN}Skipping download...${NC}"
                echo -e "SteamCMD Errors:\n${loggedErrors}"
                echo -e "\t${YELLOW}(Please contact your administrator/host if this issue persists)${NC}\n"
                break
            fi
        elif [[ $steamcmdExitCode != 0 ]]; then # Unknown fatal error
            echo -e "\n${RED}[UPDATE]: SteamCMD has crashed for an unknown reason!${NC} (Exit code: ${CYAN}${steamcmdExitCode}${NC})"
            echo -e "\t${YELLOW}(Please contact your administrator/host for support)${NC}\n"
            cp -r /tmp/dumps ./dumps
            exit $steamcmdExitCode
        else # Success!
            if [[ $1 == 0 ]]; then # Server
                echo -e "\n${GREEN}[UPDATE]: Game server is up to date!${NC}"
            else # Mod
                echo -e "\tMoving any mod ${CYAN}.bikey${NC} files to the ${CYAN}keys/${NC} folder..."
                if [[ $1 == 1 ]]; then # Regular mod
                    # Move any .bikey's to the keys directory
                    find "${WORKSHOP_DIR}/content/${GAME_ID}/$2" -name "*.bikey" -type f -exec cp -t "keys" {} +
                    # Make a hard link copy of the downloaded mod to the current directory if it doesn't already exist
                    echo -e "\tMaking ${CYAN}hard link${NC} copy of mod to ${CYAN}$(pwd)@$2${NC}"
                    if [[ ! -d "@$2" ]]; then
                        mkdir @$2
                        cp -al ${WORKSHOP_DIR}/content/${GAME_ID}/$2/* @$2/
                    fi
                    # Make the hard link copy's contents all lowercase
                    # (This complies with Arma's mod-folder rules while not disturbing the mod's SteamCMD source files)
                    ModsLowercase @$2
                elif [[ $1 == 2 ]]; then # Optional mod
                    # Give optional mod keys a custom name during move which can be checked later for deleting un-configured mods
                    for file in $(find "${WORKSHOP_DIR}/content/${GAME_ID}/$2" -name "*.bikey" -type f); do
                        filename=$(basename ${file})
                        cp $file keys/optional_$2_${filename}
                    done;
                    # Delete mod folder to save space
                    echo -e "\tMod is an ${CYAN}optional mod${NC}. Deleting mod files to save space..."
                    rm -r ${WORKSHOP_DIR}/content/${GAME_ID}/$2
                    # Create a directory so time-based detection of auto updates works correctly
                    mkdir @${2}_optional
                    touch "DON'T DELETE THIS DIRECTORY - USED FOR AUTO UPDATES"
                fi
                echo -e "${GREEN}[UPDATE]: Mod download/update successful!${NC}"
            fi
            break
        fi
        if (( $updateAttempt == $STEAMCMD_ATTEMPTS )); then # Notify if failed last attempt
            if [[ $1 == 0 ]]; then # Server
                echo -e "\t${RED}Final attempt made! ${YELLOW}Unable to complete game server update. ${CYAN}Skipping...${NC}"
                echo -e "\t(Please try again at a later time)"
                sleep 3
            else # Mod
                echo -e "\t${RED}Final attempt made! ${YELLOW}Unable to complete mod download/update. ${CYAN}Skipping...${NC}"
                echo -e "\t(You may try again later, or manually upload this mod to your server via SFTP)"
                sleep 3
            fi
        fi
    done
}

# Takes a directory (string) as input, and recursively makes all files & folders lowercase.
function ModsLowercase {
    echo -e "\n\tMaking mod ${CYAN}$1${NC} files/folders lowercase..."
    for SRC in `find ./$1 -depth`; do
        DST=`dirname "${SRC}"`/`basename "${SRC}" | tr '[A-Z]' '[a-z]'`
        if [ "${SRC}" != "${DST}" ]
        then
            [ ! -e "${DST}" ] && mv -T "${SRC}" "${DST}"
        fi
    done
}

# Removes duplicate items from a semicolon delimited string
function RemoveDuplicates { #[Input: str - Output: printf of new str]
    if [[ -n $1 ]]; then # If nothing to compare, skip to prevent extra semicolon being returned
        echo $1 | sed -e 's/;/\n/g' | sort -u | xargs printf '%s;'
    fi
}

## === ENTRYPOINT START ===

# Wait for the container to fully initialize
sleep 1

# Switch to the container's working directory
cd ${HOME} || exit 1

# Check for old Eggs
if [[ -z ${PROFILING_BRANCH} ]]; then # PROFILING_BRANCH was not in the previous version
    echo -e "\n${RED}[STARTUP_ERR]: Please contact your administrator/host for support, and give them the following message:${NC}\n"
    echo -e "\t${CYAN}Your Arma 3 Egg is outdated and no longer supported.${NC}"
    echo -e "\t${CYAN}Please download the latest version at the following link, and install it in your panel:${NC}"
    echo -e "\t${CYAN}${EGG_URL}${NC}\n"
    exit 1
fi

# Collect and parse all specified mods
if [[ -n ${MODIFICATIONS} ]] && [[ ${MODIFICATIONS} != *\; ]]; then # Add manually specified mods to the client-side mods list, while checking for trailing semicolon
    clientMods="${MODIFICATIONS};"
else
    clientMods=${MODIFICATIONS}
fi
if [[ -f ${MOD_FILE} ]] && [[ -n "$(cat ${MOD_FILE} | grep 'Created by Arma 3 Launcher')" ]]; then # If the mod list file exists and is valid, parse and add mods to the client-side mods list
    clientMods+=$(cat ${MOD_FILE} | grep 'id=' | cut -d'=' -f3 | cut -d'"' -f1 | xargs printf '@%s;')
elif [[ -n "${MOD_FILE}" ]]; then # If MOD_FILE is not null, warn user file is missing or invalid
    echo -e "\n${YELLOW}[STARTUP_WARN]: Arma 3 Modlist file \"${CYAN}${MOD_FILE}${YELLOW}\" could not be found, or is invalid!${NC}"
    echo -e "\tEnsure your uploaded modlist's file name matches your Startup Parameter."
    echo -e "\tOnly files exported from an Arma 3 Launcher are permitted."
    if [[ -n "${clientMods}" ]]; then
        echo -e "\t${CYAN}Reverting to the manual mod list...${NC}"
    fi
fi
if [[ -n ${SERVERMODS} ]] && [[ ${SERVERMODS} != *\; ]]; then # Add server mods to the master mods list, while checking for trailing semicolon
    allMods="${SERVERMODS};"
else
    allMods=${SERVERMODS}
fi
if [[ -n ${OPTIONALMODS} ]] && [[ ${OPTIONALMODS} != *\; ]]; then # Add specified optional mods to the mods list, while checking for trailing semicolon
    allMods+="${OPTIONALMODS};"
else
    allMods+=${OPTIONALMODS}
fi
allMods+=$clientMods # Add all client-side mods to the master mod list
clientMods=$(RemoveDuplicates ${clientMods}) # Remove duplicate mods from clientMods, if present
allMods=$(RemoveDuplicates ${allMods}) # Remove duplicate mods from allMods, if present
allMods=$(echo $allMods | sed -e 's/;/ /g') # Convert from string to array

# Update everything (server and mods), if specified
if [[ ${UPDATE_SERVER} == 1 ]]; then
    echo -e "\n${GREEN}[STARTUP]: ${CYAN}Starting checks for all updates...${NC}"
    echo -e "(It is okay to ignore any \"SDL\", \"steamservice\", and \"thread priority\" errors during this process)\n"

    ## Update game server
    echo -e "${GREEN}[UPDATE]:${NC} Checking for game server updates with App ID: ${CYAN}${STEAMCMD_APPID}${NC}..."

    # Validate will be added as a parameter if specified
    if [[ ${VALIDATE_SERVER} == 1 ]]; then
        echo -e "\t${CYAN}File validation enabled.${NC} (This may take extra time to complete)"
        validateServer="validate"
    else
        validateServer=""
    fi

    # Determine what beta branch should be set, if any
    if [[ ${PROFILING_BRANCH} == 1 ]]; then
        echo -e "\t${CYAN}Download/Update server profiling branch enabled.${NC}\n"
        betaBranch="-beta profiling"
    elif [[ ${CDLC} == 1 ]]; then
        echo -e "\t${CYAN}Download/Update Creator DLC server files enabled.${NC}\n"
        betaBranch="-beta creatordlc"
    else
        echo -e ""
        betaBranch=""
    fi

    RunSteamCMD 0 ${STEAMCMD_APPID}

    ## Update mods
    if [[ -n $allMods ]]; then
        echo -e "\n${GREEN}[UPDATE]:${NC} Checking all ${CYAN}Steam Workshop mods${NC} for updates..."
        for modID in $(echo $allMods | sed -e 's/@//g'); do
            if [[ $modID =~ ^[0-9]+$ ]]; then # Only check mods that are in ID-form
                # If a mod is defined in OPTIONALMODS, and is not defined in clientMods or SERVERMODS, then treat as an optional mod
                # Optional mods are given a different directory which is checked to see if a new update is available. This is to ensure
                # if an optional mod is switched to be a standard client-side mod, this script will redownload the mod
                if [[ "${OPTIONALMODS}" == *"@${modID};"* ]] && [[ "${clientMods}" != *"@${modID};"* ]] && [[ "${SERVERMODS}" != *"@${modID};"* ]]; then
                    modType=2
                    modDir=@${modID}_optional
                else
                    modType=1
                    modDir=@${modID}
                fi

                # Get mod's latest update in epoch time from its Steam Workshop changelog page
                latestUpdate=$(curl -sL https://steamcommunity.com/sharedfiles/filedetails/changelog/$modID | grep '<p id=' | head -1 | cut -d'"' -f2)

                # If the update time is valid and newer than the local directory's creation date, or the mod hasn't been downloaded yet, download the mod
                # if [[ ! -d $modDir ]] || [[ ( -n $latestUpdate ) && ( $latestUpdate =~ ^[0-9]+$ ) && ( $latestUpdate > $(find $modDir | head -1 | xargs stat -c%Y) ) ]]; then
                    # Get the mod's name from the Workshop page as well
                    modName=$(curl -sL https://steamcommunity.com/sharedfiles/filedetails/changelog/$modID | grep 'workshopItemTitle' | cut -d'>' -f2 | cut -d'<' -f1)
                    if [[ -z $modName ]]; then # Set default name if unavailable
                        modName="[NAME UNAVAILABLE]"
                    fi
                    if [[ ! -d $modDir ]]; then
                        echo -e "\n${GREEN}[UPDATE]:${NC} Downloading new Mod: \"${CYAN}${modName}${NC}\" (${CYAN}${modID}${NC})"
                    else
                        echo -e "\n${GREEN}[UPDATE]:${NC} Mod update found for: \"${CYAN}${modName}${NC}\" (${CYAN}${modID}${NC})"
                    fi
                    if [[ -n $latestUpdate ]] && [[ $latestUpdate =~ ^[0-9]+$ ]]; then # Notify last update date, if valid
                        echo -e "\tMod was last updated: ${CYAN}$(date -d @${latestUpdate})${NC}"
                    fi
                    
                    echo -e "\tAttempting mod update/download via SteamCMD...\n"
                    RunSteamCMD $modType $modID
                # fi
            fi
        done

        # Check over key files for un-configured optional mods' .bikey files
        for keyFile in $(find "keys" -name "*.bikey" -type f); do
            keyFileName=$(basename ${keyFile})

            # If the key file is using the optional mod file name
            if [[ "${keyFileName}" == "optional_"* ]]; then
                modID=$(echo "${keyFileName}" | cut -d _ -f 2)

                # If mod is not in optional mods, delete it
                # If a mod is configured in clientMods or SERVERMODS, we should still delete this file
                # as a new file will have been copied that does not follow the naming scheme
                if [[ "${OPTIONALMODS}" != *"@${modID};"* ]]; then

                    # We only need to let the user know the key file is being deleted if this mod is no longer configured at all.
                    # If clientMods contains the mod ID, we'd just confuse the user by telling them we are deleting the optional .bikey file
                    if [[ "${clientMods}" != *"@${modID};"* ]]; then
                        echo -e "\tKey file and directory for un-configured optional mod ${CYAN}${modID}${NC} is being deleted..."
                    fi

                    # Delete the optional mod .bikey file and directory
                    rm ${keyFile}
                    rm -r @${modID}_optional
                fi
            fi
        done;

        echo -e "${GREEN}[UPDATE]:${NC} Steam Workshop mod update check ${GREEN}complete${NC}!"
    fi
fi

# Check if specified server binary exists.
if [[ ! -f ${SERVER_BINARY} ]]; then
    echo -e "\n${RED}[STARTUP_ERR]: Specified Arma 3 server binary could not be found in `$(pwd)`!${NC}"
    echo -e "${YELLOW}Please do the following to resolve this issue:${NC}"
    echo -e "\t${CYAN}- Double check your \"Server Binary\" Startup Variable is correct.${NC}"
    echo -e "\t${CYAN}- Ensure your server has properly installed/updated without errors (reinstalling/updating again may help).${NC}"
    echo -e "\t${CYAN}- Use the File Manager to check that your specified server binary file is not missing from `$(pwd)`.${NC}\n"
    exit 1
fi

# Make mods lowercase, if specified
if [[ ${MODS_LOWERCASE} == "1" ]]; then
    for modDir in $allMods; do
        ModsLowercase $modDir
    done
fi

# Define the log file path with a timestamp
# LOG_FILE="/home/container/serverprofile/rpt/arma3server_$(date '+%m_%d_%Y_%H%M%S').rpt"
# Ensure the logs directory exists
# mkdir -p /home/container/serverprofile/rpt

# Clear HC cache, if specified
# if [[ ${CLEAR_CACHE} == "1" ]]; then
#     echo -e "\n${GREEN}[STARTUP]: ${CYAN}Clearing Headless Client profiles cache...${NC}"
#     for profileDir in ./serverprofile/home/*; do
#         [ "$profileDir" = "./serverprofile/home/Player" ] && continue
#         rm -rf $profileDir
#     done
# fi

# Check if basic.cfg exists, and download if not (Arma really doesn't like it missing for some reason)
if [[ ! -f basic.cfg ]]; then
    echo -e "\n${YELLOW}[STARTUP_WARN]: Basic Network Configuration file \"${CYAN}basic.cfg${YELLOW}\" is missing!${NC}"
    echo -e "\t${YELLOW}Downloading default file for use instead...${NC}"
    curl -sSL ${BASIC_URL} -o ./basic.cfg
fi

# Setup NSS Wrapper for use ($NSS_WRAPPER_PASSWD and $NSS_WRAPPER_GROUP have been set by the Dockerfile)
export USER_ID=$(id -u)
export GROUP_ID=$(id -g)
envsubst < /passwd.template > ${NSS_WRAPPER_PASSWD}

if [[ ${SERVER_BINARY} == *"x64"* ]]; then # Check which libnss-wrapper architecture to run, based off the server binary name
    export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libnss_wrapper.so
else
    export LD_PRELOAD=/usr/lib/i386-linux-gnu/libnss_wrapper.so
fi

# Replace Startup Variables
modifiedStartup=`eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')`

# Start Headless Clients if applicable
if [[ ${HC_NUM} > 0 ]]; then
    echo -e "\n${GREEN}[STARTUP]:${NC} Starting ${CYAN}${HC_NUM}${NC} Headless Client(s)."
    for i in $(seq ${HC_NUM}); do
        if [[ ${HC_HIDE} == "1" ]]; then
            ./${SERVER_BINARY} -client -connect=127.0.0.1 -port=${SERVER_PORT} -password="${SERVER_PASSWORD}" -profiles=./serverprofile -bepath=./battleye -mod="${clientMods}" ${STARTUP_PARAMS} > /dev/null 2>&1 &
        else
            ./${SERVER_BINARY} -client -connect=127.0.0.1 -port=${SERVER_PORT} -password="${SERVER_PASSWORD}" -profiles=./serverprofile -bepath=./battleye -mod="${clientMods}" ${STARTUP_PARAMS} &
        fi
        echo -e "${GREEN}[STARTUP]:${CYAN} Headless Client $i${NC} launched."
    done
fi

# Start the Server
echo -e "\n${GREEN}[STARTUP]:${NC} Starting server with the following startup command:"
echo -e "${CYAN}${modifiedStartup}${NC}\n"
sleep 10 #DEBUG
exit 1
if [[ "$STARTUP_PARAMS" == *"-noLogs"* ]]; then
    ${modifiedStartup}
else
    ${modifiedStartup} 2>&1 | tee -a "$LOG_FILE"
fi

if [ $? -ne 0 ]; then
    echo -e "\n${RED}PTDL_CONTAINER_ERR: There was an error while attempting to run the start command.${NC}\n"
    exit 1
fi
