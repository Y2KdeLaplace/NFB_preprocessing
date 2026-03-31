#!/bin/bash
# Written by Yiheng Hu (2026.3.31)
WORK_DIR=/mnt/c/rtfmri/nii_files

echo "-----------------------------------------------"
echo "
Real-time transferred .dcm files will be stored as follow ways:
C:.
│
├─20260317.20260317_RT_02.2026.03.17_10_02_07_STD_1.3.12.2.1107.5.99.3
│  │  001_000013_000001_1.3.12.2.1107.5.2.43.166305.2026031710390810723723103.dcm
│  │  001_000013_000002_1.3.12.2.1107.5.2.43.166305.2026031710390985117823169.dcm
│  │  001_000013_000003_1.3.12.2.1107.5.2.43.166305.2026031710391185117823242.dcm
│  │  001_000013_000004_1.3.12.2.1107.5.2.43.166305.2026031710391385119723315.dcm
│  │
│  ├─15-online-practice
"
echo -n "Please input the Windows path of transferred .dcm files:"
read -r dcm_path
dcm_path=$(wslpath -u "$dcm_path")
echo "So it's in: ${dcm_path}"

echo "-----------------------------------------------"
echo "exporting .dcm files to bold.nii"
dcm2niix -z n -f bold -w 1 -o $WORK_DIR $dcm_path

echo "-----------------------------------------------"
echo "
File structure of exported DICOM database is like:
C:.
│  DICOMDIR
│
└─DICOM
    └─26031703
        ├─19350000
        │      11933663
        │      ...
        │
        └─24130000
                14148086
                ...
"
echo -n "Please enter the Windows path of exported DICOM files: "
read -r dicom_bin_path
dicom_bin_path=$(wslpath -u "$dicom_bin_path")
echo "So it's in: ${dicom_bin_path}"

echo "-----------------------------------------------"
echo "Converting EPI DICOM files from: ${dicom_bin_path}"
mkdir -p "${WORK_DIR}/temp"
dcm2niix -z n -b y -f "%p_%s" -o $WORK_DIR/temp $dicom_bin_path > /dev/null

echo "-----------------------------------------------"
echo "Parsing JSON files to organize Anatomical images (finding ND versions)..."
# Helper function to parse JSON SeriesDescription and find the optimal image
find_best_anat() {
    local keyword1="$1"
    local keyword2="$2"
    local best_file=""
    local fallback_file=""

    for nii in "$WORK_DIR/temp"/*"${keyword1}"*.nii "$WORK_DIR/temp"/*"${keyword2}"*.nii; do
        if [ ! -f "$nii" ]; then continue; fi
        local json="${nii%.nii}.json"
        if [ ! -f "$json" ]; then continue; fi

        local series_desc=$(grep -i '"SeriesDescription"' "$json" 2>/dev/null)

        if echo "$series_desc" | grep -iq "localizer"; then continue; fi

        if echo "$series_desc" | grep -iq "ND"; then
            best_file="$nii"
            break
        elif [ -z "$fallback_file" ]; then
            fallback_file="$nii"
        fi
    done

    if [ -n "$best_file" ]; then
        echo "$best_file"
    else
        echo "$fallback_file"
    fi
}

# Process T1w image (Keywords: T1, MPRAGE)
t1_file=$(find_best_anat "T1" "MPRAGE")
if [ -n "$t1_file" ]; then
    base_name=$(basename "$t1_file" .nii)
    mv "$t1_file" "${WORK_DIR}/anat.nii"
    mv "${WORK_DIR}/temp/${base_name}.json" "${WORK_DIR}/anat.json"
    echo " -> T1w exported successfully."
else
    echo " -> T1w not found!"
fi
rm -rf ${WORK_DIR}/temp
