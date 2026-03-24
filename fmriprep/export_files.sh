#!/bin/bash
# Script to securely extract, rename, and unzip perfectly aligned fMRIPrep outputs
# Target: pyOpenNFT Real-Time Processing
# Core Logic: All exported files are strictly co-registered in the T1w spatial coordinate system.

SUB_ID="sub-01"
FMRIPREP_OUT="$1/output/${SUB_ID}"

# Create target directory if it doesn't exist
TARGET_DIR=$2
mkdir -p "${TARGET_DIR}"

echo "Starting perfectly aligned export to ${TARGET_DIR}..."

# 1. Structural Anchor (The native preprocessed T1w image)
T1_FILE=$(find "${FMRIPREP_OUT}/anat" -name "*_desc-preproc_T1w.nii.gz" | head -n 1)

# 2. Functional Reference (BOLD reference co-registered to T1w space)
MC_TEMPL_FILE=$(find "${FMRIPREP_OUT}/func" -name "*_space-T1w_boldref.nii.gz" | head -n 1)

# 3. Functional Mask (Brain mask co-registered to T1w space, matching the BOLD grid)
MASK_FILE=$(find "${FMRIPREP_OUT}/func" -name "*_space-T1w_desc-brain_mask.nii.gz" | head -n 1)

# Safety check
if [ -z "$T1_FILE" ] || [ -z "$MC_TEMPL_FILE" ] || [ -z "$MASK_FILE" ]; then
    echo "Error: Critical fMRIPrep output files are missing. Did the pipeline finish successfully?"
    exit 1
fi

echo " -> Copying T1 structural anchor..."
cp "${T1_FILE}" "${TARGET_DIR}/T1.nii.gz"

echo " -> Copying BOLD reference (aligned to T1) as MC_Templ..."
cp "${MC_TEMPL_FILE}" "${TARGET_DIR}/MC_Templ.nii.gz"

echo " -> Copying Brain mask (aligned to T1) as WholeBrainMask_EPI..."
cp "${MASK_FILE}" "${TARGET_DIR}/WholeBrainMask_EPI.nii.gz"

echo " -> Unzipping all files for pyOpenNFT compatibility..."
gunzip -f "${TARGET_DIR}/T1.nii.gz"
gunzip -f "${TARGET_DIR}/MC_Templ.nii.gz"
gunzip -f "${TARGET_DIR}/WholeBrainMask_EPI.nii.gz"

echo "Export completed successfully! All 3 files are perfectly registered in space."