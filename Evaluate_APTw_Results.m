%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%   Evaluate_APTw_Results.m
%
%   Standalone QC + Olea/scanner-map comparison for Run_APTw_Pipeline.m
%   output. Does NOT run any part of the pipeline itself - it only reads
%   the .mat file Run_APTw_Pipeline.m already wrote to each subject's
%   Zeval/ folder, and (optionally) a scanner/Olea-computed map sitting
%   next to the raw data.
%
%   For each subject, and for each of APTw / B0 / relative-B1 where a
%   matching scanner map is found (see cfg.olea_id / olea_b0_id /
%   olea_b1_id below), this:
%     - puts both maps on the same grid/orientation and units
%     - reports Pearson/Spearman correlation, bias, 95% limits of
%       agreement, and MAE over the brain/overlap voxels
%     - draws four figures: maps side-by-side, a difference map, a
%       scatter + Bland-Altman plot, and distributions + per-slice r
%
%   Which APTw map is graded is set by cfg.aptw_metric ('fs' or 'rex').
%
%   No toolboxes required beyond what Run_APTw_Pipeline.m already needs -
%   dicominfo/dicomread/corrcoef/plotting are all base MATLAB.
%
%   HOW TO USE
%     1) Run Run_APTw_Pipeline.m first (this script only reads its output).
%     2) Set DATA_ROOT below (or leave '' to pick interactively).
%     3) Run this script. For each subject, look at the "orientation
%        check" figure first - if the two panels aren't anatomically
%        aligned, adjust cfg.olea_orient and re-run.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% ========================= SETUP (do not need to edit) =========================
projectRoot = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(projectRoot, 'lib')));

%% ========================= USER SETTINGS =========================
% Same convention as Run_APTw_Pipeline.m: point at EITHER a single
% subject folder OR a folder containing one sub-folder per subject - both
% are auto-detected below. Leave empty to pick interactively.
DATA_ROOT = '';

cfg = struct();
cfg.olea_id       = 'SC_ST';   % substring identifying the Olea-computed APTw series folder
cfg.olea_b0_id    = 'dB0';     % substring identifying the Olea/scanner-computed B0 map series folder
cfg.olea_b1_id    = 'rB1';     % substring identifying the Olea/scanner-computed relative-B1 map series folder
cfg.aptw_metric   = 'rex';     % which APTw map to grade: 'fs' (conventional 1/Zref^2)
                               % or 'rex' (inverse-Z / MTRRex). Both are written by
                               % Run_APTw_Pipeline.m; flip this instead of editing code.
cfg.olea_bgThresh = -10;       % Olea APTw values (%) below this are background -> excluded (B0/rB1 use segmentation only)
cfg.olea_outlierK = 3;         % reject voxels with |diff-median(diff)| > K*(1.4826*MAD) from agreement stats

% Our B0 map is fit in ppm and our B1 map is a dimensionless fraction of nominal
% (fitted uT / nominal uT, ~1 = full power). Olea/scanner dB0 and rB1 series are
% commonly exported in different units (dB0 often in Hz, rB1 often as a percent
% of nominal), which is why they can look wildly off-scale even when the maps
% agree. evaluate_one_map() prints the actual median(mine)/median(scanner) ratio
% for each - use that number to set these (e.g. ~123.23 if B0 needs ppm->Hz at
% 3T, ~100 if B1 needs fraction->percent). Leave at 1 if your Olea export is
% already in the same units as ours.
cfg.olea_b0_scale = 1;
cfg.olea_b1_scale = 1;
cfg.olea_orient = struct( ...  % shared orientation for all three comparisons (APTw/B0/rB1) - tune with the
    'transpose', false, 'flipud', true, 'fliplr', false, 'rot90', 0, 'reverse_slices', false); % orientation-check figure
cfg.sliceKeep   = 3:10;        % slices to include in stats/figures; [] = all
cfg.saveOutputs = true;        % save stats .mat + figure PNGs into each subject's Zeval/ folder

%% ========================= SELECT SUBJECTS =========================
if isempty(DATA_ROOT)
    DATA_ROOT = uigetdir(pwd, 'Select a subject folder, or a folder containing one sub-folder per subject');
    if isequal(DATA_ROOT, 0)
        error('No folder selected.');
    end
