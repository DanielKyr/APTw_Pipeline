%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%   Run_APTw_Pipeline.m
%
%   Single-B1 3T APTw (CEST) analysis pipeline.
%
%   RUN Prepare_APTw_Data.m FIRST. That script does the one-time data
%   preparation (DICOM -> NIfTI -> motion correction) and writes the "_REG_"
%   NIfTI this one consumes. Analysis is kept separate from preparation on
%   purpose: motion correction is an iterative optimisation and is NOT
%   bit-reproducible, so if it re-ran here, re-running the analysis would
%   silently change its own input and you could never separate a real
%   processing improvement from registration noise (worth ~0.03 percentage
%   points of APTw bias - the reproducibility floor of the pipeline).
%
%   Everything this script calls lives in lib/ next to this file. The only
%   things NOT bundled are SPM12 and a few MATLAB toolboxes (see README.md).
%
%   WHAT THIS SCRIPT DOES, IN PLAIN LANGUAGE
%   -----------------------------------------------------------------
%   CEST (Chemical Exchange Saturation Transfer) MRI measures a brain
%   image repeatedly while applying a saturation pulse at many different
%   frequency offsets ("the Z-spectrum"). APTw is a contrast computed
%   from the asymmetry of that spectrum around the water peak. Two
%   things corrupt this measurement and must be corrected voxel-by-voxel
%   before APTw is meaningful:
%     - B0 inhomogeneity: the water peak isn't at exactly 0 ppm
%       everywhere, so "symmetric" offsets aren't really symmetric.
%     - B1 inhomogeneity: the actual saturation power delivered differs
%       from the nominal scanner setting, which changes the size of the
%       CEST effect independent of tissue.
%   A short separate scan called WASABI is used to map both B0 and B1
%   at every voxel, and that map is then used to correct the APTw data.
%   Steps below, in order: load the prepared (motion-corrected) Z-spectrum
%   -> fit the WASABI scan for B0/B1 -> correct the APTw Z-spectra for B0
%   -> normalize -> denoise -> correct for B1 -> compute MTRasym (the APTw
%   contrast), B1-detrended, in two fluid-suppression flavours.
%
%   FOLDER LAYOUT THIS SCRIPT EXPECTS PER SUBJECT
%   -----------------------------------------------------------------
%   <subject_folder>/
%       nii/                         populated by Prepare_APTw_Data.m; must
%                                     contain exactly one *_REG_*.nii
%       Zeval/                       created automatically; files land here
%                                     per subject, named after the subject
%                                     folder itself (<subjectID> below):
%           <subjectID>_APTw_results.mat        small - the APTw map + B0/B1
%                                                maps + QC info. Open this
%                                                first.
%           <subjectID>_APTw_full_Zspectra.mat  large - full Z-spectrum stacks,
%                                                only needed for deeper QA/reuse.
%           <subjectID>_WASABI_fit.mat          cached WASABI B0/B1 fit.
%
%   This script does NOT show figures or compare against a scanner/Olea
%   map - see Evaluate_APTw_Results.m for that, which reads the
%   <subjectID>_APTw_results.mat file this script writes.
%
%   The APTw series folder/filename must contain cfg.singleB1_id
%   (default 'APTw_001') and the WASABI series must contain
%   cfg.wasabi_id (default 'WASAB') - same convention the original
%   pipeline used.
%
%   NO SCANNER LOG FILES ARE USED. Every subject is assumed to have been
%   acquired with the same protocol, so the sequence parameters (B1, the
%   full saturation-offset list, etc.) live in ONE place -
%   lib/pipeline/aptw_sequence_config.m - shared with Prepare_APTw_Data.m
%   and reused for every subject, instead of being parsed per-subject from
%   a .log file. If a subject's protocol ever differs, either update that
%   file or process that subject separately.
%
%   ATTENTION - one thing this script cannot check for you:
%   if your B1 (slab-selective transmit) data differs in brightness
%   between slices, run FAUBATCH_B1map_Correction.m (in the original,
%   full cest_eval repo) on it BEFORE using this pipeline.
%
%   Authors of the original pipeline: Katrin M. Khakzar, Alexander
%   German, Angelika Mennecke, Kai Herz, Felix Glang, Moritz Zaiss.
%   Restructured 2026 into APTw_1B1_Pipeline_Streamlined_3T.m, then
%   repackaged as this self-contained project.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% ========================= SETUP (do not need to edit) =========================
% Everything this pipeline calls (besides SPM12) lives in lib/ and bin/
% right next to this file. Add them to the path and fail fast with a
% clear message if a required external toolbox is missing.
projectRoot = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(projectRoot, 'lib')));

if isempty(which('spm'))
    error(['SPM12 was not found on the MATLAB path. This pipeline uses SPM for brain ' ...
           'segmentation and does not bundle it. Install SPM12 and run ' ...
           'addpath(''/path/to/spm12'') (or savepath) before running this script. ' ...
           'https://www.fil.ion.ucl.ac.uk/spm/software/spm12/']);
