#!/bin/bash
# 2_epi_moco_and_mean.sh

BIDS_DIR=$1
SUB=$2
DERIVATIVES_DIR="$BIDS_DIR/derivatives"

EPI_FILE="$BIDS_DIR/$SUB/func/${SUB}_task-rest_bold.nii.gz" 
OUTPUT_DIR="$DERIVATIVES_DIR/$SUB/func"

mkdir -p $OUTPUT_DIR
cd $OUTPUT_DIR

echo ">>> 1. 提取 EPI 第一帧作为临时头动校正靶点..."
fslroi $EPI_FILE epi_first_frame.nii.gz 0 1

echo ">>> 2. 运行 MCFLIRT 进行全序列头动校正..."
mcflirt -in $EPI_FILE -out epi_moco.nii.gz -reffile epi_first_frame.nii.gz

echo ">>> 3. 计算头动校正后序列的均值 (生成高信噪比参考相)..."
fslmaths epi_moco.nii.gz -Tmean mean_epi.nii.gz

echo ">>> EPI 预处理完成！生成最终高质参考相：mean_epi.nii.gz"