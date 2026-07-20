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

cfg = struct();
cfg.singleB1_id  = 'APTw_001';   % substring identifying the CEST Z-spectrum series
cfg.wasabi_id    = 'WASAB';      % substring identifying the WASABI series
cfg.force_wasabi = false;        % true re-fits WASABI even if Zeval/<id>_WASABI_fit.mat exists
[cfg.aptw_seq, cfg.wasabi_seq] = aptw_sequence_config();  % shared with Prepare_APTw_Data.m

%% ========================= SELECT SUBJECTS =========================
% DATA_ROOT can point at EITHER a single subject folder (its immediate
% sub-folders are the raw DICOM SERIES, e.g. CEST008 itself, containing
% CEST008_..._APT, CEST008_..._WASABI, CEST008_..._dB0, ...) OR a folder
% that contains one such subject folder per SUBJECT. Both are detected
% automatically below - you don't need to know which level you're
% pointing at. If DATA_ROOT is not set above, a standard folder-picker
% dialog opens so you can choose it.
if isempty(DATA_ROOT)
    DATA_ROOT = uigetdir(pwd, 'Select a subject folder, or a folder containing one sub-folder per subject');
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


%% ===================================================================
%  ===================== local functions below =======================
%% ===================================================================

function out = run_APTw_subject(subjFolder, cfg)
% Runs the APTw evaluation for one subject folder. Returns the same struct
% that gets saved to Zeval/<subjectID>_APTw_results.mat.
%
% Expects Prepare_APTw_Data.m to have already produced the motion-corrected
% "_REG_" NIfTI. This script never converts DICOM or runs MOCO.

[~, subjectID] = fileparts(subjFolder); % used to name every file this run produces
niiFolder   = fullfile(subjFolder, 'nii');
zevalFolder = fullfile(subjFolder, 'Zeval');
if ~isfolder(zevalFolder), mkdir(zevalFolder); end

% ---- 1. Locate the prepared inputs.
wasabiFile = find_series_file(niiFolder, cfg.wasabi_id, numel(cfg.wasabi_seq.offsetlist_ppm));
reg = dir(fullfile(niiFolder, ['*' cfg.singleB1_id '*_REG_*.nii']));
if isempty(reg)
    error(['No motion-corrected ("_REG_") NIfTI found in %s.\n' ...
           'Run Prepare_APTw_Data.m on this subject first.'], niiFolder);
end
if numel(reg) > 1
    % Ambiguity here silently changes the input data, so refuse rather than guess.
    error(['Found %d motion-corrected NIfTI files in %s:\n  %s\n' ...
           'Leave exactly one so the analysis input is unambiguous.'], ...
           numel(reg), niiFolder, strjoin({reg.name}, sprintf('\n  ')));
end
regFile = fullfile(niiFolder, reg(1).name);
fprintf('Using prepared input: %s\n', reg(1).name);

% ---- 2. Load the motion-corrected Z-spectrum and segment the brain.
[M0_stack, Mz_stack, P] = load_niistack_with_config(regFile, cfg.aptw_seq);
P.Fit.Fit_Model        = 'MTRasym';
P.Fit.MOCO             = 'spm';
P.Fit.int_meth         = 'linear';
P.EVAL.B0_int_meth     = 'linear';   % B0 fit-grid interpolation
P.EVAL.splinesmoothing = 0.95;       % B0 smoothing-spline parameter

Segment = CreateBinaryBrainmaskWithSPM(regFile, 0.2, 1, 1, 1);  % 0.2 = tissue-probability threshold
if isempty(Segment(~isnan(Segment)))
    warning('Brain segmentation failed for %s - using the whole field of view instead.', subjFolder);
    Segment = ones(size(Segment));
end
Segment(:, :, [1:2 end-1:end]) = 0; % outermost two slices on each side are unreliable coverage

% ---- 4. WASABI fit for B0 (field offset) and B1 (transmit efficiency)
%         maps (reused from Zeval/<subjectID>_WASABI_fit.mat if already computed).
[B1map, dB0map] = ensure_wasabi_fit(niiFolder, wasabiFile, zevalFolder, subjectID, Segment, cfg);

