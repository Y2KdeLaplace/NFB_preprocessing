#!/bin/bash
# Written by Yiheng Hu (2026.3.19)
# You can modify this script to adapt to your experiment

# ==========================================
# Settings for experiment
# ==========================================
atlas_path=$(wslpath -u "D:\atlas\Tian2020MSA\3T\Subcortex-Only\Tian_Subcortex_S1_3T.nii.gz")
roi_index=(10 1)
roi_name=(AMG_L HPC_R)

BIDs_path="$(wslpath -u "C:\rtfmri\batch\bids")"
data_BIDs_path="$(wslpath -u "C:\rtfmri\nii_files\BIDS")"
scripts_path="$(wslpath -u "C:\rtfmri\batch\fsl_opt")"
work_path="$(wslpath -u "C:\rtfmri\nii_files")"

TARGET_DIR="$(wslpath -u "C:\rtfmri\pyOpenNFT-setting")"
TARGET_ROIs_DIR="$(wslpath -u "C:\rtfmri\pyOpenNFT-setting\ROIs")"

# ==========================================
# Export DICOM to BIDs
# ==========================================
cd "$BIDs_path"
./bids_export.sh

# ==========================================
# Parse Parameters
# ==========================================
echo "-----------------------------------------------"
echo ">> Parsing JSON metadata for physical parameters..."

cd "$scripts_path"
SUB_ID="sub-01"

PARAMS=$(./parse_bids_params.sh "$data_BIDs_path" "$SUB_ID" "rest")
if [ $? -ne 0 ]; then
    echo "ERROR: Parameter parsing failed. Pipeline aborted."
    exit 1
fi

read -r EPI_PEDIR EPI_ECHO_SPACING DELTA_TE <<< "$PARAMS"

echo "   -> Phase Encoding Dir: ${EPI_PEDIR}"
echo "   -> Echo Spacing: ${EPI_ECHO_SPACING} s"
if [ "$DELTA_TE" != "N/A" ]; then
    echo "   -> Delta TE: ${DELTA_TE} ms"
    FMAP_DIR="${data_BIDs_path}/${SUB_ID}/fmap"
else
    echo "   -> Delta TE: N/A (No Fieldmap detected)"
fi

# ==========================================
# Step 2: Preprocessing Pipeline
# ==========================================
echo "-----------------------------------------------"
echo ">> Starting Preprocessing Pipeline..."

T1_NII="${data_BIDs_path}/${SUB_ID}/anat/${SUB_ID}_T1w.nii.gz"
EPI_NII="${data_BIDs_path}/${SUB_ID}/func/${SUB_ID}_task-rest_bold.nii.gz"

if [ "$DELTA_TE" != "N/A" ] && \
   [ -f "${FMAP_DIR}/${SUB_ID}_magnitude1.nii.gz" ] && \
   [ -f "${FMAP_DIR}/${SUB_ID}_phasediff.nii.gz" ]; then
    ./proc_raw.sh "$EPI_NII" "$T1_NII" \
                  "${FMAP_DIR}/${SUB_ID}_magnitude1.nii.gz" \
                  "${FMAP_DIR}/${SUB_ID}_phasediff.nii.gz" \
                  "$DELTA_TE" "$EPI_ECHO_SPACING" "$EPI_PEDIR"
else
    echo "Warning: Fieldmaps incomplete or not provided. Proceeding with standard coregistration."
    ./proc_raw.sh "$EPI_NII" "$T1_NII"
fi

# ==========================================
# Step 3: ROI Extraction & Post-Renaming
# ==========================================
echo "-----------------------------------------------"
echo ">> Starting ROI projection..."

./gen_atlas_ROI.sh "$work_path" "$atlas_path" "${roi_index[@]}"

echo ">> Renaming and deploying ROI masks..."
mkdir -p "$TARGET_ROIs_DIR"
for i in "${!roi_index[@]}"; do
    idx="${roi_index[$i]}"
    name="${roi_name[$i]}"
    
    SOURCE_ROI_FILE="$work_path/native_EPI_ROI_${idx}_mask.nii"
    
    if [ -f "$SOURCE_ROI_FILE" ]; then
        mv "$SOURCE_ROI_FILE" "${TARGET_ROIs_DIR}/${name}.nii"
        echo "   -> Successfully deployed ${name}.nii for pyOpenNFT."
    else
        echo "   -> ERROR: Expected ROI mask ${SOURCE_ROI_FILE} not found!"
    fi
done

mv "$work_path/T1.nii" "$TARGET_DIR/T1.nii"
mv "$work_path/MC_Templ.nii" "$TARGET_DIR/MC_Templ.nii"
mv "$work_path/WholeBrainMask_EPI.nii" "$TARGET_DIR/WholeBrainMask_EPI.nii"

echo "-----------------------------------------------"
echo "All processing finished successfully! Ready for pyOpenNFT."