end

%% ========================= USER SETTINGS =========================
% Point this at EITHER a single subject folder OR a folder containing
% one sub-folder per subject - both are auto-detected (see SELECT
% SUBJECTS below), so it's fine either way. Leave it empty to pick
% interactively instead, via a standard folder dialog.
DATA_ROOT = '';

% All cfg fields (series IDs, cache-bypass toggles, mask/PCA/smoothing
% settings, ...) start from the shared defaults in lib/pipeline/aptw_default_cfg.m
% - the same defaults the GUI (gui/APTwPipelineApp.m) and Prepare_APTw_Data.m /
% Evaluate_APTw_Results.m use - then override below only what this script wants
% different from those defaults.
cfg = aptw_default_cfg();

% OFF by default. Sigma (voxels) of a per-slice, per-offset 2D Gaussian blur applied
% to the denoised Z-spectrum right before B1 correction - the original cest_eval repo
% has this exact step (same location in the pipeline) in
% FAU_Crw_lowB1muscle_Pipeline_IMPI04_3T.m, commented out there too, and NOT present
% in FAU_APTw_1B1_Pipeline_IMPI04_3T.m (the pipeline this script is otherwise a
% straight restructuring of). Tested against Olea's SC_ST_AUC map on 2 subjects:
% sigma=0.5 cut MAE ~12-16% with Pearson r roughly flat; sigma>=0.75 made both r and
% MAE worse. It's a real spatial-resolution tradeoff (blurs small lesions/hotspots
% along with noise) for a closer match to Olea's own (presumably also smoothed)
% output - not obviously "more correct" on its own, so it's left off unless you set it.
cfg.spatial_smooth_sigma = 0;

% true re-fits WASABI / redoes SPM segmentation even if a cached Zeval/*.mat exists.
cfg.force_wasabi       = false;
cfg.force_segmentation = false;

%% ========================= SELECT SUBJECTS =========================
% DATA_ROOT can point at EITHER a single subject folder (its immediate
% sub-folders are the raw DICOM SERIES, e.g. CEST008 itself, containing
% CEST008_..._APT, CEST008_..._WASABI, CEST008_..._dB0, ...) OR a folder
% that contains one such subject folder per SUBJECT. Both are detected
% automatically below - you don't need to know which level you're
% pointing at. If DATA_ROOT is not set above, a standard folder-picker
% dialog opens so you can choose it.
if isempty(DATA_ROOT)
    DATA_ROOT = uigetdir('F:\CEST\Patient Data', 'Select a subject folder, or a folder containing one sub-folder per subject');
    if isequal(DATA_ROOT, 0)
        error('No folder selected.');
    end
end

if looks_like_subject_folder(DATA_ROOT, cfg)
    Subject_Folders = {DATA_ROOT};
else
    d = dir(DATA_ROOT);
    d = d([d.isdir] & ~ismember({d.name}, {'.', '..'}));
    candidates = fullfile(DATA_ROOT, {d.name});
    candidates = candidates(cellfun(@isfolder, candidates));
    isSubject  = cellfun(@(f) looks_like_subject_folder(f, cfg), candidates);
    if any(~isSubject)
        fprintf(['Skipping %d sub-folder(s) of %s that don''t look like subject folders ' ...
            '(no nii/*%s*.nii + nii/*%s*.nii, and no series sub-folder matching "%s"):\n'], ...
            nnz(~isSubject), DATA_ROOT, cfg.singleB1_id, cfg.wasabi_id, cfg.wasabi_id);
        fprintf('  %s\n', candidates{~isSubject});
    end
    Subject_Folders = candidates(isSubject);
end
fprintf('Found %d subject folder(s) to process.\n', numel(Subject_Folders));

%% ========================= RUN THE PIPELINE =========================
results = cell(numel(Subject_Folders), 1);
failed  = false(numel(Subject_Folders), 1);
for s = 1:numel(Subject_Folders)
    fprintf('\n===== Subject %d/%d: %s =====\n', s, numel(Subject_Folders), Subject_Folders{s});
    try
        results{s} = run_APTw_subject(Subject_Folders{s}, cfg);
        [~, subjID] = fileparts(Subject_Folders{s});
        fprintf('Done. Results saved to %s\n', ...
            fullfile(Subject_Folders{s}, 'Zeval', [subjID '_APTw_results.mat']));
    catch ME
        failed(s) = true;
        warning('FAILED for %s:\n  %s', Subject_Folders{s}, ME.message);
    end
end

fprintf('\n===== Summary =====\n%d/%d subjects completed successfully.\n', ...
    nnz(~failed), numel(Subject_Folders));
if any(failed)
    fprintf('Failed:\n'); fprintf('  %s\n', Subject_Folders{failed});
end
