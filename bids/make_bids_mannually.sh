#!/bin/bash
# Written by Yiheng Hu (2026.3.17)
# Updated to handle Siemens ND fieldmaps and EchoTime injection
CURRENT_DIR='/mnt/c/rtfmri/nii_files'

# Check if at least 2 input paths are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <path_to_epi> <path_to_dicomdir> [task_name]"
    echo "Example: $0 '/MRI/EPI' '/MRI/DICOMDIR' 'motor'"
    exit 1
fi

EPI_DCM_PATH=$1
DICOMDIR_PATH=$2
TASK_NAME=${3:-rest} # Set task name, default to 'rest' if not provided as the 3rd argument

# Set BIDS root in the current working directory where the script is executed
BIDS_ROOT="${CURRENT_DIR}/BIDS"
SUB_ID="sub-01"
TEMP_EPI="${BIDS_ROOT}/temp_epi"
TEMP_ANAT="${BIDS_ROOT}/temp_anat"

# Create standard BIDS directory structure
mkdir -p "${BIDS_ROOT}/${SUB_ID}/anat"
mkdir -p "${BIDS_ROOT}/${SUB_ID}/func"
mkdir -p "${BIDS_ROOT}/${SUB_ID}/fmap"
mkdir -p "${TEMP_EPI}"
mkdir -p "${TEMP_ANAT}"

echo "Converting EPI DICOM files from: ${EPI_DCM_PATH}"
dcm2niix -z y -b y -f "%p_%s" -o "${TEMP_EPI}" "${EPI_DCM_PATH}" > /dev/null

echo "Converting DICOMDIR files from: ${DICOMDIR_PATH}"
dcm2niix -z y -b y -f "%p_%s" -o "${TEMP_ANAT}" "${DICOMDIR_PATH}" > /dev/null

echo "Organizing EPI functional files (Task: ${TASK_NAME})..."
shopt -s nullglob
run_idx=1
for nii_file in "${TEMP_EPI}"/*.nii.gz; do
    if [ -f "$nii_file" ]; then
        base_name=$(basename "$nii_file" .nii.gz)
        json_file="${TEMP_EPI}/${base_name}.json"
        
        # Apply the dynamic task name from argument
        new_nii="${BIDS_ROOT}/${SUB_ID}/func/${SUB_ID}_task-${TASK_NAME}_run-$(printf "%02d" $run_idx)_bold.nii.gz"
        new_json="${BIDS_ROOT}/${SUB_ID}/func/${SUB_ID}_task-${TASK_NAME}_run-$(printf "%02d" $run_idx)_bold.json"
        
        mv "$nii_file" "$new_nii"
        if [ -f "$json_file" ]; then mv "$json_file" "$new_json"; fi
        ((run_idx++))
    fi
done

echo "Parsing JSON files to organize Anatomical images (finding ND versions)..."
# Helper function to parse JSON SeriesDescription and find the optimal image
find_best_anat() {
    local keyword1=$1
    local keyword2=$2
    local best_file=""
    local fallback_file=""

    for nii in "${TEMP_ANAT}"/*"${keyword1}"*.nii.gz "${TEMP_ANAT}"/*"${keyword2}"*.nii.gz; do
        if [ ! -f "$nii" ]; then continue; fi
        local json="${nii%.nii.gz}.json"
        if [ ! -f "$json" ]; then continue; fi

        # Extract SeriesDescription from JSON
        local series_desc=$(grep -i '"SeriesDescription"' "$json" 2>/dev/null)

        # Skip localizers explicitly
        if echo "$series_desc" | grep -iq "localizer"; then continue; fi

        # Check for ND flag in SeriesDescription
        if echo "$series_desc" | grep -iq "ND"; then
            best_file="$nii"
            break # High priority found, stop searching
        elif [ -z "$fallback_file" ]; then
            fallback_file="$nii" # Save normal version as fallback
        fi
    done

    # Return the best match
    if [ -n "$best_file" ]; then
        echo "$best_file"
    else
        echo "$fallback_file"
    fi
}

# Process T1w image (Keywords: T1, mprage)
t1_file=$(find_best_anat "T1" "mprage")
if [ -n "$t1_file" ]; then
    base_name=$(basename "$t1_file" .nii.gz)
    mv "$t1_file" "${BIDS_ROOT}/${SUB_ID}/anat/${SUB_ID}_T1w.nii.gz"
    mv "${TEMP_ANAT}/${base_name}.json" "${BIDS_ROOT}/${SUB_ID}/anat/${SUB_ID}_T1w.json"
    echo " -> T1w processed successfully."
fi

# Process T2w image (Keywords: T2, SPACE)
t2_file=$(find_best_anat "T2" "SPACE")
if [ -n "$t2_file" ]; then
    base_name=$(basename "$t2_file" .nii.gz)
    mv "$t2_file" "${BIDS_ROOT}/${SUB_ID}/anat/${SUB_ID}_T2w.nii.gz"
    mv "${TEMP_ANAT}/${base_name}.json" "${BIDS_ROOT}/${SUB_ID}/anat/${SUB_ID}_T2w.json"
    echo " -> T2w processed successfully."
fi

echo "Organizing Fieldmap files and handling EchoTimes..."
# 1. Process PhaseDiff directly
ph_file=$(find "${TEMP_ANAT}" -maxdepth 1 -type f -name "*_ph.nii*" | head -n 1)
if [ -n "$ph_file" ]; then
    # Strip extension safely
    base_name=$(basename "$ph_file" | sed 's/\.nii.*//')
    mv "${TEMP_ANAT}/${base_name}.nii"* "${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_phasediff.nii.gz" 2>/dev/null || mv "${TEMP_ANAT}/${base_name}.nii" "${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_phasediff.nii" 2>/dev/null
    mv "${TEMP_ANAT}/${base_name}.json" "${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_phasediff.json" 2>/dev/null