end

if has_aptw_results(DATA_ROOT)
    Subject_Folders = {DATA_ROOT};
else
    d = dir(DATA_ROOT);
    d = d([d.isdir] & ~ismember({d.name}, {'.', '..'}));
    candidates = fullfile(DATA_ROOT, {d.name});
    candidates = candidates(cellfun(@isfolder, candidates));
    isSubject  = cellfun(@has_aptw_results, candidates);
    if any(~isSubject)
        fprintf(['Skipping %d sub-folder(s) of %s with no Zeval/*_APTw_results.mat ' ...
            '(run Run_APTw_Pipeline.m on them first):\n'], nnz(~isSubject), DATA_ROOT);
        fprintf('  %s\n', candidates{~isSubject});
    end
    Subject_Folders = candidates(isSubject);
end
fprintf('Found %d subject folder(s) with results to evaluate.\n', numel(Subject_Folders));

%% ========================= RUN EVALUATION =========================
for s = 1:numel(Subject_Folders)
    fprintf('\n===== Subject %d/%d: %s =====\n', s, numel(Subject_Folders), Subject_Folders{s});
    try
        evaluate_subject(Subject_Folders{s}, cfg);
    catch ME
        warning('FAILED for %s:\n  %s', Subject_Folders{s}, ME.message);
    end
end


%% ===================================================================
%  ===================== local functions below =======================
%% ===================================================================

function tf = has_aptw_results(folder)
[~, subjectID] = fileparts(folder);
tf = isfile(fullfile(folder, 'Zeval', [subjectID '_APTw_results.mat']));
end


function evaluate_subject(subjFolder, cfg)
[~, subjectID] = fileparts(subjFolder);
zevalFolder = fullfile(subjFolder, 'Zeval');
resultsFile = fullfile(zevalFolder, [subjectID '_APTw_results.mat']);
S = load(resultsFile);

switch lower(cfg.aptw_metric)
    case 'fs',  aptwMap = S.maps.APTw;
    case 'rex', aptwMap = S.maps.APTw_rex;
    otherwise,  error('cfg.aptw_metric must be ''fs'' or ''rex'', got ''%s''.', cfg.aptw_metric);
end

% One spec per comparison. scale=100 for APTw because the pipeline stores it as a
% plain ratio (0.02, not "2%") while Olea stores %; B0 (ppm) and B1 (relative) are
% already in matching units. bgThresh=-Inf means "use the brain mask alone".
comparisons = { ...
    struct('map', aptwMap,      'seriesID', cfg.olea_id,    'scale', 100, ...
           'bgThresh', cfg.olea_bgThresh, 'label', 'APTw (%)',      'tag', 'aptw', 'diverging', true), ...
    struct('map', S.maps.dB0map, 'seriesID', cfg.olea_b0_id, 'scale', cfg.olea_b0_scale, ...
           'bgThresh', -Inf,               'label', 'B0 (ppm)',      'tag', 'b0', 'diverging', true), ...
    struct('map', S.maps.B1map,  'seriesID', cfg.olea_b1_id, 'scale', cfg.olea_b1_scale, ...
           'bgThresh', -Inf,               'label', 'B1 (relative)', 'tag', 'b1', 'diverging', false)};

% Our own APTw/B0/B1 maps, in one figure. Needs nothing but the
% pipeline's own output, so it appears whether or not a scanner/Olea
% series exists to compare against.
plot_own_maps(subjectID, zevalFolder, comparisons, S.qc.Segment, cfg);

% Then the scanner/Olea comparisons, each of which skips itself if its
% counterpart series isn't there.
for k = 1:numel(comparisons)
    evaluate_one_map(subjFolder, subjectID, zevalFolder, comparisons{k}, S.qc.Segment, cfg);
end
end


function plot_own_maps(subjectID, zevalFolder, comparisons, Segment, cfg)
% One figure, one montage panel per map (APTw / B0 / B1), masked to the
% brain and windowed to each map's own robust 2-98 percentile range.
figTag = 'APTwOwnMaps';
close(findobj('Type', 'figure', 'Tag', figTag));
fh = figure('Name', sprintf('%s: pipeline maps', subjectID), 'Color', 'w', ...
    'Position', [70 90 1500 480], 'Tag', figTag);

