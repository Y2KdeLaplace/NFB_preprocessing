function spm_preprocess_nfb()

spm_path   = '/Users/zhangxuelei/Desktop/上机课251015/spm';     

anat_nii   = '/Volumes/rtfmri/nii_files/raw_nii/20260317_RT_02_RT_T1_MPRAGE_iPAT2_20260317100235_3.nii';
bold_nii   = '/Volumes/rtfmri/nii_files/raw_nii/loc_ep2d_bold_TR2000_LOC_20260317100235_11.nii';

atlas_nii  = '/Users/zhangxuelei/Desktop/amygdala_L.nii';        
roi_name   = 'AMG_L';

work_dir   = '/Volumes/rtfmri/nii_files/spm';
target_dir = '/Volumes/rtfmri/nii_files/pyOpenNFT-setting';
roi_dir    = fullfile(target_dir, 'ROIs');

padding_trs = 3;         
wb_thr      = 0.5;       
roi_thr     = 0.5;        

addpath(spm_path);
spm('Defaults','fMRI');
spm_jobman('initcfg');

if ~exist(work_dir,'dir'), mkdir(work_dir); end
if ~exist(target_dir,'dir'), mkdir(target_dir); end
if ~exist(roi_dir,'dir'), mkdir(roi_dir); end

fprintf('\n=== Start SPM atlas-label amygdala -> EPI pipeline ===\n');

Vbold = spm_vol(bold_nii);
nvol = numel(Vbold);
if nvol <= padding_trs
    error('bold.nii has %d volumes, cannot discard %d TRs.', nvol, padding_trs);
end

epi_list = cell(nvol - padding_trs, 1);
for k = (padding_trs + 1):nvol
    epi_list{k - padding_trs} = sprintf('%s,%d', bold_nii, k);
end

matlabbatch = {};
matlabbatch{1}.spm.spatial.realign.estwrite.data = {epi_list};
matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.quality = 0.9;
matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.sep = 4;
matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.fwhm = 5;
matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.rtm = 1;
matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.interp = 2;
matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.wrap = [0 0 0];
matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.weight = '';
matlabbatch{1}.spm.spatial.realign.estwrite.roptions.which = [2 1];
matlabbatch{1}.spm.spatial.realign.estwrite.roptions.interp = 4;
matlabbatch{1}.spm.spatial.realign.estwrite.roptions.wrap = [0 0 0];
matlabbatch{1}.spm.spatial.realign.estwrite.roptions.mask = 1;
matlabbatch{1}.spm.spatial.realign.estwrite.roptions.prefix = 'r';
spm_jobman('run', matlabbatch);

[pb, nb, eb] = fileparts(bold_nii);
mean_epi = fullfile(pb, ['mean' nb eb]);
if ~exist(mean_epi, 'file')
    error('mean EPI not found: %s', mean_epi);
end

copyfile(mean_epi, fullfile(target_dir, 'MC_Templ.nii'));
fprintf('Saved MC_Templ.nii\n');

matlabbatch = {};
matlabbatch{1}.spm.spatial.coreg.estimate.ref = {mean_epi};
matlabbatch{1}.spm.spatial.coreg.estimate.source = {anat_nii};
matlabbatch{1}.spm.spatial.coreg.estimate.other = {''};
matlabbatch{1}.spm.spatial.coreg.estimate.eoptions.cost_fun = 'nmi';
matlabbatch{1}.spm.spatial.coreg.estimate.eoptions.sep = [4 2];
matlabbatch{1}.spm.spatial.coreg.estimate.eoptions.tol = ...
    [0.02 0.02 0.02 0.001 0.001 0.001 0.01 0.01 0.01 0.001 0.001 0.001];
matlabbatch{1}.spm.spatial.coreg.estimate.eoptions.fwhm = [7 7];
spm_jobman('run', matlabbatch);

matlabbatch = {};
tpm = fullfile(spm('Dir'), 'tpm', 'TPM.nii');

