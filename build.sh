#!/bin/bash

# lunch ROM_DEVICE-BUILD_TYPE
ROM="aosp"
DEVICE="laurel_sprout"
BUILD_TYPE="userdebug"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to handle errors
handle_error() {
    echo
    echo -e "${RED}Error occurred $(date +%H:%M:%S)${NC}"
    echo    
    exit 1
}

# Trap errors
trap 'handle_error' ERR

# Source the environment setup script
echo
echo -e "${YELLOW}Sourcing build/envsetup.sh...${NC}"
echo
source build/envsetup.sh || handle_error

TIME_START=$(date +%s.%N)

# Start the lunch build
echo
echo -e "${YELLOW}Running lunch for $DEVICE $BUILD_TYPE...${NC}"
echo
# Try running the lunch command
if ! lunch ${ROM}_${DEVICE}-${BUILD_TYPE}; then
    echo -e "${YELLOW}Trying alternative lunch command...${NC}"
    # Try an alternative lunch command
    if ! lunch ${ROM}_${DEVICE}-ap3a-${BUILD_TYPE}; then
        echo -e "${YELLOW}Trying another alternative lunch command...${NC}"
        # Try another alternative lunch command
        if ! brunch $DEVICE $BUILD_TYPE; then
            handle_error
        fi
    fi
fi

# Check if the -c flag is passed
RUN_INSTALLCLEAN=false
while getopts "c" flag; do
    case "${flag}" in
        c) RUN_INSTALLCLEAN=true ;;
        *) echo -e "${GREEN}Usage: $0 [-c]" ;;
    esac
done

# Run installclean if the -c flag is present
if $RUN_INSTALLCLEAN; then
    echo -e "${YELLOW}Running installclean..."
    m installclean
else
    echo -e "${YELLOW}Skipping installclean. Use -c flag to enable."
fi

# Build the target files package and otatools
echo
echo -e "${YELLOW}Building target-files-package and otatools...${NC}"
echo
mka target-files-package otatools || handle_error

# Define file paths
target_files="$OUT/obj/PACKAGING/target_files_intermediates/*-target_files*.zip"
ota_update_file="$CUSTOM_VERSION.zip"

# Remove Previous target files if they exist
if [ -e "$target_files" ]; then
    rm -rf "$target_files"
    echo -e "${RED}Removed Previous $target_files${NC}"
else
    echo -e "${YELLOW}Previous $target_files does not exist${NC}"
fi

if [ -e "$ota_update_file" ]; then
    rm -rf "$ota_update_file"
    echo -e "${RED}Removed Previous $ota_update_file${NC}"
else
    echo -e "${YELLOW}Previous $ota_update_file does not exist${NC}"
fi

# Get build name
echo
echo -e "${YELLOW}Get build name${NC}"
echo
# Extract the value of ro.custom.version
BUILD_PROP_FILE="$OUT/product/etc/build.prop"
CUSTOM_VERSION=$(grep "^ro.custom.version=" "$BUILD_PROP_FILE" | cut -d'=' -f2)
# Check if the value was found
if [ -n "$CUSTOM_VERSION" ]; then
    echo -e "${YELLOW}Extracted value: $CUSTOM_VERSION"
else
    echo -e "${YELLOW}ro.custom.version not found in $BUILD_PROP_FILE"
    CUSTOM_VERSION=${ROM}_${DEVICE}-signed-ota_update.zip
fi

# Create OTA from target files
echo
echo -e "${YELLOW}Creating OTA from target files...${NC}"
echo
ota_from_target_files -k $(pwd)/vendor/aosp/signing/keys/releasekey \
    --retrofit_dynamic_partitions \
    --block --backup=true \
    $OUT/obj/PACKAGING/target_files_intermediates/*-target_files*.zip \
    $CUSTOM_VERSION.zip || handle_error

# Echo package complete and path of the package
package_path="$(pwd)/$CUSTOM_VERSION.zip"
package_size_gb=$(du -h --apparent-size "$package_path" | awk -F'\t' '{print $1}')
echo
echo -e "${GREEN}Package complete: ${package_path} (${package_size_gb})${NC}"
echo

# Record the end time for signing
TIME_END=$(date +%s.%N)
elapsed_time=$(echo "($TIME_END - $TIME_START) / 60" | bc -l)
echo -e "${GREEN}#Total time elapsed: ${elapsed_time} minutes #${NC}"
echo
