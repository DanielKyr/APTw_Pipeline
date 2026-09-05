function [correctedImg, biasFieldImg] = RunSPM_BFC(origImg)
% RUNSPM_BFC  Bias-field-corrects origImg via SPM unified segmentation, using
% the segmentation only as a means to estimate the bias field (all tissue
% class outputs are disabled below) - correctedImg is the bias-corrected
% image SPM writes ('m'-prefixed); biasFieldImg is the raw bias field itself
% ('BiasField_'-prefixed), returned so a caller can reuse it on OTHER images
% via simple division instead of re-running this (expensive, and unreliable
% on low-contrast input) segmentation once per image - see CEST_MOCO_spm.m's
% header comment for why that matters.

%get spm version and path
spm_Version = which('spm');
if isempty(spm_Version)
    error('SPM not found!');
end
[spm_path, ~, ~] = fileparts(spm_Version);
matlabbatch{1}.spm.spatial.preproc.channel.vols = {[origImg ',1']};
matlabbatch{1}.spm.spatial.preproc.channel.biasreg = 0.001;
matlabbatch{1}.spm.spatial.preproc.channel.biasfwhm = 30;
matlabbatch{1}.spm.spatial.preproc.channel.write = [1 1]; % [bias field, bias-corrected image] - both written now so the field can be reused
matlabbatch{1}.spm.spatial.preproc.tissue(1).tpm = {[spm_path '\tpm\TPM.nii,1']};
matlabbatch{1}.spm.spatial.preproc.tissue(1).ngaus = 1;
matlabbatch{1}.spm.spatial.preproc.tissue(1).native = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(1).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(2).tpm = {[spm_path '\tpm\TPM.nii,1']};
matlabbatch{1}.spm.spatial.preproc.tissue(2).ngaus = 1;
matlabbatch{1}.spm.spatial.preproc.tissue(2).native = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(2).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(3).tpm = {[spm_path '\tpm\TPM.nii,1']};
matlabbatch{1}.spm.spatial.preproc.tissue(3).ngaus = 2;
matlabbatch{1}.spm.spatial.preproc.tissue(3).native = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(3).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(4).tpm = {[spm_path '\tpm\TPM.nii,1']};
matlabbatch{1}.spm.spatial.preproc.tissue(4).ngaus = 3;
matlabbatch{1}.spm.spatial.preproc.tissue(4).native = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(4).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(5).tpm = {[spm_path '\tpm\TPM.nii,1']};
matlabbatch{1}.spm.spatial.preproc.tissue(5).ngaus = 4;
matlabbatch{1}.spm.spatial.preproc.tissue(5).native = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(5).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(6).tpm = {[spm_path '\tpm\TPM.nii,1']};
matlabbatch{1}.spm.spatial.preproc.tissue(6).ngaus = 2;
matlabbatch{1}.spm.spatial.preproc.tissue(6).native = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(6).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.warp.mrf = 1;
matlabbatch{1}.spm.spatial.preproc.warp.cleanup = 1;
matlabbatch{1}.spm.spatial.preproc.warp.reg = [0 0.001 0.5 0.05 0.2];
matlabbatch{1}.spm.spatial.preproc.warp.affreg = 'mni';
matlabbatch{1}.spm.spatial.preproc.warp.fwhm = 0;
matlabbatch{1}.spm.spatial.preproc.warp.samp = 3;
matlabbatch{1}.spm.spatial.preproc.warp.write = [0 0];
spm('defaults', 'FMRI');
spm_jobman('run', matlabbatch, cell(0,1));

[fp, fn, fe] = fileparts(origImg);
correctedImg = fullfile(fp, ['m' fn fe]);
biasFieldCandidates = dir(fullfile(fp, ['BiasField_' fn '*']));
if isempty(biasFieldCandidates)
    error('RunSPM_BFC:noBiasField', ...
        'Expected a BiasField_%s* output next to %s but found none - SPM may have changed its output naming convention.', fn, origImg);
end
biasFieldImg = fullfile(biasFieldCandidates(1).folder, biasFieldCandidates(1).name);

end