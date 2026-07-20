function [Segment,c_all] = CreateBinaryBrainmaskWithSPM(NiiFilename, threshold, idx4D, saveSegment, cleanup, use_c6)

arguments
    NiiFilename
    threshold = eps
    idx4D = 1
    saveSegment = true
    cleanup = true
    use_c6 = false
end


if nargin < 2 
    threshold = eps;
end

if nargin < 3 
    idx4D = 1;
    sprintf('segmentation performed on 1st image of stack')
else
    sprintf(['segmentation performed on image number ',num2str(idx4D),' of stack'])
end

%get spm version and path
spm_Version = which('spm');
if isempty(spm_Version)
    error('SPM not found!');
end

[spm_path, ~, ~] = fileparts(spm_Version);

% init dpm matlab batch
matlabbatch{1}.spm.spatial.preproc.channel.vols = {[NiiFilename ',' num2str(idx4D)]};
matlabbatch{1}.spm.spatial.preproc.channel.biasreg = 0.001;
matlabbatch{1}.spm.spatial.preproc.channel.biasfwhm = 30;
matlabbatch{1}.spm.spatial.preproc.channel.write = [0 1];
matlabbatch{1}.spm.spatial.preproc.tissue(1).tpm = {[spm_path '/tpm/TPM.nii,1']};
matlabbatch{1}.spm.spatial.preproc.tissue(1).ngaus = 1;
matlabbatch{1}.spm.spatial.preproc.tissue(1).native = [1 0];
matlabbatch{1}.spm.spatial.preproc.tissue(1).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(2).tpm = {[spm_path '/tpm/TPM.nii,2']};
matlabbatch{1}.spm.spatial.preproc.tissue(2).ngaus = 1;
matlabbatch{1}.spm.spatial.preproc.tissue(2).native = [1 0];
matlabbatch{1}.spm.spatial.preproc.tissue(2).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(3).tpm = {[spm_path '/tpm/TPM.nii,3']};
%matlabbatch{1}.spm.spatial.preproc.tissue(3).ngaus = 2;
matlabbatch{1}.spm.spatial.preproc.tissue(3).ngaus = 1;
matlabbatch{1}.spm.spatial.preproc.tissue(3).native = [1 0];
matlabbatch{1}.spm.spatial.preproc.tissue(3).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(4).tpm = {[spm_path '/tpm/TPM.nii,4']};
matlabbatch{1}.spm.spatial.preproc.tissue(4).ngaus = 3;
matlabbatch{1}.spm.spatial.preproc.tissue(4).native = [1 0];
matlabbatch{1}.spm.spatial.preproc.tissue(4).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(5).tpm = {[spm_path '/tpm/TPM.nii,5']};
matlabbatch{1}.spm.spatial.preproc.tissue(5).ngaus = 4;
matlabbatch{1}.spm.spatial.preproc.tissue(5).native = [1 0];
matlabbatch{1}.spm.spatial.preproc.tissue(5).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.tissue(6).tpm = {[spm_path '/tpm/TPM.nii,6']};
matlabbatch{1}.spm.spatial.preproc.tissue(6).ngaus = 2;
matlabbatch{1}.spm.spatial.preproc.tissue(6).native = [1 0];
matlabbatch{1}.spm.spatial.preproc.tissue(6).warped = [0 0];
matlabbatch{1}.spm.spatial.preproc.warp.mrf = 1;
matlabbatch{1}.spm.spatial.preproc.warp.cleanup = 1;
matlabbatch{1}.spm.spatial.preproc.warp.reg = [0 0.001 0.5 0.05 0.2];
matlabbatch{1}.spm.spatial.preproc.warp.affreg = 'mni';
matlabbatch{1}.spm.spatial.preproc.warp.fwhm = 0;
matlabbatch{1}.spm.spatial.preproc.warp.samp = 3;
matlabbatch{1}.spm.spatial.preproc.warp.write = [0 0];

%run segmentation
spm('defaults', 'FMRI');
spm_jobman('run', matlabbatch, cell(0,1));

%get the GM, WM and CSF propability maps
[fp, fn ,fe] = fileparts(NiiFilename);
c1_filename = fullfile(fp, ['c1' fn fe]);
c2_filename = fullfile(fp, ['c2' fn fe]);
c3_filename = fullfile(fp, ['c3' fn fe]);
c4_filename = fullfile(fp, ['c4' fn fe]);
c5_filename = fullfile(fp, ['c5' fn fe]);
c6_filename = fullfile(fp, ['c6' fn fe]);
m_filename = fullfile(fp, ['m' fn fe]);

if ~exist(c1_filename, 'file') || ...
   ~exist(c2_filename, 'file') || ...
   ~exist(c3_filename, 'file') || ...
   ~exist(c4_filename, 'file') || ...
   ~exist(c5_filename, 'file') || ...
   ~exist(c6_filename, 'file') 

    error('Segmentation was not succesfull!');
end

c1_nii = spm_read_vols(spm_vol(c1_filename));
c2_nii = spm_read_vols(spm_vol(c2_filename));
c3_nii = spm_read_vols(spm_vol(c3_filename));
c4_nii = spm_read_vols(spm_vol(c4_filename));
c5_nii = spm_read_vols(spm_vol(c5_filename));
c6_nii = spm_read_vols(spm_vol(c6_filename));
% SM @ MPI: needed all masks in cell
c_all{1,1} = c1_nii; c_all{2,1} = c2_nii; c_all{3,1} = c3_nii;
c_all{4,1} = c4_nii; c_all{5,1} = c5_nii; c_all{6,1} = c6_nii;


%create binary mask from proability maps
if ~use_c6
    Segment = c1_nii+c2_nii+c3_nii>threshold;
else
    Segment = c6_nii == 0;
end
% go through slices and fill holes
for ii = 1: size(Segment,3)
    Segment(:,:,ii) = imfill(squeeze(Segment(:,:,ii)), 'holes');
end
% prepare segment for imgui pieline
Segment = double(Segment);
Segment(Segment == 0) = nan;
if nargin < 4
    saveSegment = true;
end
if saveSegment
    save(fullfile(fp, [fn '_Brainmask.mat']), 'Segment', 'c1_nii','c2_nii','c3_nii','c4_nii','c5_nii','c6_nii','c_all');
end

%clean up tissue masks
if nargin < 5
    cleanup = true;
end
if cleanup
    delete(c1_filename);
    delete(c2_filename);
    delete(c3_filename);
    delete(c4_filename);
    delete(c5_filename);
    delete(c6_filename);
    delete(m_filename);
end


end