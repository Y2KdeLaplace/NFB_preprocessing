#!/bin/bash
# Written by Yiheng Hu (2026.3.10-11)
# Module: Base fMRI Preprocessing (Native EPI Resolution)

export FSLOUTPUTTYPE=NIFTI

# ==============================================================================
# Configuration Variables
# ==============================================================================
PADDING_TRS=3
SAVE_PROCESSED_EPI_4D=0
SMOOTHING_CHECK=0
FWHM_mm=5

# ==============================================================================
# Input Validation & Setup
# ==============================================================================
if [ "$#" -eq 2 ]; then
    USE_FMAP=0
    RAW_EPI=$1
    RAW_T1=$2
    echo ">> No Fieldmap inputs detected. Standard rigid BBR will be used."
elif [ "$#" -eq 7 ]; then
    USE_FMAP=1
    RAW_EPI=$1
    RAW_T1=$2
    RAW_FMAP_MAG=$3
    RAW_FMAP_PH=$4
    
    # Receive dynamic JSON parameters
    DELTA_TE=$5
    EPI_ECHO_SPACING=$6
    EPI_PEDIR=$7
else
    echo "Usage: $0 <EPI> <T1> [<MAG> <PH> <DELTA_TE> <ECHO_SPACING> <PEDIR>]"
    exit 1
fi

OUT_DIR="/mnt/c/rtfmri/pyOpenNFT-setting/"
mkdir -p "$OUT_DIR"
cd "$OUT_DIR" || exit

echo "=== Starting Base Preprocessing Module ==="
# ==============================================================================
# Step 1: Crop Dummy TRs & Motion Correction
# ==============================================================================
echo ">> Step 1: Cropping $PADDING_TRS dummy TRs and running motion correction..."
fslroi "$RAW_EPI" tmp_cropped_EPI.nii $PADDING_TRS -1
echo "Doing Motion Correction..."
mcflirt -in tmp_cropped_EPI.nii -out tmp_mc_cropped_EPI.nii

# ==============================================================================
# Step 2: Generate Reference EPI
# ==============================================================================
echo ">> Step 2: Generating reference EPI (Native Resolution)..."
fslmaths tmp_mc_cropped_EPI.nii -Tmean MC_Templ.nii
echo "   -> Generated: MC_Templ.nii"

# ==============================================================================
# Step 3: T1 Brain Extraction
# Here we get raw_T1_brain_mask.nii and raw_T1_brain.nii
# ==============================================================================
echo ">> Step 3: Skull-stripping T1 and generating high-res brain mask..."
robustfov -i "$RAW_T1" -r tmp_T1_cropped.nii
bet tmp_T1_cropped.nii raw_T1_brain.nii -R -m
mv raw_T1_brain_mask.nii tmp_raw_T1_brain_mask.nii

# ==============================================================================
# Step 3.5: Prepare Fieldmap (B0 Unwarping)
# ==============================================================================
if [ "$USE_FMAP" -eq 1 ]; then
    echo ">> Step 3.5: Preparing Fieldmap..."

    # 1. remove skull and a part of edge
    bet "$RAW_FMAP_MAG" tmp_fmap_mag_brain.nii -R
    fslmaths tmp_fmap_mag_brain.nii -ero tmp_fmap_mag_brain_ero1.nii
    fslmaths tmp_fmap_mag_brain_ero1.nii -ero tmp_fmap_mag_brain_ero2.nii

    # 2. generate Rad/s formattt of real fieldmap
    # SIEMENS tell FSL formatt
    fsl_prepare_fieldmap SIEMENS "$RAW_FMAP_PH" tmp_fmap_mag_brain_ero2.nii tmp_fmap_rads.nii $DELTA_TE
fi

