#!/bin/bash
# Written by Yiheng Hu (2026.3.23)

BIDS_DIR="$(wslpath -u "C:\rtfmri\nii_files\BIDS")"
SUB_ID="sub-01"

TARGET_DIR="$(wslpath -u "C:\rtfmri\pyOpenNFT-setting")"

cd "$(wslpath -u "C:\rtfmri\batch\bids")"
./bids_export.sh

cd "$(wslpath -u "C:\rtfmri\batch\fastsurfer")"
conda activate Fastsurfer
./anat_proc.sh $BIDS_DIR $SUB_ID

./registration.sh $BIDS_DIR $SUB_ID $TARGET_DIR

./create_masks.sh $BIDS_DIR $SUB_ID $TARGET_DIR