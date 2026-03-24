#!/bin/bash
# Written by Yiheng Hu (2026.3.19)
# You can modify this script to adapt to your experiment

# ==========================================
# Settings for experiment
# ==========================================
atlas_path=$(wslpath -u "D:\atlas\Tian2020MSA\3T\Subcortex-Only\Tian_Subcortex_S1_3T_2009cAsym_1mm.nii.gz")
roi_index=(10 1)
roi_name=(AMG_L HPC_R)

BIDs_path="$(wslpath -u "C:\rtfmri\batch\bids")"
data_BIDs_path="$(wslpath -u "C:\rtfmri\nii_files\BIDS")"
scripts_path="$(wslpath -u "C:\rtfmri\batch\fmriprep")"
work_path="$(wslpath -u "C:\rtfmri\nii_files\fmriprep")"

TARGET_DIR="$(wslpath -u "C:\rtfmri\pyOpenNFT-setting")"
TARGET_ROIs_DIR="$(wslpath -u "C:\rtfmri\pyOpenNFT-setting\ROIs")"

# ==========================================
# Export DICOM to BIDs
# ==========================================
cd "$BIDs_path"
./bids_export.sh

# ==========================================
# Preprocessing Pipeline
# ==========================================
cd "$scripts_path"

echo "Starting fmriprep..."
./fmripreping.sh "$data_BIDs_path" "$work_path"

echo "Exporting aligned files..."
./export_files.sh "$work_path" "$TARGET_DIR"

# ==========================================
# ROI Extraction & Post-Renaming
# ==========================================
echo "Starting ROI projection..."
./project_roi.sh "$atlas_path" "${roi_index[@]}"

echo "Renaming ROI masks..."
cd "${TARGET_ROIs_DIR}"
for i in "${!roi_index[@]}"; do
    idx="${roi_index[$i]}"
    name="${roi_name[$i]}"
    
    target_file="ROI_${idx}_mask.nii"
    
    if [ -f "$target_file" ]; then
        mv "$target_file" "${name}.nii"
        echo " -> Successfully renamed ${target_file} to ${name}.nii"
    else
        echo " -> Warning: Expected ${target_file} but it was not found!"
    fi
done

echo "-----------------------------------------------"
echo "All processing finished successfully! Ready for pyOpenNFT."