#!/bin/bash

# eReader Deployment Script
# This script deploys the eReader plugin and related files to your Kobo or Kindle device. On kobo devices it alsosets up the eReader menu item in the Nickle menu.

set -e

# Cross-platform color support detection
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  # Check if terminal supports colors
  ncolors=$(tput colors)
  if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
  else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
  fi
else
  # No color support
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

# Configuration
PLUGIN_SOURCE="plugins/ereader.koplugin"

# Additional files to copy (source -> destination relative to KOReader root)
KOREADER_BASE_FILES=(
  "frontend/ui/elements/filemanager_menu_order.lua"
  "frontend/ui/elements/reader_menu_order.lua"
  "frontend/ui/widget/menu.lua"
  "resources/icons/mdlight/wifi.off.svg"
  "resources/icons/mdlight/brightness.svg"
  "resources/icons/mdlight/rotation.auto.svg"
  "resources/icons/mdlight/rotation.lock.portrait.svg"
  "resources/icons/mdlight/rotation.lock.landscape.svg"
  "reader.lua"
)

echo -e "${GREEN}eReader Deployment Script${NC}"
echo "================================================"

# Check if plugin source exists
if [ ! -d "$PLUGIN_SOURCE" ]; then
  echo -e "${RED}Error: Plugin source directory not found: $PLUGIN_SOURCE${NC}"
  echo "Make sure you're running this script from the KOReader root directory"
  exit 1
fi

# Cross-platform device detection
PLATFORM="$(uname -s)"
DEVICE_MOUNTPOINT=""
DEVICE_TYPE=""
DEVICE_PLATFORM=""

if [ -e "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then
  PLATFORM='WSL'
fi

# Helper function to find PowerShell executable
find_powershell() {
  local POWERSHELL_EXEC='powershell'
  if ! command -v "${POWERSHELL_EXEC}" >/dev/null 2>&1; then
    if command -v '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' >/dev/null 2>&1; then
      POWERSHELL_EXEC='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
    elif command -v '/cygdrive/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' >/dev/null 2>&1; then
      POWERSHELL_EXEC='/cygdrive/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
    elif command -v '/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' >/dev/null 2>&1; then
      POWERSHELL_EXEC='/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
    else
      echo -e "${RED}Error: powershell executable not in path; please make powershell available.${NC}"
      exit 1
    fi
  fi
  echo "$POWERSHELL_EXEC"
}

# Helper function to handle WSL mounting
handle_wsl_mount() {
  local drive_letter="$1"
  local device_name="$2"
  local mountpoint="/mnt/${drive_letter}"
  
  local wsl_mount=$(findmnt -S "${drive_letter}:" -t 9p -nlo TARGET | head -1)
  if [[ -z "${wsl_mount}" ]]; then
    echo -e "${YELLOW}${device_name} device appears to be Windows drive ${drive_letter} which is not mounted in WSL. We can try to attempt to mount it if you like. This may require administrator privileges.${NC}"
    while true; do 
      read -p "Do you want to mount the ${device_name} device in WSL? (yes/no): " yn
      case $yn in
        [Yy]* ) 
          if [ ! -d "${mountpoint}" ]; then
            echo "Creating mountpoint ${mountpoint}..."
            if ! mkdir -m=777 -p "${mountpoint}" >/dev/null 2>&1; then
              sudo mkdir -m=777 -p "${mountpoint}" 
            fi
          fi
          if [ ! -d "${mountpoint}" ]; then
              echo -e "${RED}Unable to access mount point ${mountpoint}. Exiting.${NC}"
              exit 1
          fi
          echo "Mounting ${drive_letter}..."
          if ! mount "${drive_letter}:" "${mountpoint}" -t drvfs >/dev/null 2>&1; then
            if ! sudo mount "${drive_letter}:" "${mountpoint}" -t drvfs; then
              echo -e "${RED}Unable to mount ${drive_letter}: on ${mountpoint}. Exiting.${NC}"
              exit 1
            fi
          fi
          # set flag to unmount device at end of process
          UNMOUNT=1
          break
          ;;
        [Nn]* ) echo "Exiting..."; exit;;
        * ) 
          echo -e "${RED}Invalid input. Please answer yes or no.${NC}"
          ;;
      esac
    done
  fi
}