if ~isequal(size(dB0map), size(M0_stack))
    error(['WASABI (%s) and APTw (%s) volumes have different matrix sizes. They must share ' ...
           'the same FOV/resolution for B0/B1 correction to be voxel-aligned - reslice one ' ...
           'to match the other before running this pipeline.'], mat2str(size(dB0map)), mat2str(size(M0_stack)));
end

% ---- 5. Correct each voxel's Z-spectrum for its local B0 offset
%         (using the WASABI dB0 map), then normalize to the M0 signal.
%
%      Two-step form, matching the original FAU_APTw_1B1_Pipeline_IMPI04_3T:
%        (a) MINFIND_SPLINE_3D fits a smoothing spline per voxel and evaluates it
%            on a DENSE offset grid (P.EVAL.w_fit, 0.01 ppm steps) -> yfit.
%        (b) B0_CORRECTION shifts by dB0 and interpolates that dense grid back to
%            the acquired offsets (P.EVAL.w_interp), using P.EVAL.B0_int_meth.
%      Do NOT replace this with MINFIND_SPLINE_AND_CORRECT_3D_withExt, which
%      evaluates the spline directly at cf_(w + dB0). That form returns finite but
%      wildly non-physical Z (hundreds to thousands instead of ~0.3-0.9) wherever the
%      per-voxel fit is degenerate or the shift lands outside the measured offset
%      range. Those few voxels then corrupt pcca_3D - a GLOBAL PCA - which shifts
%      every voxel in the map and adds a small bias.
[~, ~, yfit] = MINFIND_SPLINE_3D(Mz_stack, Segment, P);
Pfit               = change_w_fit(P);
Pfit.SEQ.w         = Pfit.EVAL.w_fit;   % the spline was evaluated on this dense grid
Pfit.EVAL.w_interp = P.SEQ.w;           % ...and is interpolated back to the acquired offsets
Mz_CORR            = B0_CORRECTION(yfit, dB0map, Pfit, Segment);

[Z_corrExt, ~, normType] = NORM_ZSTACK(Mz_CORR, M0_stack, P, Segment);
P.EVAL.normalizationType = normType;
P.EVAL.normalization     = 'M0_stack';

% ---- 6. Denoise via local PCA (first N components kept).
[Z_corrExt_denoised, used_components] = pcca_3D(Z_corrExt, P, 1:15, 0, Segment);  % keep first 15 PCs

% ---- 7. B1 correction: interpolate each voxel's Z-spectrum from the
%         (B1=0 baseline, measured-B1) pair to the mean nominal B1 of
%         this acquisition, using the WASABI B1 map.
B1_nominal = P.SEQ.B1;
Z_stack = zeros([size(Z_corrExt_denoised), 2]);
Z_stack(:, :, :, :, 2) = Z_corrExt_denoised;
Z_stack(:, :, :, :, 1) = repmat(Z_corrExt_denoised(:, :, :, end), 1, 1, 1, size(Z_corrExt_denoised, 4)); % Z(B1=0) baseline estimate
B1_input  = [0, B1_nominal];
B1_output = B1_nominal;
Z_stack_corr = Z_B1_correction(Z_stack, B1map, B1_input, B1_output, Segment, 'linear');
Z_final = Z_stack_corr(:, :, :, :, 1);

% ---- 8. MTRasym (the APTw contrast): B1-detrend, then both fluid-suppression
%         metrics. The detrend is unconditional - it improved r, bias, LoA and
%         MAE together, so there is no reason to run without it.
Zref    = Z_final(:, :, :, end:-1:1);   % Zref is the offset-mirror of Zlab (= Z_final)
MTRasym = Zref - Z_final;
[MTRasym, b1_slope] = detrend_b1(MTRasym, B1map, Segment);