seg0 = permute(Segment, [2 1 3]) > 0;
drew = false;
for k = 1:numel(comparisons)
    cmp  = comparisons{k};
    mine = permute(cmp.map, [2 1 3]) * cmp.scale;

    nz  = min(size(mine, 3), size(seg0, 3));
    mine = mine(:, :, 1:nz); seg = seg0(:, :, 1:nz);

    sliceMask = false(1, nz);
    if isempty(cfg.sliceKeep), sliceMask(:) = true; else, sliceMask(intersect(cfg.sliceKeep, 1:nz)) = true; end
    zr = find(sliceMask);

    vis = mine;
    vis(~seg | ~isfinite(mine)) = NaN;

    subplot(1, numel(comparisons), k)
    if isempty(zr)
        axis off, title(sprintf('%s - no slice selected', cmp.label))
        continue
    end
    sel  = vis(:, :, zr);
    vals = sel(isfinite(sel));
    if isempty(vals)
        axis off, title(sprintf('%s - no in-mask voxels', cmp.label))
        continue
    end

    w = pctwin(vals);
    m = tile(vis, zr);
    h = imagesc(m, w); set(h, 'AlphaData', ~isnan(m)); axis image off
    title(sprintf('%s   [%.3g %.3g]', cmp.label, w(1), w(2)))
    colorbar
    if cmp.diverging
        lim = max(abs(w));
        if lim > 0, caxis([-lim lim]); end
        colormap(gca, bluewhitered)
    else
        colormap(gca, parula)
    end
    drew = true;

    fprintf('%-14s own map: n=%d voxels, mean %+.4g, median %+.4g, 2-98%% [%.4g %.4g]\n', ...
        cmp.label, numel(vals), mean(vals), median(vals), w(1), w(2));
end

if ~drew
    close(fh);
    fprintf('None of the pipeline maps had displayable voxels - no map figure drawn.\n');
    return
end

if cfg.saveOutputs
    saveas(fh, fullfile(zevalFolder, sprintf('%s_pipeline_maps.png', subjectID)));
end
end


function evaluate_one_map(subjFolder, subjectID, zevalFolder, cmp, Segment, cfg)
% Compares one of our maps against its scanner/Olea counterpart.
%
% cmp is a spec struct describing this comparison:
%   .map       our map (3D, in its native units)
%   .seriesID  substring identifying the scanner DICOM series folder
%   .scale     multiplier putting .map into the scanner map's units
%   .bgThresh  scanner values at or below this are background (-Inf = mask only)
%   .label     axis/printout label, e.g. 'APTw (%)'
%   .tag       short slug used in saved filenames
%
% Finds the scanner series next to the raw data, decodes it via its DICOM
% RescaleSlope/Intercept, puts it on the same grid/orientation as
% cmp.map*cmp.scale, then reports correlation stats and draws four figures:
% maps montage, difference map, scatter + Bland-Altman, distributions +
% per-slice r. Silently does nothing if no matching scanner series is found.

[mineMap, seriesID, scaleMine, bgThresh, label, tag] = ...
    deal(cmp.map, cmp.seriesID, cmp.scale, cmp.bgThresh, cmp.label, cmp.tag);

figTag = ['APTwEval_' tag];
close(findobj('Type', 'figure', 'Tag', figTag)); % clear this map's own figures from a previous run

files = find_scanner_series_files(subjFolder, seriesID);
if isempty(files)
    fprintf('No scanner map found matching "%s" - skipping the %s comparison.\n', seriesID, label);
    return
end

[slope, inter, haveScale] = read_dicom_rescale(files);
if ~haveScale
    warning(['No RescaleSlope/RescaleIntercept found on any file for the scanner map matching "%s" - ' ...
        'using raw pixel values (slope=1, intercept=0) instead, which is likely wrong for an ' ...
        'Olea-computed parametric map.'], seriesID);
end

raw = read_dicom_stack(files);
if isempty(raw)
    fprintf('Could not read any image from the scanner map matching "%s" - skipping the %s comparison.\n', seriesID, label);
    return
end
scanner_map = raw * slope + inter;
scanner_map = apply_orient(scanner_map, cfg.olea_orient);