fi

# 2. Process Magnitudes (Find ND versions and sort by EchoTime)
mag_jsons=$(find "${TEMP_ANAT}" -maxdepth 1 -name "*gre_field_mapping*.json" ! -name "*_ph.json")
nd_jsons=()

# Filter only JSONs containing 'ND' in SeriesDescription
for jf in $mag_jsons; do
    if grep -iq '"SeriesDescription".*ND' "$jf"; then
        nd_jsons+=("$jf")
    fi
done

# We expect exactly 2 ND jsons (e.g., Series 7 e1 and e1a)
if [ ${#nd_jsons[@]} -eq 2 ]; then
    json1="${nd_jsons[0]}"
    json2="${nd_jsons[1]}"
    
    # Extract EchoTime values
    te1=$(grep -i '"EchoTime"' "$json1" | grep -o '[0-9.]*')
    te2=$(grep -i '"EchoTime"' "$json2" | grep -o '[0-9.]*')
    
    # Compare float numbers using awk to determine which is Magnitude 1 (shorter TE)
    is_json1_te1=$(awk -v t1="$te1" -v t2="$te2" 'BEGIN {print (t1 < t2) ? 1 : 0}')
    
    if [ "$is_json1_te1" -eq 1 ]; then
        mag1_json="$json1"; mag2_json="$json2"
        TE1_val="$te1"; TE2_val="$te2"
    else
        mag1_json="$json2"; mag2_json="$json1"
        TE1_val="$te2"; TE2_val="$te1"
    fi
    
    # Rename to magnitude1 and magnitude2
    base1=$(basename "$mag1_json" | sed 's/\.json//')
    base2=$(basename "$mag2_json" | sed 's/\.json//')
    
    mv "${TEMP_ANAT}/${base1}.nii"* "${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_magnitude1.nii.gz" 2>/dev/null || mv "${TEMP_ANAT}/${base1}.nii" "${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_magnitude1.nii" 2>/dev/null
    mv "$mag1_json" "${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_magnitude1.json"
    
    mv "${TEMP_ANAT}/${base2}.nii"* "${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_magnitude2.nii.gz" 2>/dev/null || mv "${TEMP_ANAT}/${base2}.nii" "${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_magnitude2.nii" 2>/dev/null
    mv "$mag2_json" "${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_magnitude2.json"

    # Inject into phasediff.json
    ph_json="${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_phasediff.json"
    if [ -f "$ph_json" ]; then
        sed -i "s/{/{\n    \"EchoTime1\": ${TE1_val},\n    \"EchoTime2\": ${TE2_val},/" "$ph_json"
        echo " -> Successfully mapped ND magnitudes and injected EchoTimes ($TE1_val, $TE2_val) into phasediff.json!"
    fi
else
    echo "Warning: Did not find exactly 2 ND magnitude files. Found ${#nd_jsons[@]}."
fi

# Generate dataset_description.json
cat <<EOF > "${BIDS_ROOT}/dataset_description.json"
{
    "Name": "RealTime_fMRI_Dataset",
    "BIDSVersion": "1.8.0",
    "Authors": ["Yiheng Hu"],
    "DatasetType": "raw"
}
EOF

# Create a README with actual content to avoid EMPTY_FILE error
echo "Dataset for the MRI neurofeedback research project." > "${BIDS_ROOT}/README"

# cleanup
rm -rf "${TEMP_EPI}"
rm -rf "${TEMP_ANAT}"

echo "BIDS conversion completed in ${BIDS_ROOT}!"