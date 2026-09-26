function out = run_APTw_subject(subjFolder, cfg)
% RUN_APTW_SUBJECT  Runs the APTw evaluation for one subject folder.
%
% Returns the same struct that gets saved to Zeval/<subjectID>_APTw_results.mat.
% Expects Prepare_APTw_Data.m / prepare_one_subject.m to have already produced
% the motion-corrected "_REG_" NIfTI. This function never converts DICOM or
% runs MOCO itself.
%
% Recognized cfg fields (see aptw_default_cfg.m for defaults):
%   singleB1_id, wasabi_id, aptw_seq, wasabi_seq   - sequence identification
%   force_wasabi, force_segmentation               - cache-bypass toggles
%   mask_threshold, use_c6                         - brain-mask definition
%   pca_components                                 - which PCs pcca_3D keeps, e.g. 1:15
%   spatial_smooth_sigma                           - optional pre-B1-correction blur, 0 = off
%   emit_stage_markers                             - if true, prints "__STAGE__:<NAME>_START/DONE"
%                                                      sentinel lines around segmentation/WASABI/
%                                                      processing, for a caller (the GUI) to parse
%                                                      progress out of. Off by default.
%
% This function does NOT show figures or compare against a scanner/Olea
% map - see evaluate_subject_own_maps.m / Evaluate_APTw_Results.m for that.

if ~isfield(cfg, 'emit_stage_markers'), cfg.emit_stage_markers = false; end
if isfield(cfg, 'use_parallel')
    if ~isfield(cfg, 'max_workers'), cfg.max_workers = 0; end
    aptw_parallel_enabled(cfg.use_parallel, cfg.max_workers);
end

[~, subjectID] = fileparts(subjFolder); % used to name every file this run produces
niiFolder   = fullfile(subjFolder, 'nii');
zevalFolder = fullfile(subjFolder, 'Zeval');
if ~isfolder(zevalFolder), mkdir(zevalFolder); end

% ---- 1. Locate the prepared inputs.
wasabiFile = find_series_file(niiFolder, cfg.wasabi_id, numel(cfg.wasabi_seq.offsetlist_ppm));
reg = dir(fullfile(niiFolder, ['*' cfg.singleB1_id '*_REG_*.nii']));
if isempty(reg)
    error(['No motion-corrected ("_REG_") NIfTI found in %s.\n' ...
           'Run Prepare_APTw_Data.m (or prepare_one_subject) on this subject first.'], niiFolder);
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

% use_c6=true (default): mask = everything that ISN'T classified as pure background
% air (c6), i.e. GM+WM+CSF+bone+soft-tissue - not just GM+WM+CSF>threshold. Every
% step that consumes Segment below (WASABI B0/B1 fit, per-voxel spline fit,
% normalization, denoising, B1 correction, detrend) processes real voxels over this
% wider footprint as a result - matching Olea's own SC_ST_AUC(...)(Masked) coverage.
if cfg.emit_stage_markers, fprintf('__STAGE__:SEGMENT_START\n'); end
[Segment, c_all] = ensure_brain_segmentation(regFile, zevalFolder, subjectID, cfg);
if cfg.emit_stage_markers, fprintf('__STAGE__:SEGMENT_DONE\n'); end
if isempty(Segment(~isnan(Segment)))
    warning('Brain segmentation failed for %s - using the whole field of view instead.', subjFolder);
    Segment = ones(size(Segment));
end
% Narrow GM+WM+CSF>threshold mask (the ORIGINAL, pre-widening definition), kept
% alongside the wide Segment above for one reason: pcca_3D's PCA fit is GLOBAL, so
% training it on Segment's wider, noisier footprint shifts the basis for every
% voxel, brain included. BrainOnlyMask is passed to pcca_3D as its training set
% below so the basis stays exactly as robust as the original brain-only pipeline,
% while Segment still controls what actually gets reconstructed/output.
BrainOnlyMask = (c_all{1} + c_all{2} + c_all{3}) > cfg.mask_threshold;
for ii = 1:size(BrainOnlyMask, 3)
    BrainOnlyMask(:, :, ii) = imfill(squeeze(BrainOnlyMask(:, :, ii)), 'holes'); % matches CreateBinaryBrainmaskWithSPM's own post-processing
