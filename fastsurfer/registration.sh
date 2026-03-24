#!/bin/bash
# 3_registration_with_fmap.sh

BIDS_DIR=$1
SUB=$2
DERIVATIVES_DIR="$BIDS_DIR/derivatives"

OUTPUT_DIR="$DERIVATIVES_DIR/$SUB/func"
FS_MRI_DIR="$DERIVATIVES_DIR/$SUB/mri"

cd $OUTPUT_DIR

echo ">>> 1. 准备 T1 和白质特征..."
mri_convert $FS_MRI_DIR/orig.mgz T1_fs.nii.gz
mri_binarize --i $FS_MRI_DIR/mask.mgz --min 0.5 --o brainmask_bin.nii.gz
fslmaths T1_fs.nii.gz -mas brainmask_bin.nii.gz T1_brain_fs.nii.gz
mri_binarize --i $FS_MRI_DIR/aparc.DKTatlas+aseg.deep.mgz \
             --match 2 41 7 46 16 251 252 253 254 255 \
             --o wm_mask_fs.nii.gz

echo ">>> 2. 检查 Fieldmap 并从 BIDS JSON 提取参数..."
FMAP_MAG="$BIDS_DIR/$SUB/fmap/${SUB}_magnitude1.nii.gz"
FMAP_PHASE="$BIDS_DIR/$SUB/fmap/${SUB}_phasediff.nii.gz"
FMAP_PHASE_JSON="$BIDS_DIR/$SUB/fmap/${SUB}_phasediff.json"
FUNC_JSON="$BIDS_DIR/$SUB/func/${SUB}_task-rest_bold.json"

FMAP_ARGS=""
if [ -f "$FMAP_MAG" ] && [ -f "$FMAP_PHASE" ] && [ -f "$FMAP_PHASE_JSON" ] && [ -f "$FUNC_JSON" ]; then
    echo ">>> 检测到 Fieldmap 和 JSON 配置文件，正在自动解析参数..."
    
    # 提取 EchoTime1 和 EchoTime2 (单位：秒)
    TE1=$(jq -r '.EchoTime1' $FMAP_PHASE_JSON)
    TE2=$(jq -r '.EchoTime2' $FMAP_PHASE_JSON)
    
    # 计算 Delta TE (单位：毫秒)，fsl_prepare_fieldmap 要求输入毫秒
    DELTA_TE=$(echo "($TE2 - $TE1) * 1000" | bc -l)
    # 格式化保留两位小数
    DELTA_TE=$(printf "%.2f" $DELTA_TE)
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
        *)  echo "警告: 未知的相位编码方向 $PEDIR_BIDS，默认使用 y"; PEDIR_FSL="y" ;;
    esac
    echo "  -> 解析到 PhaseEncodingDirection: $PEDIR_BIDS (映射为 FSL 格式: $PEDIR_FSL)"

    # 提取 Magnitude 脑掩码
    fslmaths $FMAP_MAG -Tmean fmap_mag.nii.gz
    bet fmap_mag.nii.gz fmap_mag_brain.nii.gz
    
    # 转换 PhaseDiff 为 Rads
    fsl_prepare_fieldmap SIEMENS $FMAP_PHASE fmap_mag_brain.nii.gz fmap_rads $DELTA_TE
    
    # 构建自动参数
    FMAP_ARGS="--fmap=fmap_rads --fmapmag=fmap_mag.nii.gz --fmapmagbrain=fmap_mag_brain.nii.gz --echospacing=$ECHO_SPACING --pedir=$PEDIR_FSL"
else
    echo ">>> 未检测到完整的 Fieldmap 或 JSON 配置文件，将执行无畸变校正的标准配准..."
fi

echo ">>> 3. 运行 FSL epi_reg 高精度配准..."
epi_reg \
  --epi=mean_epi.nii.gz \
  --t1=T1_fs.nii.gz \
  --t1brain=T1_brain_fs.nii.gz \
  --wmseg=wm_mask_fs.nii.gz \
  --out=epi2t1 $FMAP_ARGS

echo ">>> 计算逆向变换矩阵 (T1 到 EPI 空间)..."
convert_xfm -omat t12epi.mat -inverse epi2t1.mat