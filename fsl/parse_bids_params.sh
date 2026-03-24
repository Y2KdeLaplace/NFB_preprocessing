#!/bin/bash
# Module: Extract physical parameters from BIDS JSON files

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <BIDS_ROOT> <SUB_ID> [TASK_NAME]" >&2
    exit 1
fi

BIDS_ROOT=$1
SUB_ID=$2
TASK_NAME=${3:-rest}

EPI_JSON="${BIDS_ROOT}/${SUB_ID}/func/${SUB_ID}_task-${TASK_NAME}_bold.json"
FMAP_PH_JSON="${BIDS_ROOT}/${SUB_ID}/fmap/${SUB_ID}_phasediff.json"

if [ ! -f "$EPI_JSON" ]; then
    echo "ERROR: $EPI_JSON not found. Cannot parse EPI parameters." >&2
    exit 1
fi

# 1. Parse Phase Encoding Direction
pedir_raw=$(grep -oP '"PhaseEncodingDirection"\s*:\s*"\K[^"]+' "$EPI_JSON" 2>/dev/null)
case "$pedir_raw" in
    "i")  EPI_PEDIR="x"  ;;
    "i-") EPI_PEDIR="-x" ;;
    "j")  EPI_PEDIR="y"  ;;
    "j-") EPI_PEDIR="-y" ;;
    "k")  EPI_PEDIR="z"  ;;
    "k-") EPI_PEDIR="-z" ;;
    *)    
        echo "ERROR: Unrecognized PhaseEncodingDirection format: $pedir_raw" >&2
        exit 1 
        ;;
esac

# 2. Parse Effective Echo Spacing
EPI_ECHO_SPACING=$(grep -oP '"EffectiveEchoSpacing"\s*:\s*\K[\d\.]+' "$EPI_JSON" 2>/dev/null)
if [ -z "$EPI_ECHO_SPACING" ]; then
    echo "ERROR: 'EffectiveEchoSpacing' not found in EPI JSON!" >&2
    exit 1
fi

# 3. Calculate Delta TE (Only if Fieldmap JSON exists)
DELTA_TE="N/A"
if [ -f "$FMAP_PH_JSON" ]; then
    te1=$(grep -oP '"EchoTime1"\s*:\s*\K[\d\.]+' "$FMAP_PH_JSON" 2>/dev/null)
    te2=$(grep -oP '"EchoTime2"\s*:\s*\K[\d\.]+' "$FMAP_PH_JSON" 2>/dev/null)
    
    if [ -n "$te1" ] && [ -n "$te2" ]; then
        diff=$(echo "scale=5; ($te2 - $te1) * 1000" | bc)
        DELTA_TE=${diff#-}
        
        if (( $(echo "$DELTA_TE == 0" | bc -l) )); then
            echo "ERROR: Calculated Delta TE is 0. Both echo times are identical." >&2
            exit 1
        fi
    else
        echo "ERROR: Fieldmap JSON exists but EchoTime1 or EchoTime2 are missing!" >&2
        exit 1
    fi
fi

echo "$EPI_PEDIR $EPI_ECHO_SPACING $DELTA_TE"