# Helper function to find device drive in Windows
find_device_drive() {
  local device_label="$1"
  local powershell_exec="$2"
  
  local drive_letter=$("${powershell_exec}" -c "(Get-Volume -FileSystemLabel \"${device_label}\" -ErrorAction SilentlyContinue | Select-Object DriveLetter).DriveLetter ")
  drive_letter="${drive_letter:0:1}"
  drive_letter="${drive_letter,,}"
  echo "$drive_letter"
}

# Helper function to validate device mountpoint
validate_device_mountpoint() {
  local mountpoint="$1"
  local device_type="$2"
  
  if [ "$device_type" = "kobo" ]; then
    # Check for .kobo directory
    for test_mountpoint in /mnt/ /cygdrive/ /; do
      local test_path="${test_mountpoint}${mountpoint}/"
      if [ -d "${test_path}.kobo" ]; then
        echo "$test_path"
        return 0
      fi
    done
  elif [ "$device_type" = "kindle" ]; then
    # Check for koreader directory
    for test_mountpoint in /mnt/ /cygdrive/ /; do
      local test_path="${test_mountpoint}${mountpoint}/"
      if [ -d "${test_path}/koreader" ]; then
        echo "$test_path"
        return 0
      fi
    done
  fi
  
  return 1
}

# Function to detect device type and mountpoint
detect_device() {
  case "${PLATFORM}" in
    "Linux" )
      # Use findmnt, it's in util-linux, which should be present in every sane distro.
      if ! command -v findmnt >/dev/null 2>&1; then
        echo -e "${RED}Error: This script relies on findmnt, from util-linux!${NC}"
        echo "Please install util-linux package for your distribution."
        exit 1
      fi

      # Try to find Kobo device first
      DEVICE_MOUNTPOINT="$(findmnt -nlo TARGET LABEL=KOBOeReader 2>/dev/null || true)"
      if [ -n "$DEVICE_MOUNTPOINT" ]; then
        DEVICE_TYPE="kobo"
        DEVICE_PLATFORM="kobo"
        return 0
      fi

      # Try to find Kindle device
      DEVICE_MOUNTPOINT="$(findmnt -nlo TARGET LABEL=Kindle 2>/dev/null || true)"
      if [ -n "$DEVICE_MOUNTPOINT" ]; then
        DEVICE_TYPE="kindle"
        DEVICE_PLATFORM="kindle"
        return 0
      fi
      ;;
    "Darwin" )
      # Same idea, via diskutil
      if ! command -v diskutil >/dev/null 2>&1; then
        echo -e "${RED}Error: diskutil command not found!${NC}"
        exit 1
      fi
      
      # Try to find Kobo device first
      DEVICE_MOUNTPOINT="$(diskutil info -plist "KOBOeReader" 2>/dev/null | grep -A1 "MountPoint" | tail -n 1 | cut -d'>' -f2 | cut -d'<' -f1 || true)"
      if [ -n "$DEVICE_MOUNTPOINT" ]; then
        DEVICE_TYPE="kobo"
        DEVICE_PLATFORM="kobo"
        return 0
      fi

      # Try to find Kindle device
      DEVICE_MOUNTPOINT="$(diskutil info -plist "Kindle" 2>/dev/null | grep -A1 "MountPoint" | tail -n 1 | cut -d'>' -f2 | cut -d'<' -f1 || true)"
      if [ -n "$DEVICE_MOUNTPOINT" ]; then
        DEVICE_TYPE="kindle"
        DEVICE_PLATFORM="kindle"
        return 0
      fi
      ;;
    "MINGW"*|"MSYS"*|"CYGWIN"*|"WSL"* )
      # Find PowerShell executable
      local powershell_exec=$(find_powershell)
      
      # Try to find Kobo device first
      local kobo_drive=$(find_device_drive "KOBOeReader" "$powershell_exec")
      if [[ -n "${kobo_drive}" ]]; then
        if [ "${PLATFORM}" == "WSL" ]; then
          DEVICE_MOUNTPOINT="/mnt/${kobo_drive}"
          handle_wsl_mount "$kobo_drive" "Kobo"
        else
          DEVICE_MOUNTPOINT=$(validate_device_mountpoint "$kobo_drive" "kobo")
          if [ $? -ne 0 ]; then
            echo -e "${RED}Could not find drive ${kobo_drive} in this environment. Exiting.${NC}"
            exit 1
          fi
        fi
        DEVICE_TYPE="kobo"
        DEVICE_PLATFORM="kobo"
        return 0
      fi

      # Try to find Kindle device
      local kindle_drive=$(find_device_drive "Kindle" "$powershell_exec")
      if [[ -n "${kindle_drive}" ]]; then
        if [ "${PLATFORM}" == "WSL" ]; then
          DEVICE_MOUNTPOINT="/mnt/${kindle_drive}"
          handle_wsl_mount "$kindle_drive" "Kindle"
        else
          DEVICE_MOUNTPOINT=$(validate_device_mountpoint "$kindle_drive" "kindle")
          if [ $? -ne 0 ]; then
            echo -e "${RED}Could not find drive ${kindle_drive} in this environment. Exiting.${NC}"
            exit 1
          fi
        fi
        DEVICE_TYPE="kindle"
        DEVICE_PLATFORM="kindle"
        return 0
      fi
      ;;
    * )
      echo -e "${RED}Unsupported OS: ${PLATFORM}${NC}"
      exit 1
      ;;
  esac
  
  return 1
}

