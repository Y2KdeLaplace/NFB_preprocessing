#!/bin/bash
# Written by Yiheng Hu (2026.3.30)
export FSLOUTPUTTYPE=NIFTI

BIDS_DIR=$1
SUB_ID=$2
TARGET_DIR=$3
mkdir -p $TARGET_DIR

DERIVATIVES_DIR="$BIDS_DIR/derivatives"
FS_MRI_DIR="$DERIVATIVES_DIR/$SUB_ID/mri"

OUTPUT_DIR="$DERIVATIVES_DIR/$SUB_ID/func"
mkdir -p $OUTPUT_DIR
cd $OUTPUT_DIR


echo ">>> 0. 检查 Fieldmap 并从 BIDS JSON 提取参数..."
FMAP_MAG="$BIDS_DIR/$SUB_ID/fmap/${SUB_ID}_magnitude1.nii.gz"
FMAP_PHASE="$BIDS_DIR/$SUB_ID/fmap/${SUB_ID}_phasediff.nii.gz"
FMAP_PHASE_JSON="$BIDS_DIR/$SUB_ID/fmap/${SUB_ID}_phasediff.json"
FUNC_JSON="$BIDS_DIR/$SUB_ID/func/${SUB_ID}_task-rest_bold.json"

FMAP_ARGS=""
if [ -f "$FMAP_MAG" ] && [ -f "$FMAP_PHASE" ] && [ -f "$FMAP_PHASE_JSON" ] && [ -f "$FUNC_JSON" ]; then
    echo ">>> 检测到 Fieldmap 和 JSON 配置文件，正在自动解析参数..."
    
    # 提取 EchoTime1 和 EchoTime2 (单位：秒)
    TE1=$(jq -r '.EchoTime1' $FMAP_PHASE_JSON)
    TE2=$(jq -r '.EchoTime2' $FMAP_PHASE_JSON)
    
    # 计算 Delta TE (单位：毫秒)，fsl_prepare_fieldmap 要求输入毫秒
    DELTA_TE=$(echo "($TE2 - $TE1) * 1000" | bc -l)
    echo "  -> 解析到 Delta TE: $DELTA_TE ms"

    # 提取 EffectiveEchoSpacing (单位：秒，FSL 接收秒)
    ECHO_SPACING=$(jq -r '.EffectiveEchoSpacing' $FUNC_JSON)
    echo "  -> 解析到 EffectiveEchoSpacing: $ECHO_SPACING s"

    # 提取 PhaseEncodingDirection 并将其映射到 FSL 格式 (BIDS: i, j, k -> FSL: x, y, z)
    PEDIR_BIDS=$(jq -r '.PhaseEncodingDirection' $FUNC_JSON)
    case $PEDIR_BIDS in
        i)  PEDIR_FSL="x" ;;
        i-) PEDIR_FSL="-x" ;;
        j)  PEDIR_FSL="y" ;;
        j-) PEDIR_FSL="-y" ;;
        k)  PEDIR_FSL="z" ;;
        k-) PEDIR_FSL="-z" ;;
        *)  echo "ERROR: 未知的相位编码方向 $PEDIR_BIDS"; exit ;;
    esac
    echo "  -> 解析到 PhaseEncodingDirection: $PEDIR_BIDS (映射为 FSL 格式: $PEDIR_FSL)"

    # 提取 Magnitude 脑掩码
    hd-bet -i $FMAP_MAG -o fmap_mag_brain.nii.gz
    
    # 转换 PhaseDiff 为 Rads
    fsl_prepare_fieldmap SIEMENS $FMAP_PHASE fmap_mag_brain.nii.gz fmap_rads $DELTA_TE
    
    # 构建自动参数
    FMAP_ARGS="--fmap=fmap_rads --fmapmag=$FMAP_MAG --fmapmagbrain=fmap_mag_brain.nii.gz --echospacing=$ECHO_SPACING --pedir=$PEDIR_FSL"
else
    echo ">>> 未检测到完整的 Fieldmap 或 JSON 配置文件，将执行无畸变校正的标准配准..."
fi


echo ">>> 1. 提取最后一个TR volume作为参考相"
EPI_FILE="$BIDS_DIR/$SUB_ID/func/${SUB_ID}_task-rest_bold.nii.gz" 

num_trs=$(fslval $EPI_FILE dim4) # 获取总 TR 数 (dim4)
last_index=$((num_trs - 1)) # 计算最后一个 TR 的索引 (N-1)
fslroi $EPI_FILE last_epi.nii $last_index 1


echo ">>> 2. 准备 T1 和白质特征..."
mri_convert $FS_MRI_DIR/orig.mgz T1_fs.nii
mri_binarize --i $FS_MRI_DIR/mask.mgz --min 0.5 --o brainmask_bin.nii.gz
fslmaths T1_fs.nii -mas brainmask_bin.nii.gz T1_brain_fs.nii
mri_binarize --i $FS_MRI_DIR/aparc.DKTatlas+aseg.deep.mgz \
             --match 2 41 7 46 16 251 252 253 254 255 \
             --o wm_mask_fs.nii.gz


echo ">>> 3. 运行 FSL epi_reg 高精度配准..."
epi_reg \
  --epi=last_epi.nii \
  --t1=T1_fs.nii \
  --t1brain=T1_brain_fs.nii \
  --wmseg=wm_mask_fs.nii.gz \
  --out=epi2t1 $FMAP_ARGS

echo ">>> 计算逆向变换矩阵 (T1 到 EPI 空间)..."
if [ -f "epi2t1_warp.nii" ] || [ -f "epi2t1_warp.nii.gz" ]; then
    echo "  -> 检测到 Fieldmap 形变场，正在计算逆向非线性 Warp..."
    invwarp --ref=last_epi.nii --warp=epi2t1_warp --out=t12epi_warp
else
    echo "  -> 未检测到形变场，仅计算逆向线性矩阵..."
    convert_xfm -omat t12epi.mat -inverse epi2t1.mat
fi


echo ">>> 4. 导出目标文件："
echo ">>>        生成全脑掩膜 (WholeBrainMask_EPI.nii) -> 对齐并重采样到 EPI 网格"
if [ -f "t12epi_warp.nii" ] || [ -f "t12epi_warp.nii.gz" ]; then
    echo "        -> 使用非线性 Warp 投射全脑掩膜 (包含畸变映射)..."
    applywarp --ref=last_epi.nii \
              --in=brainmask_bin.nii.gz \
              --warp=t12epi_warp \
              --interp=nn \
              --out=$TARGET_DIR/WholeBrainMask_EPI.nii
else
    echo "        -> 使用线性矩阵投射全脑掩膜..."
    flirt -in brainmask_bin.nii.gz \
          -ref last_epi.nii \
          -applyxfm -init t12epi.mat \
          -interp nearestneighbour \
          -out $TARGET_DIR/WholeBrainMask_EPI.nii
fi
echo ">>>        生成参考相 (MC_Templ.nii)"
mv last_epi.nii $TARGET_DIR/MC_Templ.nii
echo ">>>        生成结构像 (T1.nii)"
mv T1_brain_fs.nii $TARGET_DIR/T1.nii