mine = permute(mineMap, [2 1 3]) * scaleMine;
seg  = permute(Segment, [2 1 3]) > 0;

nz = min(size(mine, 3), size(scanner_map, 3));
mine = mine(:, :, 1:nz); seg = seg(:, :, 1:nz); scanner_map = scanner_map(:, :, 1:nz);
if ~isequal(size(mine), size(scanner_map))
    warning(['Found a scanner map (series matching "%s") but its size doesn''t match ours after ' ...
             'orientation (mine %s vs scanner %s) - skipping the %s comparison. Check cfg.olea_orient.'], ...
             seriesID, mat2str(size(mine)), mat2str(size(scanner_map)), label);
    return
end

%% ---- masks ----
sliceMask = false(1, nz);
if isempty(cfg.sliceKeep), sliceMask(:) = true; else, sliceMask(intersect(cfg.sliceKeep, 1:nz)) = true; end
sliceVol = repmat(reshape(sliceMask, 1, 1, nz), size(mine,1), size(mine,2), 1);

base = seg & (scanner_map > bgThresh) & isfinite(mine) & isfinite(scanner_map) & sliceVol;

outlier = false(size(mine));
dall = mine - scanner_map;
dv = dall(base);
if ~isempty(dv)
    med  = median(dv);
    sigR = 1.4826 * median(abs(dv - med));
    if sigR > 0
        outlier = base & (abs(dall - med) > cfg.olea_outlierK * sigR);
        fprintf('Outlier rejection (%s): median d=%+.3f, robust sigma=%.3f, K=%.1f -> %d voxels dropped (%.1f%%)\n', ...
            label, med, sigR, cfg.olea_outlierK, nnz(outlier), 100*nnz(outlier)/max(1, nnz(base)));
    end
end
both = base & ~outlier;
x = mine(both); y = scanner_map(both);

if isempty(x)
    fprintf('No overlapping voxels for the %s comparison - skipping.\n', label);
    return
end

%% ---- correlations ----
r_all = pearsonr(x, y); rho_all = spearmanr(x, y);
bias  = mean(x - y); loa = 1.96 * std(x - y); mae = mean(abs(x - y));
p = polyfit(x, y, 1);

fprintf('\n===== %s agreement (scanner/Olea vs mine) =====\n', label);
fprintf('slices kept (cfg.sliceKeep): %s  (%d of %d)\n', mat2str(find(sliceMask)), nnz(sliceMask), nz);
fprintf('n voxels (overlap)      : %d\n', numel(x));
fprintf('Pearson  r               : %.3f\n', r_all);
fprintf('Spearman rho             : %.3f\n', rho_all);
fprintf('Mean bias (mine-scanner) : %+.3f  (95%% LoA +/- %.3f)\n', bias, loa);
fprintf('MAE  |mine-scanner|      : %.3f\n', mae);
medMine = median(x); medScan = median(y);
fprintf('median mine / scanner    : %.4g / %.4g  (ratio %.4g)\n', medMine, medScan, medMine / medScan);
if ismember(tag, {'b0', 'b1'}) && (abs(medMine / medScan) > 5 || abs(medMine / medScan) < 0.2)
    fprintf(['  -> looks like a unit/scale mismatch, not a real disagreement. Try setting cfg.olea_%s_scale ' ...
        'to ~%.3g (currently %.3g) and re-running.\n'], tag, scaleMine * medScan / medMine, scaleMine);
end

zr = find(sliceMask);
r_slice = nan(1, nz);
for z = zr
    m = both(:,:,z);
    if nnz(m) > 20
        a = mine(:,:,z); b = scanner_map(:,:,z);
        r_slice(z) = pearsonr(a(m), b(m));
    end
end

%% ---- maps montage (mine / scanner / difference) ----
mine_disp    = mine;        mine_disp(~both)    = NaN;
scanner_disp = scanner_map; scanner_disp(~both) = NaN;
dMap         = mine - scanner_map; dMap(~both) = NaN;

wMine = pctwin(mine(both));
wScan = pctwin(scanner_map(both));
dAbs = abs(dMap(~isnan(dMap)));
if isempty(dAbs), dlim = [-1 1]; else, dw = pctwin(dAbs); dlim = [-1 1] * max(dw(2), eps); end

