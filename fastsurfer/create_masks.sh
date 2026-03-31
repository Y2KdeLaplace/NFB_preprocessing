#!/bin/bash
# Written by Yiheng Hu (2026.3.30)
export FSLOUTPUTTYPE=NIFTI

BIDS_DIR=$1
SUB_ID=$2
TARGET_DIR=$3
DERIVATIVES_DIR="$BIDS_DIR/derivatives"

OUTPUT_DIR="$DERIVATIVES_DIR/$SUB_ID/func"
FS_MRI_DIR="$DERIVATIVES_DIR/$SUB_ID/mri"

cd $OUTPUT_DIR
echo ">>> Final. 生成左侧杏仁核 ROI (AMG_L.nii)..."
# 从 FastSurfer 图谱中提取 Label 18
mri_binarize \
  --i $FS_MRI_DIR/aparc.DKTatlas+aseg.deep.mgz \
  --match 18 \
  --o temp_amg_l_t1.nii.gz

if [ -f "t12epi_warp.nii" ] || [ -f "t12epi_warp.nii.gz" ]; then
    echo "  -> 使用非线性 Warp 投射杏仁核 ROI (包含畸变映射)..."
    applywarp --ref=$TARGET_DIR/MC_Templ.nii \
              --in=temp_amg_l_t1.nii.gz \
              --warp=t12epi_warp \
              --interp=nn \
              --out=$TARGET_DIR/ROIs/AMG_L.nii
else
    echo "  -> 使用线性矩阵投射杏仁核 ROI..."
    flirt -in temp_amg_l_t1.nii.gz \
          -ref $TARGET_DIR/MC_Templ.nii \
          -applyxfm -init t12epi.mat \
          -interp nearestneighbour \
          -out $TARGET_DIR/ROIs/AMG_L.nii
fi
rm temp_amg_l_t1.nii.gz

echo ">>> 恭喜！所有最终文件已导出至指定文件夹: $TARGET_DIR"
tree $TARGET_DIR