end
BrainOnlyMask = double(BrainOnlyMask);
BrainOnlyMask(BrainOnlyMask == 0) = nan;
% Some subjects have one or more genuinely empty edge slices after motion correction
% (M0_stack literally all-zero there - no acquired signal at all, not just noisy).
% This varies per subject (registration-dependent), so it's not a fixed "exclude N
% edge slices" rule - exclude by the actual zero-signal voxels instead, wherever they
% land, rather than guessing which slice index is bad.
noSignal = M0_stack == 0;
if any(noSignal(:))
    fprintf('%d of %d voxels have zero raw M0 signal (no real acquisition coverage) - excluding from Segment.\n', ...
        nnz(noSignal), numel(noSignal));
    Segment(noSignal) = nan;
    BrainOnlyMask(noSignal) = nan;
end

% ---- 4. WASABI fit for B0 (field offset) and B1 (transmit efficiency)
%         maps (reused from Zeval/<subjectID>_WASABI_fit.mat if already computed).
if cfg.emit_stage_markers, fprintf('__STAGE__:WASABI_START\n'); end
[B1map, dB0map] = ensure_wasabi_fit(niiFolder, wasabiFile, zevalFolder, subjectID, Segment, cfg);
if cfg.emit_stage_markers, fprintf('__STAGE__:WASABI_DONE\n'); end

if ~isequal(size(dB0map), size(M0_stack))
    error(['WASABI (%s) and APTw (%s) volumes have different matrix sizes. They must share ' ...
           'the same FOV/resolution for B0/B1 correction to be voxel-aligned - reslice one ' ...
           'to match the other before running this pipeline.'], mat2str(size(dB0map)), mat2str(size(M0_stack)));
end

if cfg.emit_stage_markers, fprintf('__STAGE__:B0CORR_START\n'); end
% ---- 5. Correct each voxel's Z-spectrum for its local B0 offset
%         (using the WASABI dB0 map), then normalize to the M0 signal.
%
%      Two-step form, matching the original FAU_APTw_1B1_Pipeline_IMPI04_3T:
%        (a) MINFIND_SPLINE_3D fits a smoothing spline per voxel and evaluates it
%            on a DENSE offset grid (P.EVAL.w_fit, 0.01 ppm steps) -> yfit.
%        (b) B0_CORRECTION shifts by dB0 and interpolates that dense grid back to
%            the acquired offsets (P.EVAL.w_interp), using P.EVAL.B0_int_meth.
[~, ~, yfit] = MINFIND_SPLINE_3D(Mz_stack, Segment, P);
Pfit               = change_w_fit(P);
Pfit.SEQ.w         = Pfit.EVAL.w_fit;   % the spline was evaluated on this dense grid
Pfit.EVAL.w_interp = P.SEQ.w;           % ...and is interpolated back to the acquired offsets
Mz_CORR            = B0_CORRECTION(yfit, dB0map, Pfit, Segment);

[Z_corrExt, ~, normType] = NORM_ZSTACK(Mz_CORR, M0_stack, P, Segment);
P.EVAL.normalizationType = normType;
P.EVAL.normalization     = 'M0_stack';
if cfg.emit_stage_markers, fprintf('__STAGE__:B0CORR_DONE\n__STAGE__:DENOISE_START\n'); end

% ---- 6. Denoise via local PCA (first N components kept). BrainOnlyMask (not the
%         wider Segment) trains the PCA basis - see pcca_3D.m's header comment and
%         the note above Segment/BrainOnlyMask's definitions for why.
[Z_corrExt_denoised, used_components] = pcca_3D(Z_corrExt, P, cfg.pca_components, 0, Segment, [], BrainOnlyMask);

% ---- 6b. Optional spatial smoothing (OFF by default - see cfg.spatial_smooth_sigma).
Z_corrExt_denoised = apply_spatial_smoothing(Z_corrExt_denoised, cfg.spatial_smooth_sigma);
if cfg.emit_stage_markers, fprintf('__STAGE__:DENOISE_DONE\n__STAGE__:B1MAPS_START\n'); end

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
[MTRasym, b1_slope] = detrend_b1(MTRasym, B1map, Segment, BrainOnlyMask);

% Two fluid-suppression metrics, produced in the SAME run so they can be compared
% on byte-identical data:
%   _fs  : conventional, scale by 1/Zref^2
%   _rex : inverse-Z / MTRRex, == 0.35^2*(1./Zlab - 1./Zref), which divides out
%          spillover and semisolid-MT dilution instead of merely rescaling.
MTRasym_fs  = clip_outliers(MTRasym * 0.35^2 ./ Zref.^2);
MTRasym_rex = clip_outliers(MTRasym * 0.35^2 ./ (Zref .* Z_final));