# Detect device
if ! detect_device; then
  echo -e "${RED}Error: Couldn't find a Kobo or Kindle eReader volume! Is one actually mounted?${NC}"
  exit 1
fi

# Validate device type and set paths
if [ "$DEVICE_TYPE" = "kobo" ]; then
  # Validate that this is actually a Kobo device
  KOBO_DIR="${DEVICE_MOUNTPOINT}/.kobo"
  if [[ ! -d "${KOBO_DIR}" ]] ; then
    echo -e "${RED}Error: Can't find a .kobo directory, ${DEVICE_MOUNTPOINT} doesn't appear to point to a Kobo eReader... Is one actually mounted?${NC}"
    exit 1
  fi
  DEVICE_PLUGIN_DIR="${DEVICE_MOUNTPOINT}/.adds/koreader/plugins"
  KOREADER_BASE_PATH="${DEVICE_MOUNTPOINT}/.adds/koreader"
  echo -e "${GREEN}Found Kobo device at: ${DEVICE_MOUNTPOINT}${NC}"
elif [ "$DEVICE_TYPE" = "kindle" ]; then
  # Validate that this is actually a Kindle device
  KINDLE_DIR="${DEVICE_MOUNTPOINT}/koreader"
  if [[ ! -d "${KINDLE_DIR}" ]] ; then
    echo -e "${YELLOW}KOReader directory not found on Kindle device. Creating it...${NC}"
    if ! mkdir -p "${KINDLE_DIR}"; then
      echo -e "${RED}Error: Failed to create KOReader directory on Kindle device!${NC}"
      exit 1
    fi
  fi
  DEVICE_PLUGIN_DIR="${DEVICE_MOUNTPOINT}/koreader/plugins"
  KOREADER_BASE_PATH="${DEVICE_MOUNTPOINT}/koreader"
  echo -e "${GREEN}Found Kindle device at: ${DEVICE_MOUNTPOINT}${NC}"
  
  # For Kindle, we need to determine the specific platform
  echo -e "${YELLOW}Please select your Kindle platform (for help identifying your Kindle, see https://wiki.mobileread.com/wiki/Kindle_Serial_Numbers):${NC}"
  echo "1) kobo (all Kobo devices)"
  echo "2) kindle-legacy (old Kindles with hardware keyboards)"
  echo "3) kindle (K4, K5 (KT), Paperwhite 1)"
  echo "4) kindlepw2 (All newer Kindles (starting with Paperwhite 2) running firmware <= 5.16.2)"
  echo "5) kindlehf (Any kindle running firmware >= 5.16.3)"

  
  while true; do
    read -p "Enter your choice (1-5): " choice
    case $choice in
      1) DEVICE_PLATFORM="kobo"; break;;
      2) DEVICE_PLATFORM="kindle-legacy"; break;;
      3) DEVICE_PLATFORM="kindle"; break;;
      4) DEVICE_PLATFORM="kindlepw2"; break;;
      5) DEVICE_PLATFORM="kindlehf"; break;;
      *) echo -e "${RED}Invalid choice. Please enter 1-5.${NC}";;
    esac
  done