matlabbatch{1}.spm.spatial.preproc.channel.vols = {anat_nii};
matlabbatch{1}.spm.spatial.preproc.channel.biasreg = 0.001;
matlabbatch{1}.spm.spatial.preproc.channel.biasfwhm = 60;
matlabbatch{1}.spm.spatial.preproc.channel.write = [0 1];

for t = 1:6
    matlabbatch{1}.spm.spatial.preproc.tissue(t).tpm = {sprintf('%s,%d', tpm, t)};
end

matlabbatch{1}.spm.spatial.preproc.tissue(1).ngaus = 1;
matlabbatch{1}.spm.spatial.preproc.tissue(1).native = [1 0];
matlabbatch{1}.spm.spatial.preproc.tissue(1).warped = [0 0];

matlabbatch{1}.spm.spatial.preproc.tissue(2).ngaus = 1;
matlabbatch{1}.spm.spatial.preproc.tissue(2).native = [1 0];
matlabbatch{1}.spm.spatial.preproc.tissue(2).warped = [0 0];

matlabbatch{1}.spm.spatial.preproc.tissue(3).ngaus = 2;
matlabbatch{1}.spm.spatial.preproc.tissue(3).native = [1 0];
matlabbatch{1}.spm.spatial.preproc.tissue(3).warped = [0 0];

matlabbatch{1}.spm.spatial.preproc.tissue(4).ngaus = 3;
matlabbatch{1}.spm.spatial.preproc.tissue(4).native = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(4).warped = [0 0];

matlabbatch{1}.spm.spatial.preproc.tissue(5).ngaus = 4;
matlabbatch{1}.spm.spatial.preproc.tissue(5).native = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(5).warped = [0 0];

matlabbatch{1}.spm.spatial.preproc.tissue(6).ngaus = 2;
matlabbatch{1}.spm.spatial.preproc.tissue(6).native = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(6).warped = [0 0];

matlabbatch{1}.spm.spatial.preproc.warp.mrf = 1;
matlabbatch{1}.spm.spatial.preproc.warp.cleanup = 1;
matlabbatch{1}.spm.spatial.preproc.warp.reg = [0 0.001 0.5 0.05 0.2];
matlabbatch{1}.spm.spatial.preproc.warp.affreg = 'mni';
matlabbatch{1}.spm.spatial.preproc.warp.fwhm = 0;
matlabbatch{1}.spm.spatial.preproc.warp.samp = 3;
matlabbatch{1}.spm.spatial.preproc.warp.write = [1 1];  
spm_jobman('run', matlabbatch);

[pa, na, ea] = fileparts(anat_nii);
c1  = fullfile(pa, ['c1' na ea]);
c2  = fullfile(pa, ['c2' na ea]);
c3  = fullfile(pa, ['c3' na ea]);
mT1 = fullfile(pa, ['m' na ea]);
iy  = fullfile(pa, ['iy_' na ea]);

if ~exist(iy, 'file')
    error('Inverse deformation field not found: %s', iy);
end

copyfile(mT1, fullfile(target_dir, 'T1.nii'));
fprintf('Saved T1.nii\n');

matlabbatch = {};
matlabbatch{1}.spm.util.imcalc.input = {c1; c2; c3};
matlabbatch{1}.spm.util.imcalc.output = 'tmp_WholeBrainMask_T1.nii';
matlabbatch{1}.spm.util.imcalc.outdir = {work_dir};
matlabbatch{1}.spm.util.imcalc.expression = sprintf('(i1+i2+i3)>%g', wb_thr);
matlabbatch{1}.spm.util.imcalc.var = struct('name', {}, 'value', {});
matlabbatch{1}.spm.util.imcalc.options.dmtx = 0;
matlabbatch{1}.spm.util.imcalc.options.mask = 0;
matlabbatch{1}.spm.util.imcalc.options.interp = 0;
matlabbatch{1}.spm.util.imcalc.options.dtype = 4;
spm_jobman('run', matlabbatch);

tmp_wb_t1 = fullfile(work_dir, 'tmp_WholeBrainMask_T1.nii');

