#!/bin/bash
# Written by Yiheng Hu (2026.3.12)
# Module: Atlas ROI Extraction and Native Space Mapping
#
# ==============================================================================
# IMPORTANT WARNING: 
# Ensure that the spatial resolution of the external Atlas provided as input 
# strictly matches the MNI templates used in this script (e.g., both 2mm or 
# both 1mm isotropic). Mixing resolutions will lead to interpolation misalignment 
# and inaccurate ROI extraction in native space.
# ==============================================================================
RAW_T1="/mnt/c/rtfmri/nii_files/BIDS/sub-01/anat/sub-01_T1w.nii.gz"

export FSLOUTPUTTYPE=NIFTI

# ==============================================================================
# Input Validation
# ==============================================================================
# Require at least 3 arguments: T1_dir, Atlas_dir, and at least 1 ROI index
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <work_dir> <atlas_dir> <roi_index_1> [roi_index_2 ...]"
    exit 1
fi

MNI_BRAIN="/home/wanglab/fsl/data/standard/MNI152_T1_2mm_brain.nii.gz"
MNI_HEAD="/home/wanglab/fsl/data/standard/MNI152_T1_2mm.nii.gz"

cd $1
ATLAS=$2

# Shift by 1 to consume the first two arguments (T1 and Atlas).
# The remaining arguments ("$@") are packaged into the ROI loop.
shift 2
ROI_INDICES=("$@")

echo "=== Starting ROI Extraction Module ==="
echo ">> Target ROIs Index: ${ROI_INDICES[*]}"

# ==============================================================================
# Step 1-3: Core Registration (Calculate T1 to MNI mathematical mapping)
# ==============================================================================
echo ">> Calculating Linear Registration (T1 -> MNI)..."
flirt -in raw_T1_brain.nii -ref "$MNI_BRAIN" -omat tmp_T1_to_MNI.mat

echo ">> Calculating Non-linear Registration (Warp field)..."
fnirt --in="$RAW_T1" --ref="$MNI_HEAD" --aff=tmp_T1_to_MNI.mat --cout=tmp_warp_to_MNI --config=T1_2_MNI152_2mm

echo ">> Inverting warp field (MNI -> T1)..."
invwarp --ref="$RAW_T1" --warp=tmp_warp_to_MNI.nii --out=tmp_warp_to_T1.nii

# ==============================================================================
# Step 4: Determine Fieldmap Strategy and Combine Final Warps
# ==============================================================================
echo ">> Preparing final transformations..."
if [ -f "T1_to_distorted_EPI_warp.nii" ]; then
    STRATEGY="FIELDMAP"
    echo "   -> Fieldmap detected. Concatenating non-linear warps..."
    convertwarp --ref=MC_Templ.nii \
                --warp1=tmp_warp_to_T1.nii \
                --warp2=T1_to_distorted_EPI_warp.nii \
                --out=tmp_combined_MNI_to_EPI_warp.nii
elif [ -f "raw_T1_brain_to_EPI.mat" ]; then
    STRATEGY="LINEAR"
    echo "   -> No fieldmap detected. Will use linear post-matrix."
else
    echo "   -> ERROR: Missing mapping files from proc_raw.sh."
    exit 1
fi

# ==============================================================================
# Step 5: Loop Through and Process All ROIs
# ==============================================================================
echo ">> Processing ROIs..."

for ROI_INDEX in "${ROI_INDICES[@]}"; do
    echo "   -> Extracting and mapping ROI: $ROI_INDEX"
    
    # Extract current ROI from the Atlas
    fslmaths "$ATLAS" -thr "$ROI_INDEX" -uthr "$ROI_INDEX" -bin tmp_MNI_ROI_${ROI_INDEX}.nii
    
    # Project current ROI to Native EPI Space
    if [ "$STRATEGY" == "FIELDMAP" ]; then
        applywarp --ref=MC_Templ.nii \
                  --in=tmp_MNI_ROI_${ROI_INDEX}.nii \
                  --warp=tmp_combined_MNI_to_EPI_warp.nii \
                  --interp=nn \
                  --out=native_EPI_ROI_${ROI_INDEX}_mask.nii
    else
        applywarp --ref=MC_Templ.nii \
                  --in=tmp_MNI_ROI_${ROI_INDEX}.nii \
                  --warp=tmp_warp_to_T1.nii \
                  --postmat=raw_T1_brain_to_EPI.mat \
                  --interp=nn \
                  --out=native_EPI_ROI_${ROI_INDEX}_mask.nii
    fi
done

# ==============================================================================
# Cleanup
# ==============================================================================
echo ">> Cleaning up intermediate files..."
rm tmp_*.nii 2>/dev/null
rm tmp_*.mat 2>/dev/null

echo "=== ROI Extraction Completed ==="