else
  echo -e "${RED}Error: Unknown device type: $DEVICE_TYPE${NC}"
  exit 1
fi

# Check if KOReader plugins directory exists on device
if [ ! -d "$DEVICE_PLUGIN_DIR" ]; then
  echo -e "${YELLOW}Creating plugins directory on device...${NC}"
  if ! mkdir -p "$DEVICE_PLUGIN_DIR"; then
    echo -e "${RED}Error: Failed to create plugins directory on device!${NC}"
    exit 1
  fi
fi

# Copy plugin to device
echo -e "${GREEN}Copying plugin to device...${NC}"
if ! cp -r "$PLUGIN_SOURCE" "$DEVICE_PLUGIN_DIR/"; then
  echo -e "${RED}Error: Failed to copy plugin to device!${NC}"
  exit 1
fi

# Copy the appropriate instapapersecrets.so file for the platform
SECRETS_LIB_SOURCE="lib/secrets-store/instapapersecrets_${DEVICE_PLATFORM}.so"
SECRETS_LIB_DEST="$DEVICE_PLUGIN_DIR/ereader.koplugin/lib/instapapersecrets.so"

if [ ! -f "$SECRETS_LIB_SOURCE" ]; then
  echo -e "${RED}Error: Secrets library not found for platform ${DEVICE_PLATFORM}: $SECRETS_LIB_SOURCE${NC}"
  exit 1
fi

echo -e "${GREEN}Copying secrets library for ${DEVICE_PLATFORM}...${NC}"
if ! cp "$SECRETS_LIB_SOURCE" "$SECRETS_LIB_DEST"; then
  echo -e "${RED}Error: Failed to copy secrets library!${NC}"
  exit 1
fi

# Copy base files to device
for FILE in "${KOREADER_BASE_FILES[@]}"; do
  if [ ! -f "$FILE" ]; then
    echo -e "${YELLOW}Warning: Source file not found: $FILE${NC}"
    continue
  fi

  DEST="${KOREADER_BASE_PATH}/${FILE}"
  DEST_DIR="$(dirname "$DEST")"
  if [ ! -d "$DEST_DIR" ]; then
    echo -e "${YELLOW}Creating directory $DEST_DIR on device...${NC}"
    if ! mkdir -p "$DEST_DIR"; then
      echo -e "${RED}Error: Failed to create directory $DEST_DIR on device!${NC}"
      exit 1
    fi
  fi
  echo -e "${GREEN}Copying $FILE to device...${NC}"
  if ! cp "$FILE" "$DEST"; then
    echo -e "${RED}Error: Failed to copy $FILE to device!${NC}"
    exit 1
  fi
done

