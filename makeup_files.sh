#!/bin/bash
rm -rf nii_files/*
mv -f pyOpenNFT-setting/NF_Data_* nii_files/
mv -f pyOpenNFT-setting/ROIs/* nii_files/
mv -f pyOpenNFT-setting/settings/* nii_files/
mv -f pyOpenNFT-setting/weights/* nii_files/
mv -f pyOpenNFT-setting/*.* nii_files/

echo -n "Please input subject ID (like hyh_sub-00 or sub-00):"
read -r subj
today=$(date +%Y%m%d)
mv nii_files /mnt/d/Data_RT/${today}_${subj}
mkdir nii_files