% One figure, one row: mine / scanner-Olea / difference, each with its own
% colormap+colorbar (per-axes colormap - each subplot sets its own via
% colormap(gca, ...) rather than one shared figure-wide colormap).
figure('Name', sprintf('%s: maps + difference (%s)', subjectID, label), 'Color', 'w', 'Position', [60 80 1320 480], 'Tag', figTag);
subplot(1,3,1); m = tile(mine_disp, zr);    h = imagesc(m, wMine); set(h,'AlphaData',~isnan(m)); axis image off, title(sprintf('mine  [%.2g %.2g]', wMine)), colorbar, colormap(gca, parula)
subplot(1,3,2); m = tile(scanner_disp, zr); h = imagesc(m, wScan); set(h,'AlphaData',~isnan(m)); axis image off, title(sprintf('scanner/Olea  [%.2g %.2g]', wScan)), colorbar, colormap(gca, parula)
subplot(1,3,3); m = tile(dMap, zr);         h = imagesc(m, dlim);  set(h,'AlphaData',~isnan(m)); axis image off, title('mine - scanner/Olea'), colorbar, colormap(gca, bluewhitered)

%% ---- scatter + Bland-Altman ----
figure('Name', sprintf('%s: scatter & Bland-Altman (%s)', subjectID, label), 'Color', 'w', 'Position', [100 100 1000 440], 'Tag', figTag);
subplot(1,2,1)
scatter(x, y, 4, '.'); hold on, axis equal tight, grid on
xl = xlim; plot(xl, xl, 'k--'); plot(xl, polyval(p, xl), 'r-', 'LineWidth', 1.2);
xlabel('mine'), ylabel('scanner/Olea')
title(sprintf('r=%.3f  \\rho=%.3f  (slope %.2f)', r_all, rho_all, p(1)))
legend('voxels', 'identity', 'fit', 'Location', 'best')

subplot(1,2,2)
mn = (x + y) / 2; df = x - y;
scatter(mn, df, 4, '.'); hold on, grid on
yline(bias, 'r-'); yline(bias + loa, 'r--'); yline(bias - loa, 'r--');
xlabel('mean of the two'), ylabel('mine - scanner/Olea')
title(sprintf('bias %+.2f,  LoA [%.2f, %.2f]', bias, bias - loa, bias + loa))

%% ---- distributions + per-slice r ----
figure('Name', sprintf('%s: distributions & per-slice r (%s)', subjectID, label), 'Color', 'w', 'Position', [120 120 1000 420], 'Tag', figTag);
subplot(1,2,1)
histogram(x, 80, 'FaceAlpha', .5), hold on, histogram(y, 80, 'FaceAlpha', .5)
xlabel(label), ylabel('voxels'), legend('mine', 'scanner/Olea'), title('value distributions')
subplot(1,2,2)
bar(zr, r_slice(zr)); ylim([0 1]), grid on
xlabel('slice'), ylabel('Pearson r'), title('per-slice correlation')

%% ---- save ----
if cfg.saveOutputs
    stats = struct('n', numel(x), 'pearson', r_all, 'spearman', rho_all, 'bias', bias, ...
        'LoA', loa, 'MAE', mae, 'fit_slope', p(1), 'fit_intercept', p(2), 'r_per_slice', r_slice);
    save(fullfile(zevalFolder, sprintf('%s_%s_agreement_stats.mat', subjectID, tag)), '-struct', 'stats');

    figs = findobj('Type', 'figure', 'Tag', figTag);
    figs = flipud(figs(:)); % oldest (first-created) first
    tagsUsed = {'maps_diff', 'scatter_BA', 'distributions'};
    for i = 1:numel(figs)
        if i <= numel(tagsUsed)
            fname = sprintf('%s_%s_%s.png', subjectID, tag, tagsUsed{i});
        else
            fname = sprintf('%s_%s_fig%d.png', subjectID, tag, i);
        end
        saveas(figs(i), fullfile(zevalFolder, fname));
    end
    fprintf('Saved %s stats + figures to %s\n', label, zevalFolder);
end
end


