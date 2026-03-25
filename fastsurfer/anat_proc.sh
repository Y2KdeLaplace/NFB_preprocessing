#!/bin/bash
# 1_fastsurfer_bids_conda.sh

# ================= 配置区 =================
BIDS_DIR=$1
SUB=$2
DERIVATIVES_DIR="$BIDS_DIR/derivatives"

# FastSurfer path
FASTSURFER_HOME=$HOME/FastSurfer 

T1_FILE="$BIDS_DIR/$SUB/anat/${SUB}_T1w.nii.gz"
# ==========================================

mkdir -p $DERIVATIVES_DIR

echo ">>> 检查输入文件..."
if [ ! -f "$T1_FILE" ]; then
    echo "错误: 未找到 T1 文件 ($T1_FILE)"
    exit 1
fi

echo ">>> 启动 FastSurfer (GPU 加速)..."
$FASTSURFER_HOME/run_fastsurfer.sh \
  --t1 $T1_FILE \
  --sid $SUB \
  --sd $DERIVATIVES_DIR \
  --threads 4 \
  --seg_only \
  --no_cereb \
  --no_cc \
  --no_hypothal
echo ">>> 分割完成！"