matlabbatch = {};
matlabbatch{1}.spm.spatial.coreg.write.ref = {mean_epi};
matlabbatch{1}.spm.spatial.coreg.write.source = {tmp_wb_t1};
matlabbatch{1}.spm.spatial.coreg.write.roptions.interp = 0;
matlabbatch{1}.spm.spatial.coreg.write.roptions.wrap = [0 0 0];
matlabbatch{1}.spm.spatial.coreg.write.roptions.mask = 1;
matlabbatch{1}.spm.spatial.coreg.write.roptions.prefix = 'r';
spm_jobman('run', matlabbatch);

wb_epi = fullfile(work_dir, 'rtmp_WholeBrainMask_T1.nii');
copyfile(wb_epi, fullfile(target_dir, 'WholeBrainMask_EPI.nii'));
fprintf('Saved WholeBrainMask_EPI.nii\n');

V_atlas = spm_vol(atlas_nii);
Y_atlas = spm_read_vols(V_atlas);

roi_mni = uint8(Y_atlas > 0);

roi_mni_file = fullfile(work_dir, sprintf('%s_MNI.nii', roi_name));
Vout = V_atlas;
Vout.fname = roi_mni_file;
Vout.dt = [spm_type('uint8') 0];
spm_write_vol(Vout, roi_mni);

fprintf('Saved MNI ROI: %s\n', roi_mni_file);
fprintf('nnz roi_mni = %d\n', nnz(roi_mni));

matlabbatch = {};
matlabbatch{1}.spm.util.defs.comp{1}.def = {iy};
matlabbatch{1}.spm.util.defs.out{1}.pull.fnames = {roi_mni_file};
matlabbatch{1}.spm.util.defs.out{1}.pull.savedir.saveusr = {work_dir};
matlabbatch{1}.spm.util.defs.out{1}.pull.interp = 0;
matlabbatch{1}.spm.util.defs.out{1}.pull.mask = 1;
matlabbatch{1}.spm.util.defs.out{1}.pull.fwhm = [0 0 0];
matlabbatch{1}.spm.util.defs.out{1}.pull.prefix = 'iw_';
spm_jobman('run', matlabbatch);

roi_native_t1 = fullfile(work_dir, ['iw_' roi_name '_MNI.nii']);
if ~exist(roi_native_t1, 'file')
    error('Native T1 ROI not found: %s', roi_native_t1);
end

matlabbatch = {};
matlabbatch{1}.spm.spatial.coreg.write.ref = {mean_epi};
matlabbatch{1}.spm.spatial.coreg.write.source = {roi_native_t1};
matlabbatch{1}.spm.spatial.coreg.write.roptions.interp = 0;
matlabbatch{1}.spm.spatial.coreg.write.roptions.wrap = [0 0 0];
matlabbatch{1}.spm.spatial.coreg.write.roptions.mask = 1;
matlabbatch{1}.spm.spatial.coreg.write.roptions.prefix = 'r';
spm_jobman('run', matlabbatch);

roi_epi = fullfile(work_dir, ['riw_' roi_name '_MNI.nii']);
if ~exist(roi_epi, 'file')
    error('EPI-space ROI not found: %s', roi_epi);
end

matlabbatch = {};
matlabbatch{1}.spm.util.imcalc.input = {roi_epi};
matlabbatch{1}.spm.util.imcalc.output = [roi_name '.nii'];
matlabbatch{1}.spm.util.imcalc.outdir = {roi_dir};
matlabbatch{1}.spm.util.imcalc.expression = sprintf('i1>%g', roi_thr);
matlabbatch{1}.spm.util.imcalc.var = struct('name', {}, 'value', {});
matlabbatch{1}.spm.util.imcalc.options.dmtx = 0;
matlabbatch{1}.spm.util.imcalc.options.mask = 0;
matlabbatch{1}.spm.util.imcalc.options.interp = 0;
matlabbatch{1}.spm.util.imcalc.options.dtype = 4;
spm_jobman('run', matlabbatch);

fprintf('Saved final ROI: %s\n', fullfile(roi_dir, [roi_name '.nii']));
fprintf('=== Finished successfully ===\n');

end