function files = find_scanner_series_files(subjFolder, seriesID)
% Finds the instance files of the scanner/Olea-computed series whose
% folder name contains seriesID (e.g. 'SC_ST'/'dB0'/'rB1'), however
% deeply nested - mirrors the DICOM/EXP0000/... layout
% Run_APTw_Pipeline.m's convert_dicom_to_nii already handles.
files = [];
seriesDirs = dir(fullfile(subjFolder, '**', ['*' seriesID '*']));
seriesDirs = seriesDirs([seriesDirs.isdir]);
for ii = 1:numel(seriesDirs)
    candidate = fullfile(seriesDirs(ii).folder, seriesDirs(ii).name);
    candidateFiles = dir(fullfile(candidate, '**', '*'));
    candidateFiles = candidateFiles(~[candidateFiles.isdir]);
    if ~isempty(candidateFiles)
        files = candidateFiles;
        return
    end
end
end


function [slope, inter, haveScale] = read_dicom_rescale(files)
% Searches files (in order) for the first one that actually carries both
% RescaleSlope and RescaleIntercept, skipping any that error out (e.g. a
% DICOMDIR/report file bundled into the same folder) or simply lack the
% tags (e.g. a non-image DICOM object) - settling for the first merely
% *readable* file regardless of whether it has these tags would silently
% produce wrong-scaled Olea maps.
slope = 1; inter = 0; haveScale = false;
for k = 1:numel(files)
    try
        info1 = dicominfo(fullfile(files(k).folder, files(k).name));
    catch
        continue
    end
    if isfield(info1, 'RescaleSlope') && isfield(info1, 'RescaleIntercept')
        slope = double(info1.RescaleSlope);
        inter = double(info1.RescaleIntercept);
        haveScale = true;
        return
    end
end
end


function raw = read_dicom_stack(files)
% Reads every file as a DICOM image into raw(:,:,InstanceNumber),
% skipping any file that isn't a readable DICOM image (e.g. a
% DICOMDIR/report file) or that lacks an InstanceNumber tag (falls back
% to file order in that case rather than erroring).
raw = [];
for k = 1:numel(files)
    fp = fullfile(files(k).folder, files(k).name);
    try
        dinfo = dicominfo(fp);
        px = dicomread(fp);
    catch
        continue
    end
    if isfield(dinfo, 'InstanceNumber')
        idx = dinfo.InstanceNumber;
    else
        idx = k;
    end
    raw(:, :, idx) = double(px); %#ok<AGROW>
end
end


function v = apply_orient(v, o)
if o.transpose,      v = permute(v, [2 1 3]); end
if o.flipud,          v = flip(v, 1); end
if o.fliplr,          v = flip(v, 2); end
if o.rot90 ~= 0,      v = rot90(v, o.rot90); end
if o.reverse_slices,  v = flip(v, 3); end
end


function w = pctwin(v)
% robust 2-98 percentile display window (no toolbox needed)
s = sort(v(:)); s = s(~isnan(s)); n = numel(s);
if n < 2, w = [0 1]; return; end
w = [s(max(1, round(0.02*n)))  s(min(n, round(0.98*n)))];
if w(2) <= w(1), w(2) = w(1) + eps; end
end


function r = pearsonr(x, y)
x = x(:); y = y(:); c = corrcoef(x, y); r = c(1,2);
end


function r = spearmanr(x, y)
r = pearsonr(ranks(x), ranks(y)); % ties ignored (fine for continuous data)
end


function rk = ranks(v)
[~, ord] = sort(v(:)); rk = zeros(numel(v), 1); rk(ord) = 1:numel(v);
end


function M = tile(vol, slices)
% lay selected slices out in a near-square grid -> single 2D image
n = numel(slices); cols = ceil(sqrt(max(n, 1))); rows = ceil(n / max(cols, 1));
[h, w, ~] = size(vol); M = nan(rows*h, cols*w);
for i = 1:n
    r = floor((i-1)/cols); c = mod(i-1, cols);
    M(r*h+(1:h), c*w+(1:w)) = vol(:, :, slices(i));
end
end


function cmap = bluewhitered
% simple blue-white-red diverging colormap for difference maps
n = 128; up = linspace(0, 1, n)';
cmap = [ [up up ones(n,1)]; [ones(n,1) flipud(up) flipud(up)] ];
end
