#!/bin/bash

# Define absolute paths. Use wslpath to convert Windows paths to WSL paths if needed.
BIDS_DIR=$1
OUTPUT_DIR="$2/output"
WORK_DIR="$2/work"
FS_LICENSE="/home/wanglab/freesurfer/license.txt"

# Create required directories
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${WORK_DIR}"

echo "Starting fMRIPrep with high-performance settings..."

# Run fMRIPrep via Docker
# -v lines map host directories to container directories
# --nprocs 20 utilizes 20 logical threads of the i7-14700KF
# --mem_mb 48000 allocates ~48GB RAM for fast processing
# --fs-no-reconall disables FreeSurfer surface reconstruction for speed
docker run -ti --rm \
    -v "${BIDS_DIR}":/data:ro \
    -v "${OUTPUT_DIR}":/out \
    -v "${WORK_DIR}":/work \
    -v "${FS_LICENSE}":/opt/freesurfer/license.txt:ro \
    nipreps/fmriprep:latest \
    /data /out participant \
    --participant-label 01 \
    --output-spaces T1w MNI152NLin2009cAsym func \
    --fs-no-reconall \
    --nprocs 8 \
    --mem_mb 8096 \
    --stop-on-first-crash \
    -w /work

echo "fMRIPrep finished! Check the .html report in ${OUTPUT_DIR}"