# ==============================================================================
# Step 4: Coregistration (Calculate Matrix ONLY)
# ==============================================================================
echo ">> Step 4: Calculating EPI-to-T1 transformation matrix (No reslicing)..."
if [ "$USE_FMAP" -eq 0 ]; then
    epi_reg --epi=MC_Templ.nii \
            --t1="$RAW_T1" \
            --t1brain=raw_T1_brain.nii \
            --out=tmp_EPI_to_raw_T1_brain
    #flirt -in MC_Templ.nii -ref raw_T1_brain.nii -omat tmp_EPI_to_raw_T1_brain.mat -dof 6
else
    epi_reg --epi=MC_Templ.nii \
            --t1="$RAW_T1" \
            --t1brain=raw_T1_brain.nii \
            --out=tmp_EPI_to_raw_T1_brain \
            --fmap=tmp_fmap_rads.nii \
            --fmapmag="$RAW_FMAP_MAG" \
            --fmapmagbrain=tmp_fmap_mag_brain_ero1.nii \
            --echospacing=$EPI_ECHO_SPACING \
            --pedir=$EPI_PEDIR
fi

# ==============================================================================
# Step 5: Warp High-Res T1 Mask to Native EPI Space
# ==============================================================================
echo ">> Step 5: Warping T1 mask down to native EPI space..."
if [ "$USE_FMAP" -eq 1 ]; then
    echo "   -> Using Non-linear Inverse Warp (deliberately distorting ROI to match real-time EPI)..."
    invwarp --ref=MC_Templ.nii --warp=tmp_EPI_to_raw_T1_brain_warp.nii --out=T1_to_distorted_EPI_warp.nii
    applywarp --ref=MC_Templ.nii --in=tmp_raw_T1_brain_mask.nii --warp=T1_to_distorted_EPI_warp.nii --interp=nn --out=WholeBrainMask_EPI.nii

    echo "   -> Generating 1mm dummy reference to preserve T1 resolution..."
    flirt -in MC_Templ.nii -ref MC_Templ.nii -applyisoxfm 1 -init $FSLDIR/etc/flirtsch/ident.mat -out tmp_MC_Templ_1mm.nii
    applywarp --ref=tmp_MC_Templ_1mm.nii --in=raw_T1_brain.nii --warp=T1_to_distorted_EPI_warp.nii --out=T1.nii
else
    echo "   -> Using Linear Inverse Matrix..."
    convert_xfm -omat raw_T1_brain_to_EPI.mat -inverse tmp_EPI_to_raw_T1_brain.mat
    
    flirt -in tmp_raw_T1_brain_mask.nii -ref MC_Templ.nii -applyxfm -init raw_T1_brain_to_EPI.mat -interp nearestneighbour -out WholeBrainMask_EPI.nii
    flirt -in raw_T1_brain.nii -ref MC_Templ.nii -applyxfm -init raw_T1_brain_to_EPI.mat -applyisoxfm 1 -out T1.nii
fi
echo "   -> Generated: WholeBrainMask_EPI.nii"
echo "   -> Generated: T1.nii (High-res T1 perfectly aligned with EPI)"

# ==============================================================================
# Step 6: Process and Save 4D EPI (Native Resolution)
# ==============================================================================
if [ "$SAVE_PROCESSED_EPI_4D" -eq 1 ]; then
    echo ">> Step 6: Saving processed 4D EPI in native resolution..."
    if [ "$SMOOTHING_CHECK" -eq 1 ]; then
        echo "   -> Doing smoothing (FWHM = ${FWHM_mm}mm)..."
        sigma_gaus=$(echo "scale=10; $FWHM_mm / sqrt(8 * l(2))" | bc -l)
        fslmaths tmp_mc_cropped_EPI.nii -s $sigma_gaus EPI.nii
    else
        mv tmp_mc_cropped_EPI.nii EPI.nii
    fi
    echo "   -> Generated: EPI.nii"
fi

# ==============================================================================
# Cleanup
# ==============================================================================
echo ">> Cleaning up intermediate files..."
rm tmp_*.nii 2>/dev/null
rm tmp_*.mat 2>/dev/null

echo "=== Base Preprocessing Module Completed ==="