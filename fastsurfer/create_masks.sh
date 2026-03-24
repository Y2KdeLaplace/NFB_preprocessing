#!/bin/bash
# 4_export_online_files.sh

BIDS_DIR=$1
SUB=$2
FINAL_TARGET_DIR=$3
DERIVATIVES_DIR="$BIDS_DIR/derivatives"

OUTPUT_DIR="$DERIVATIVES_DIR/$SUB/func"
FS_MRI_DIR="$DERIVATIVES_DIR/$SUB/mri"


mkdir -p $FINAL_TARGET_DIR
export FSLOUTPUTTYPE=NIFTI
cd $OUTPUT_DIR

echo ">>> 1. 生成参考相 (MC_Templ.nii) -> 基于运动校正后的 Mean EPI..."
fslmaths mean_epi.nii.gz $FINAL_TARGET_DIR/MC_Templ.nii

echo ">>> 2. 生成结构像 (T1.nii) -> 保持原生高分辨率，不重采样..."
fslmaths T1_brain_fs.nii.gz $FINAL_TARGET_DIR/T1.nii

echo ">>> 3. 生成全脑掩膜 (WholeBrainMask_EPI.nii) -> 对齐并重采样到 EPI 网格..."
flirt \
  -in brainmask_bin.nii.gz \
  -ref mean_epi.nii.gz \
  -applyxfm -init t12epi.mat \
  -interp nearestneighbour \
  -out $FINAL_TARGET_DIR/WholeBrainMask_EPI.nii

echo ">>> 4. 生成左侧杏仁核 ROI (AMG_L.nii) -> 对齐并重采样到 EPI 网格..."
# 从 FastSurfer 图谱中提取 Label 18
mri_binarize \
  --i $FS_MRI_DIR/aparc.DKTatlas+aseg.deep.mgz \
  --match 18 \
  --o temp_amg_l_t1.nii.gz

# 投射到 EPI 空间
flirt \
  -in temp_amg_l_t1.nii.gz \
  -ref mean_epi.nii.gz \
  -applyxfm -init t12epi.mat \
  -interp nearestneighbour \
  -out $FINAL_TARGET_DIR/ROIs/AMG_L.nii

rm temp_amg_l_t1.nii.gz

echo ">>> 恭喜！所有最终文件已导出至指定文件夹: $FINAL_TARGET_DIR"
# 打印目标文件夹内容，方便核对
ls -lh $FINAL_TARGET_DIR