% Two fluid-suppression metrics, produced in the SAME run so they can be compared
% on byte-identical data (re-running the pipeline is not bit-reproducible, because
% motion correction isn't - hence Prepare_APTw_Data.m). Pick one once the
% comparison settles, then delete the other.
%
%   _fs  : conventional, scale by 1/Zref^2
%   _rex : inverse-Z / MTRRex, == 0.35^2*(1./Zlab - 1./Zref), which divides out
%          spillover and semisolid-MT dilution instead of merely rescaling.
%          (MTRRex, not full AREX - true AREX multiplies by R1 = 1/T1, and no T1
%          map is acquired in this protocol. Applied here to the DETRENDED
%          asymmetry, so it keeps the B1-detrend benefit.)
MTRasym_fs  = clip_outliers(MTRasym * 0.35^2 ./ Zref.^2);
MTRasym_rex = clip_outliers(MTRasym * 0.35^2 ./ (Zref .* Z_final));

% ---- 9. Save to disk as two clearly-named, purpose-separated files:
%
%   <subjectID>_APTw_results.mat        SMALL. The APTw map you actually
%                                        want (fluid-suppressed, at the
%                                        amide offset ~3.5 ppm) plus the
%                                        B0/B1 maps and QC info. This is
%                                        the file Evaluate_APTw_Results.m
%                                        reads, and the one you open to
%                                        look at results.
%   <subjectID>_APTw_full_Zspectra.mat  LARGE. Every offset of the
%                                        Z-spectrum at every processing
%                                        stage. Only needed for deeper
%                                        QA or re-processing.
%
w_amide = find_nearest(P.SEQ.w, 3.5); % index of the offset closest to the amide/APT frequency

info = struct( ...
    'subjectID',    subjectID, ...
    'subjectFolder', subjFolder, ...
    'processedOn',  datestr(now), ...
    'aptw_offset_ppm', P.SEQ.w(w_amide), ...
    'acquisitionParams', P);

% Both fluid-suppression metrics at the amide offset, from the same voxel data:
%   APTw     = conventional (1/Zref^2)
%   APTw_rex = inverse-Z / MTRRex
maps = struct( ...
    'APTw',     MTRasym_fs(:, :, :, w_amide), ...
    'APTw_rex', MTRasym_rex(:, :, :, w_amide), ...
    'B1map',    B1map, ...
    'dB0map',   dB0map);

qc = struct( ...
    'Segment',         Segment, ...
    'used_components', used_components, ...
    'b1_slope_per_offset', b1_slope);

results = struct('info', info, 'maps', maps, 'qc', qc);
resultsFile = fullfile(zevalFolder, [subjectID '_APTw_results.mat']);
save(resultsFile, '-struct', 'results', '-v7.3');

% Full offset-dimension versions of the APTw contrast:
%   APTw_full      = B1-detrended MTRasym, no fluid suppression
%   APTw_full_fs   = full-spectrum version of maps.APTw     (1/Zref^2)
%   APTw_full_rex  = full-spectrum version of maps.APTw_rex (inverse-Z)
full_spectra = struct( ...
    'M0_stack',              M0_stack, ...
    'Mz_stack',              Mz_stack, ...
    'Z_corrExt',             Z_corrExt, ...
    'Z_corrExt_denoised',    Z_corrExt_denoised, ...
    'Zref',                  Zref, ...
    'Z_final',               Z_final, ...
    'APTw_full',             MTRasym, ...
    'APTw_full_fs',          MTRasym_fs, ...
    'APTw_full_rex',         MTRasym_rex);
spectraFile = fullfile(zevalFolder, [subjectID '_APTw_full_Zspectra.mat']);
save(spectraFile, '-struct', 'full_spectra', '-v7.3');

out = results;
out.full_spectra_file = spectraFile;
end


function P = build_sequence_params(seqCfg)
% Builds the same P.SEQ/P metadata that logread() would normally parse
% out of a scanner .log file, directly from a small config struct
% (cfg.aptw_seq / cfg.wasabi_seq) instead - so no log file is needed.
P = struct();
P.SEQ.B1  = seqCfg.B1_uT;
P.SEQ.tp  = seqCfg.tp_ms / 1000;   % ms -> s (matches logread.m's T_PULSE handling)
P.N_PULSES = seqCfg.N_PULSES;
P.DC = seqCfg.DC_percent / 100;
P.SEQ.B0 = seqCfg.B0_T;
P.SEQ.FREQ = seqCfg.FREQ_MHz;
P.SEQ.sampling = 'List'; % offsets come from an explicit list, not a formula

P.SEQ.offsetlist = seqCfg.offsetlist_ppm(:)';

% Same fixed rule logread.m uses: any offset with |ppm| >= 299 is an
% unsaturated (M0) reference image, everything else is a saturated
% Z-spectrum point.
cutoff_offset = 299;
P.SEQ.index_M0     = find(abs(P.SEQ.offsetlist) >= cutoff_offset);
P.SEQ.index_no_M0  = find(abs(P.SEQ.offsetlist) <  cutoff_offset);
P.SEQ.w            = P.SEQ.offsetlist(P.SEQ.index_no_M0);
P.SEQ.w            = P.SEQ.w(:); % must be a column vector - fit() in lib/evaluation/MINFIND_SPLINE_3D.m
                                  % otherwise reads a row vector as multiple predictor columns and errors
                                  % ("X must be a matrix with one or two columns"). Same fixup calcOffset.m
                                  % used to do for the original log-file-based loading path.
P.SEQ.value_nextM0 = P.SEQ.offsetlist(P.SEQ.index_M0);

P.EVAL.w_fit    = min(P.SEQ.w):0.01:max(P.SEQ.w);
P.EVAL.w_interp = P.SEQ.w;
end


function [M0_stack, Mz_stack, P] = load_niistack_with_config(niiFile, seqCfg)
% Equivalent of LOAD('niilog', niiFile), but the sequence parameters
% come from seqCfg (cfg.aptw_seq or cfg.wasabi_seq) instead of being
% parsed from a scanner log file next to the nii. Mirrors LOAD.m /
% load_NII_and_LOG.m step for step so results are identical to the
% log-file path for the same underlying acquisition parameters.
Stack = readnifti(niiFile);
P = build_sequence_params(seqCfg);
[pathPart, namePart, extPart] = fileparts(niiFile);
P.EVAL.filename = [namePart extPart];
P.EVAL.pathname = pathPart;

if size(Stack, 4) ~= numel(P.SEQ.offsetlist)
    error(['%s has %d volumes but its cfg.*_seq.offsetlist_ppm lists %d offsets. ' ...
           'Update the sequence config to match this protocol.'], ...
          niiFile, size(Stack, 4), numel(P.SEQ.offsetlist));
end

M0_stack = double(Stack(:, :, :, P.SEQ.index_M0));
Mz_stack = double(Stack(:, :, :, P.SEQ.index_no_M0));

[P.SEQ.w, IX] = sort(P.SEQ.w);
Mz_stack = Mz_stack(:, :, :, IX);
P.EVAL.w_fit    = min(P.SEQ.w):0.01:max(P.SEQ.w);
P.EVAL.w_interp = P.SEQ.w;

if size(M0_stack, 4) > 1 % interleaved M0 scans -> interpolate a time-varying M0
    [M0_stack, P] = fitM0(M0_stack, P);
end

P.SEQ.stack_dim = size(Mz_stack);
P.EVAL.upperlim_slices = P.SEQ.stack_dim(3);
P.EVAL.lowerlim_slices = 1;
end


function [B1map, dB0map] = ensure_wasabi_fit(niiFolder, wasabiFile, zevalFolder, subjectID, Segment, cfg)
% Fits the WASABI scan (Schuenke et al., MRM 2017) at every voxel to get
% the local B1 (fraction of nominal transmit power actually delivered)
% and B0 (field offset, ppm) maps used to correct the APTw data. Cached
% in Zeval/<subjectID>_WASABI_fit.mat and reused unless cfg.force_wasabi is true.
wasabiMat = fullfile(zevalFolder, [subjectID '_WASABI_fit.mat']);
if isfile(wasabiMat) && ~cfg.force_wasabi
    fprintf('Reusing existing WASABI fit: %s\n', wasabiMat);
    wasabiData = load(wasabiMat);
    B1map  = wasabiData.B1map;
    dB0map = wasabiData.dB0_stack_ext;
    return
end

[M0_stack_wasabi, Mz_stack_wasabi, P_wasabi] = load_niistack_with_config(wasabiFile, cfg.wasabi_seq);
Z_wasabi = NORM_ZSTACK(Mz_stack_wasabi, M0_stack_wasabi, P_wasabi, Segment);

P_wasabi.SEQ.tp            = P_wasabi.SEQ.tp * 1e6;
P_wasabi.EVAL.abs          = 1;
P_wasabi.EVAL.neural_lookup = 0;
P_wasabi.FIT.options       = [1E-04, 1E-15, 1E-10, 1E-4, 1E-06];
P_wasabi.FIT.nIter         = 100;
P_wasabi.FIT.modelnum      = 021031; % WASABI2, absolute-value variant
P_wasabi.FIT.extopt        = 1;

fprintf('Fitting WASABI for B0/B1 maps...\n');
popt = FIT_3D(Z_wasabi, P_wasabi, Segment);
B1map  = popt(:, :, :, 1) / P_wasabi.SEQ.B1;
dB0map = popt(:, :, :, 2);

wasabiData = struct('M0_stack_wasabi', M0_stack_wasabi, 'Mz_stack_wasabi', Mz_stack_wasabi, ...
    'P_wasabi', P_wasabi, 'Z_wasabi', Z_wasabi, 'popt', popt, 'B1map', B1map, 'dB0_stack_ext', dB0map);
save(wasabiMat, '-struct', 'wasabiData');
end


function x = clip_outliers(x)
% Removes non-physical values from fluid-suppressed MTRasym maps
% (division by a near-zero Zref can blow up at a handful of voxels).
x(x < -100 | x > 100) = 0;
end


function [Y, slopes] = detrend_b1(Y, relB1, mask)
% Remove the residual LINEAR dependence of each offset map on relative B1.
% For each offset k it robustly fits  APTw = a + b*(relB1-1)  over brain tissue
% and subtracts b*(relB1-1), so the tissue mean is preserved but the B1-correlated
% trend (APTw high where B1 high) is removed. Physical rationale: true APTw should
% not depend on B1, so any linear APTw-vs-B1 dependence is a residual artifact.
d      = relB1 - 1;
mBrain = mask > 0 & isfinite(relB1);
nOff   = size(Y, 4);
slopes = zeros(nOff, 1);
for k = 1:nOff
    yk = Y(:, :, :, k);
    mm = mBrain & isfinite(yk);
    if nnz(mm) < 20, continue; end
    b = robust_slope(d(mm), yk(mm));       % dAPTw/d(relB1), robust to lesions/outliers
    yk(mm) = yk(mm) - b*d(mm);             % subtract the B1 trend inside the brain
    Y(:, :, :, k) = yk;
    slopes(k)  = b;
end
end


function b = robust_slope(x, y)
% OLS slope of y~x with one round of MAD-based outlier rejection (no toolbox).
x = x(:); y = y(:);
g = isfinite(x) & isfinite(y); x = x(g); y = y(g);
if numel(x) < 20, b = 0; return; end
b = fitslope(x, y);
r = y - (b*x + (mean(y) - b*mean(x)));     % residuals about the fit
s = 1.4826 * median(abs(r - median(r)));   % robust sigma
if s > 0
    keep = abs(r - median(r)) <= 3*s;      % drop trend outliers (e.g. lesions)
    if nnz(keep) >= 20, b = fitslope(x(keep), y(keep)); end
end
end


function b = fitslope(x, y)
% least-squares slope through the centroid
x = x - mean(x); y = y - mean(y);
den = sum(x.^2);
if den <= 0, b = 0; else, b = sum(x.*y)/den; end
end