% ---- 8b. Same two metrics again, but WITHOUT the B1 correction (step 7) or the
%          B1-detrend above - computed directly from the B0-corrected, denoised
%          Z-spectrum as acquired (Z_corrExt_denoised). Useful for a fair
%          comparison against a scanner/Olea map whose SeriesDescription shows
%          only "(wB0-corr)" (no B1 term).
Zref_noB1        = Z_corrExt_denoised(:, :, :, end:-1:1);
MTRasym_noB1     = Zref_noB1 - Z_corrExt_denoised;
MTRasym_fs_noB1  = clip_outliers(MTRasym_noB1 * 0.35^2 ./ Zref_noB1.^2);
MTRasym_rex_noB1 = clip_outliers(MTRasym_noB1 * 0.35^2 ./ (Zref_noB1 .* Z_corrExt_denoised));

% ---- 9. Save to disk as two clearly-named, purpose-separated files:
%
%   <subjectID>_APTw_results.mat        SMALL. The APTw map you actually
%                                        want (fluid-suppressed, at the
%                                        amide offset ~3.5 ppm) plus the
%                                        B0/B1 maps and QC info.
%   <subjectID>_APTw_full_Zspectra.mat  LARGE. Every offset of the
%                                        Z-spectrum at every processing
%                                        stage. Only needed for deeper
%                                        QA or re-processing.
w_amide = find_nearest(P.SEQ.w, 3.5); % index of the offset closest to the amide/APT frequency

info = struct( ...
    'subjectID',    subjectID, ...
    'subjectFolder', subjFolder, ...
    'processedOn',  datestr(now), ...
    'aptw_offset_ppm', P.SEQ.w(w_amide), ...
    'acquisitionParams', P);

% Both fluid-suppression metrics at the amide offset, from the same voxel data,
% each in a normal (B1-corrected) and a _noB1 (see step 8b) flavour:
%   APTw          = conventional (1/Zref^2), B1-corrected
%   APTw_rex      = inverse-Z / MTRRex, B1-corrected
%   APTw_noB1     = conventional (1/Zref^2), NOT B1-corrected
%   APTw_rex_noB1 = inverse-Z / MTRRex, NOT B1-corrected
maps = struct( ...
    'APTw',          MTRasym_fs(:, :, :, w_amide), ...
    'APTw_rex',      MTRasym_rex(:, :, :, w_amide), ...
    'APTw_noB1',     MTRasym_fs_noB1(:, :, :, w_amide), ...
    'APTw_rex_noB1', MTRasym_rex_noB1(:, :, :, w_amide), ...
    'B1map',    B1map, ...
    'dB0map',   dB0map);

qc = struct( ...
    'Segment',         Segment, ...
    'used_components', used_components, ...
    'b1_slope_per_offset', b1_slope, ...
    'spatial_smooth_sigma', cfg.spatial_smooth_sigma);

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
if cfg.emit_stage_markers, fprintf('__STAGE__:B1MAPS_DONE\n'); end

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
% parsed from a scanner log file next to the nii.
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


function Z = apply_spatial_smoothing(Z, sigma)
% Per-slice, per-offset 2D Gaussian blur. No-op when sigma<=0.
if sigma <= 0, return; end
for kk = 1:size(Z, 3)
    for ll = 1:size(Z, 4)
        Z(:, :, kk, ll) = imgaussfilt(Z(:, :, kk, ll), sigma);
    end
end
end


function x = clip_outliers(x)
% Removes non-physical values from fluid-suppressed MTRasym maps
% (division by a near-zero Zref can blow up at a handful of voxels).
x(x < -100 | x > 100) = 0;
end


function [Y, slopes] = detrend_b1(Y, relB1, mask, trainMask)
% Remove the residual LINEAR dependence of each offset map on relative B1.
% For each offset k it robustly fits  APTw = a + b*(relB1-1)  over brain tissue
% and subtracts b*(relB1-1), so the tissue mean is preserved but the B1-correlated
% trend (APTw high where B1 high) is removed.
%
% trainMask (optional, 4th arg): voxels that FIT each offset's slope b. mask still
% controls which voxels get the correction APPLIED - defaults to mask.
if nargin < 4, trainMask = mask; end
d      = relB1 - 1;
mTrain = trainMask > 0 & isfinite(relB1);
mApply = mask > 0 & isfinite(relB1);
nOff   = size(Y, 4);
slopes = zeros(nOff, 1);
for k = 1:nOff
    yk = Y(:, :, :, k);
    mmTrain = mTrain & isfinite(yk);
    mmApply = mApply & isfinite(yk);
    if nnz(mmTrain) < 20, continue; end
    b = robust_slope(d(mmTrain), yk(mmTrain));   % dAPTw/d(relB1), robust to lesions/outliers, BRAIN-ONLY fit
    yk(mmApply) = yk(mmApply) - b*d(mmApply);    % apply the correction to every voxel mask asks for
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
