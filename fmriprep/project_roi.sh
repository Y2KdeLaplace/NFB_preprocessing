#!/bin/bash
# Written by Yiheng Hu (2026.3.19)
# Script to project an MNI Atlas or MNI Mask to individual space and output independent binary masks
# Core Logic: Anchored in space-T1w functional grid.

SUB_ID="sub-01"
# Define the root output directory of your fMRIPrep run
FMRIPREP_OUT="/mnt/c/rtfmri/nii_files/fmriprep/output/${SUB_ID}"
# Define the target directory for OpenNFT
TARGET_DIR="/mnt/c/rtfmri/pyOpenNFT-setting/ROIs"

# Check if at least an atlas/mask is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <path_to_mni_atlas_or_mask.nii.gz> [ROI_1] [ROI_2] ..."
    echo "Example 1 (Atlas): $0 /rtfmri/aal3.nii.gz 17 18"
    echo "Example 2 (Mask):  $0 /rtfmri/my_mni_mask.nii.gz"
    exit 1
fi

ATLAS_INPUT=$1
shift # Shift arguments to check for ROI numbers

# Smart Defaulting: If no ROI indices are provided, default to 1 (assuming input is a binary mask)
if [ "$#" -eq 0 ]; then
    ROIS=(1)
    echo "Notice: No ROI index provided. Defaulting to ROI=1 (treating input as a binary MNI mask)."
else
    ROIS=("$@")
fi

# 1. Target Reference Image (The functional grid aligned to T1)
REF_GRID=$(find "${FMRIPREP_OUT}/func" -name "*_space-T1w_boldref.nii.gz" | head -n 1)

# 2. Transform Matrix (MNI standard space -> Individual T1w space)
TRANSFORM_H5=$(find "${FMRIPREP_OUT}/anat" -name "*_from-MNI152NLin2009cAsym_to-T1w_mode-image_xfm.h5" | head -n 1)

# Safety check for critical files
if [ -z "$REF_GRID" ] || [ -z "$TRANSFORM_H5" ]; then
    echo "Error: Could not find Reference Grid (space-T1w_boldref) or Transform Matrix (.h5)."
    exit 1
fi

# A temporary holding place for the fully warped atlas/mask
WARPED_ATLAS="${TARGET_DIR}/${SUB_ID}_warped_temp_space-T1w.nii.gz"

echo "Step 1: Warping input from MNI to space-T1w functional grid using ANTs..."
antsApplyTransforms -d 3 \
    -i "${ATLAS_INPUT}" \
    -r "${REF_GRID}" \
    -n MultiLabel \
    -t "${TRANSFORM_H5}" \
    -o "${WARPED_ATLAS}"

echo "Step 2: Extracting independent binary masks..."

# Loop through each provided ROI ID and create a separate file for it
for ROI in "${ROIS[@]}"; do
    echo " -> Creating binary mask for ROI ${ROI}..."
    
    # Define the output filename specific to this ROI
    OUT_MASK_GZ="${TARGET_DIR}/ROI_${ROI}_mask.nii.gz"
    OUT_MASK="${TARGET_DIR}/ROI_${ROI}_mask.nii"
    
    # Isolate the specific ROI value and binarize it (all selected voxels become 1)
    fslmaths "${WARPED_ATLAS}" -thr "${ROI}" -uthr "${ROI}" -bin "${OUT_MASK_GZ}"
    
    # Unzip specifically for pyOpenNFT
    gunzip -f "${OUT_MASK_GZ}"
    
    echo "    Saved as: ${OUT_MASK}"
done

# Cleanup the temporary fully warped atlas
rm "${WARPED_ATLAS}"

echo "Done! All masks are perfectly aligned to the T1w functional grid."