# Handle menu item creation based on device type
if [ "$DEVICE_TYPE" = "kobo" ]; then
  # Check for .adds/nm directory and create ereader menu item if needed
  NM_DIR="${DEVICE_MOUNTPOINT}/.adds/nm"
  NM_FILE="$NM_DIR/ereader"
  if [ -d "$NM_DIR" ]; then
    if [ ! -f "$NM_FILE" ]; then
      echo -e "${GREEN}Creating eReader menu item in $NM_DIR...${NC}"
      if ! cat > "$NM_FILE" <<EOF
menu_item : main : eReader : cmd_spawn : quiet : exec /mnt/onboard/.adds/koreader/koreader.sh -ereader
EOF
then
  echo -e "${RED}Error: Failed to create eReader menu item!${NC}"
  exit 1
      fi
    else
      echo -e "${YELLOW}eReader menu item already exists in $NM_DIR.${NC}"
    fi
  fi
elif [ "$DEVICE_TYPE" = "kindle" ]; then
  echo -e "${YELLOW}Note: For Kindle devices, you may need to manually add the eReader menu item to your launcher configuration.${NC}"
fi

# Set proper permissions (Unix-specific)
echo -e "${GREEN}Setting permissions...${NC}"
if command -v chmod >/dev/null 2>&1; then
  if ! chmod -R 755 "$DEVICE_PLUGIN_DIR/ereader.koplugin"; then
    echo -e "${YELLOW}Warning: Failed to set permissions on plugin directory${NC}"
  fi
else
  echo -e "${YELLOW}Warning: chmod not available, skipping permission setting${NC}"
fi

# Cross-platform device ejection
echo -e "${GREEN}Ejecting ${DEVICE_TYPE} device...${NC}"
case "${PLATFORM}" in
  "Linux" )
    # Try to unmount the device
    if command -v udisksctl >/dev/null 2>&1; then
      DEVICE_SOURCE="$(findmnt -nlo SOURCE "$DEVICE_MOUNTPOINT" 2>/dev/null || true)"
      if [ -n "$DEVICE_SOURCE" ]; then
        if ! udisksctl unmount -b "$DEVICE_SOURCE"; then
          echo -e "${YELLOW}Warning: udisksctl failed, trying umount...${NC}"
          if command -v umount >/dev/null 2>&1; then
            if ! umount "$DEVICE_MOUNTPOINT"; then
              echo -e "${YELLOW}Warning: Could not automatically eject device. Please eject manually.${NC}"
            fi
          else
            echo -e "${YELLOW}Warning: Could not automatically eject device. Please eject manually.${NC}"
          fi
        fi
      else
        echo -e "${YELLOW}Warning: Could not determine device source for ejection${NC}"
      fi
    elif command -v umount >/dev/null 2>&1; then
      if ! umount "$DEVICE_MOUNTPOINT"; then
        echo -e "${YELLOW}Warning: Could not automatically eject device. Please eject manually.${NC}"
      fi
    else
      echo -e "${YELLOW}Warning: Could not automatically eject device. Please eject manually.${NC}"
    fi
    ;;
  "Darwin" )
    if ! diskutil eject "$DEVICE_MOUNTPOINT"; then
      echo -e "${YELLOW}Warning: Could not automatically eject device. Please eject manually.${NC}"
    fi
    ;;
  "WSL"* )
    if [[ ! -z "${UNMOUNT}" ]]; then
      if ! sudo umount "${DEVICE_MOUNTPOINT}"; then
        echo -e "${YELLOW}Warning: Could not unmount device. Please eject manually.${NC}"
      fi
    fi
    ;;
esac

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Restart KOReader on your device"
if [ "$DEVICE_TYPE" = "kobo" ]; then
  echo "2. eReader should now be available in the Nickle menu item"
elif [ "$DEVICE_TYPE" = "kindle" ]; then
  echo "2. eReader should now be available in your Kindle launcher"
fi
