#!/bin/bash
# Written by Yiheng Hu (2026.3.23)

BIDS_DIR="$(wslpath -u "C:\rtfmri\batch\bids")"
SUB_ID="sub-01"
data_BIDs_path="$(wslpath -u "C:\rtfmri\nii_files\BIDS")"
scripts_path="$(wslpath -u "C:\rtfmri\batch\fastsurfer")"

TARGET_DIR="$(wslpath -u "C:\rtfmri\pyOpenNFT-setting")"

cd "$BIDS_DIR"
./bids_export.sh

cd "$scripts_path"
conda activate Fastsurfer
./anat_proc.sh $data_BIDs_path $SUB_ID

./epi_proc.sh $data_BIDs_path $SUB_ID

./registration.sh $data_BIDs_path $SUB_ID

./create_masks.sh $data_BIDs_path $SUB_ID $TARGET_DIR