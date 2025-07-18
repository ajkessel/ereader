#!/bin/bash

# KOReader eReader Deployment Script
# This script eReader plugin and related files to your Kobo device and sets up the eReader menu item in the Nickle menu.

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
  "reader.lua"
)

echo -e "${GREEN}KOReader eReader Plugin Deployment Script${NC}"
echo "================================================"

# Check if plugin source exists
if [ ! -d "$PLUGIN_SOURCE" ]; then
  echo -e "${RED}Error: Plugin source directory not found: $PLUGIN_SOURCE${NC}"
  echo "Make sure you're running this script from the KOReader root directory"
  exit 1
fi

# Cross-platform Kobo volume detection
PLATFORM="$(uname -s)"
KOBO_MOUNTPOINT=""

if [ -e "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then
  PLATFORM='WSL'
fi

case "${PLATFORM}" in
  "Linux" )
    # Use findmnt, it's in util-linux, which should be present in every sane distro.
    if ! command -v findmnt >/dev/null 2>&1; then
      echo -e "${RED}Error: This script relies on findmnt, from util-linux!${NC}"
      echo "Please install util-linux package for your distribution."
      exit 1
    fi

        # Match on the FS Label, which is common to all models.
        KOBO_MOUNTPOINT="$(findmnt -nlo TARGET LABEL=KOBOeReader 2>/dev/null || true)"
        ;;
      "Darwin" )
        # Same idea, via diskutil
        if ! command -v diskutil >/dev/null 2>&1; then
          echo -e "${RED}Error: diskutil command not found!${NC}"
          exit 1
        fi
        KOBO_MOUNTPOINT="$(diskutil info -plist "KOBOeReader" 2>/dev/null | grep -A1 "MountPoint" | tail -n 1 | cut -d'>' -f2 | cut -d'<' -f1 || true)"
        ;;
      "MINGW"*|"MSYS"*|"CYGWIN"*|"WSL"* )
        # simplistic algorithm for finding powershell executable in Windows
        # TODO: support drives other than c: and potentially other versions of PowersHell
        POWERSHELL_EXEC='powershell'
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
        KOBO_DRIVE=$("${POWERSHELL_EXEC}" -c '(Get-Volume  -FileSystemLabel "KOBOeReader" -ErrorAction SilentlyContinue | Select-Object DriveLetter).DriveLetter ')
        KOBO_DRIVE="${KOBO_DRIVE:0:1}"
        KOBO_DRIVE="${KOBO_DRIVE,,}"
        if [[ -z "${KOBO_DRIVE}" ]]; then
          echo -e "${RED}Error: could not find any drive corresponding to Kobo device. Please make sure it is connected.${NC}"
          exit 1
        fi
        if [ "${PLATFORM}" == "WSL" ]; then
          WSL_MOUNT=$(findmnt -S "${KOBO_DRIVE}:" -t 9p -nlo TARGET | head -1)
          KOBO_MOUNTPOINT="/mnt/${KOBO_DRIVE}"
          if [[ -z "${WSL_MOUNT}" ]]; then
            echo -e "${YELLOW}Kobo device appears to be Windows drive ${KOBO_DRIVE} which is not mounted in WSL. We can try to attempt to mount it if you like. This will require administrator privileges.${NC}"
            while true; do 
              read -p "Do you want to mount the Kobo device in WSL? (yes/no): " yn
              case $yn in
                [Yy]* ) 
                  if [ ! -d "${KOBO_MOUNTPOINT}" ]; then
                    echo "Creating mountpoint ${KOBO_MOUNTPOINT}..."
                    sudo mkdir -m=777 -p "${KOBO_MOUNTPOINT}"
                  fi
                  echo "Mounting ${KOBO_DRIVE}..."
                  sudo mount "${KOBO_DRIVE}:" "${KOBO_MOUNTPOINT}" -t drvfs
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
        else
          for MOUNTPOINT in /mnt/ /cygdrive/ /; do
            KOBO_MOUNTPOINT="${MOUNTPOINT}${KOBO_DRIVE}/"
            [ -d "${KOBO_MOUNTPOINT}.kobo" ] && break
          done
          if [ ! -d "${KOBO_MOUNTPOINT}.kobo" ]; then
            echo -e "${RED}Could not find drive ${KOBO_DRIVE} in this environment. Exiting.${NC}"
            exit 1
          fi
        fi
        ;;
      * )
        echo -e "${RED}Unsupported OS: ${PLATFORM}${NC}"
        exit 1
        ;;
    esac

# Sanity check for Kobo mount point
if [[ -z "${KOBO_MOUNTPOINT}" ]] ; then
  echo -e "${RED}Error: Couldn't find a Kobo eReader volume! Is one actually mounted?${NC}"
  exit 1
fi

# Validate that this is actually a Kobo device
KOBO_DIR="${KOBO_MOUNTPOINT}/.kobo"
if [[ ! -d "${KOBO_DIR}" ]] ; then
  echo -e "${RED}Error: Can't find a .kobo directory, ${KOBO_MOUNTPOINT} doesn't appear to point to a Kobo eReader... Is one actually mounted?${NC}"
  exit 1
fi

# Set device plugin directory based on detected mount point
DEVICE_PLUGIN_DIR="${KOBO_MOUNTPOINT}/.adds/koreader/plugins"

echo -e "${GREEN}Found Kobo device at: ${KOBO_MOUNTPOINT}${NC}"

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

# Copy base files to device
for FILE in "${KOREADER_BASE_FILES[@]}"; do
  if [ ! -f "$FILE" ]; then
    echo -e "${YELLOW}Warning: Source file not found: $FILE${NC}"
    continue
  fi

  DEST="${KOBO_MOUNTPOINT}/.adds/koreader/${FILE}"
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

# Check for .adds/nm directory and create ereader menu item if needed
NM_DIR="${KOBO_MOUNTPOINT}/.adds/nm"
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
echo -e "${GREEN}Ejecting Kobo device...${NC}"
case "${PLATFORM}" in
  "Linux" )
    # Try to unmount the device
    if command -v udisksctl >/dev/null 2>&1; then
      DEVICE_SOURCE="$(findmnt -nlo SOURCE "$KOBO_MOUNTPOINT" 2>/dev/null || true)"
      if [ -n "$DEVICE_SOURCE" ]; then
        if ! udisksctl unmount -b "$DEVICE_SOURCE"; then
          echo -e "${YELLOW}Warning: udisksctl failed, trying umount...${NC}"
          if command -v umount >/dev/null 2>&1; then
            if ! umount "$KOBO_MOUNTPOINT"; then
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
      if ! umount "$KOBO_MOUNTPOINT"; then
        echo -e "${YELLOW}Warning: Could not automatically eject device. Please eject manually.${NC}"
      fi
    else
      echo -e "${YELLOW}Warning: Could not automatically eject device. Please eject manually.${NC}"
    fi
    ;;
  "Darwin" )
    if ! diskutil eject "$KOBO_MOUNTPOINT"; then
      echo -e "${YELLOW}Warning: Could not automatically eject device. Please eject manually.${NC}"
    fi
    ;;
  "WSL"* )
    if [[ ! -z "${UNMOUNT}" ]]; then
      if ! sudo umount "${KOBO_MOUNTPOINT}"; then
        echo -e "${YELLOW}Warning: Could not unmount device. Please eject manually.${NC}"
      fi
    fi
    ;;
esac

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Restart KOReader on your device"
echo "2. eReader should now be available in the Nickle menu item"
