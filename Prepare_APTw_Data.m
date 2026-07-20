%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%   Prepare_APTw_Data.m
%
%   ONE-TIME data preparation for the 3T APTw (CEST) pipeline:
%       raw DICOM  ->  NIfTI  ->  motion-corrected NIfTI
%
%   Run this ONCE per subject. It produces a "_REG_" NIfTI that
%   Run_APTw_Pipeline.m then treats as a frozen input.
%
%   FOLDER LAYOUT EXPECTED PER SUBJECT
%   -----------------------------------------------------------------
%   <subject_folder>/
%       Raw DICOM. Two layouts are auto-detected:
%         dcm/<series name>/           legacy: instance files directly inside
%         <series name>/...            e.g. a PACS/Olea export, files nested
%                                       several folders deep, no extension
%       nii/                           created automatically; output lands here
%
%   Sequence parameters come from lib/pipeline/aptw_sequence_config.m,
%   shared with Run_APTw_Pipeline.m so they are defined in exactly one place.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% ========================= SETUP (do not need to edit) =========================
projectRoot = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(projectRoot, 'lib')));
binFolder   = fullfile(projectRoot, 'bin');

if isempty(which('spm'))
    error(['SPM12 was not found on the MATLAB path. Motion correction uses SPM and this ' ...
           'project does not bundle it. Install SPM12 and run addpath(''/path/to/spm12'') ' ...
           'before running this script. https://www.fil.ion.ucl.ac.uk/spm/software/spm12/']);
end

%% ========================= USER SETTINGS =========================
% Point at EITHER a single subject folder OR a folder containing one
% sub-folder per subject - both are auto-detected. Leave empty to pick
% interactively via a folder dialog.
DATA_ROOT = '';

cfg = struct();
cfg.singleB1_id = 'APTw_001';   % substring identifying the CEST Z-spectrum series
cfg.wasabi_id   = 'WASAB';      % substring identifying the WASABI series
[cfg.aptw_seq, cfg.wasabi_seq] = aptw_sequence_config();  % shared with Run_APTw_Pipeline.m

% Set true to force a step to re-run even if its output already exists.
% force_moco is deliberately separate and defaults to false - see the note
% at the top of this file about why re-running motion correction is not free.
cfg.force_dicom_conversion = false;
cfg.force_moco             = false;

%% ========================= SELECT SUBJECTS =========================
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
        fprintf('Skipping %d sub-folder(s) of %s that don''t look like subject folders:\n', ...
            nnz(~isSubject), DATA_ROOT);
        fprintf('  %s\n', candidates{~isSubject});
    end
    Subject_Folders = candidates(isSubject);
end
fprintf('Found %d subject folder(s) to prepare.\n', numel(Subject_Folders));

%% ========================= PREPARE EACH SUBJECT =========================
prepared = cell(numel(Subject_Folders), 1);
failed   = false(numel(Subject_Folders), 1);
for s = 1:numel(Subject_Folders)
    fprintf('\n===== Subject %d/%d: %s =====\n', s, numel(Subject_Folders), Subject_Folders{s});
    try
        prepared{s} = prepare_one_subject(Subject_Folders{s}, cfg, binFolder);
        fprintf('Ready for analysis: %s\n', prepared{s});
    catch ME
        failed(s) = true;
        warning('FAILED for %s:\n  %s', Subject_Folders{s}, ME.message);
    end
end

fprintf('\n===== Summary =====\n%d/%d subjects prepared successfully.\n', ...
    nnz(~failed), numel(Subject_Folders));
if any(failed)
    fprintf('Failed:\n'); fprintf('  %s\n', Subject_Folders{failed});
end
fprintf('\nNext step: run Run_APTw_Pipeline.m on the same folder.\n');


%% ===================================================================
%  ===================== local functions below =======================
%% ===================================================================

function regFile = prepare_one_subject(subjFolder, cfg, binFolder)
% DICOM -> NIfTI -> motion-corrected NIfTI for one subject.
niiFolder = fullfile(subjFolder, 'nii');

% ---- 1. Convert DICOM to NIfTI if needed. convert_dicom_to_nii decides
%         for itself by checking nii CONTENT (correct volume count), not
%         mere file existence, so an interrupted earlier conversion cannot
%         leave stale fragments that get reused forever.
convert_dicom_to_nii(subjFolder, cfg, binFolder);

aptwFile   = find_series_file(niiFolder, cfg.singleB1_id, numel(cfg.aptw_seq.offsetlist_ppm));
wasabiFile = find_series_file(niiFolder, cfg.wasabi_id,   numel(cfg.wasabi_seq.offsetlist_ppm));

% ---- 2. Motion-correct the Z-spectrum time series onto the WASABI volume.
regFile = ensure_motion_corrected(niiFolder, aptwFile, wasabiFile, cfg);
end

function convert_dicom_to_nii(subjFolder, cfg, binFolder)
% Converts every series folder found for this subject into a NIfTI file
% in <subjFolder>/nii using dcm2niix.
%
% Two raw-data layouts are supported automatically:
%   <subjFolder>/dcm/<series name>/...    legacy convention: instance
%                                          files directly inside, named *.dcm/*.ima
%   <subjFolder>/<series name>/...        e.g. a PACS/Olea export such as
%                                          CEST008_.../CEST008_..._WASABI/DICOM/EXP00000/EXP0000 -
%                                          instance files several folders deep, no file extension
%
% Every series folder found gets converted, not just the APTw/WASABI
% ones - other series (e.g. scanner- or Olea-computed B0/B1/ST_AUC maps
% sitting alongside the raw data) just end up as extra .nii files that
% find_series_file() below ignores; they're handy to keep around for a
% visual sanity check against this pipeline's own output.
%
% Skips the whole conversion step if <subjFolder>/nii already has a
% correctly-sized APTw nii (matching cfg.singleB1_id, with
% numel(cfg.aptw_seq.offsetlist_ppm) volumes) and WASABI nii (matching
% cfg.wasabi_id, with numel(cfg.wasabi_seq.offsetlist_ppm) volumes) -
% not just "any .nii files at all", since that would happily reuse a
% stale/incomplete file left over from an earlier run (e.g. before a
% pipeline update, or from an interrupted conversion) without ever
% re-running dcm2niix. Set cfg.force_dicom_conversion = true to force
% reconversion regardless.
%
% If reconversion IS going to happen, every existing file in the nii
% folder is deleted first (including any *_REG_* motion-correction
% output, which would otherwise silently get reused against the new
% source data). This is what stops re-runs from piling up duplicate
% dcm2niix output (...fatsat.nii, ...fatsata.nii, ...) that
% find_series_file() could later pick the wrong one of.
%
% Instance files are always staged into a flat temp folder with a .dcm
% extension before calling dcm2niix, however deep or however they were
% originally named - dcm2niix does not reliably convert extension-less
% files sitting several folders deep in one pass.

niiFolder = fullfile(subjFolder, 'nii');
if ~isfolder(niiFolder), mkdir(niiFolder); end

alreadyValid = ~cfg.force_dicom_conversion && ...
    matching_nii_has_expected_volumes(niiFolder, cfg.singleB1_id, numel(cfg.aptw_seq.offsetlist_ppm)) && ...
    matching_nii_has_expected_volumes(niiFolder, cfg.wasabi_id, numel(cfg.wasabi_seq.offsetlist_ppm));
if alreadyValid
    fprintf(['nii folder already has a correctly-sized APTw and WASABI conversion - skipping ' ...
        'DICOM conversion (set cfg.force_dicom_conversion = true to force).\n']);
    return
end

legacyDcmRoot = fullfile(subjFolder, 'dcm');
if isfolder(legacyDcmRoot)
    seriesRoot = legacyDcmRoot;
else
    seriesRoot = subjFolder;
end

seriesDirs = dir(seriesRoot);
seriesDirs = seriesDirs([seriesDirs.isdir] & ~ismember({seriesDirs.name}, {'.', '..', 'nii', 'Zeval'}));
if isempty(seriesDirs)
    error(['No usable .nii files found in %s (need one matching "%s" with %d volumes and one ' ...
           'matching "%s" with %d volumes) and no series sub-folders under %s to convert from.\n' ...
           'Expected the raw DICOM series folders either directly under the subject folder or ' ...
           'under a dcm/ sub-folder.'], ...
           niiFolder, cfg.singleB1_id, numel(cfg.aptw_seq.offsetlist_ppm), ...
           cfg.wasabi_id, numel(cfg.wasabi_seq.offsetlist_ppm), seriesRoot);
end

% Only now that a conversion is definitely both needed AND possible: clear
% out whatever is in nii/ (stale/incomplete fragments from an earlier run,
% plus any *_REG_* motion-correction output computed against them, which
% would otherwise be silently reused against the newly converted data).
existingFiles = dir(niiFolder);
existingFiles = existingFiles(~[existingFiles.isdir]);
fprintf('Converting DICOM to NIfTI (clearing %d existing file(s) in nii/ first)...\n', numel(existingFiles));
for k = 1:numel(existingFiles)
    delete(fullfile(niiFolder, existingFiles(k).name));
end

if isunix
    dcm2niix_exe = 'dcm2niix';
    if isempty(which(dcm2niix_exe)) && exist('/usr/bin/dcm2niix', 'file') ~= 2 ...
            && system('command -v dcm2niix >/dev/null 2>&1') ~= 0
        error(['dcm2niix was not found on the system PATH. Install it (e.g. via your package ' ...
               'manager or https://github.com/rordenlab/dcm2niix) and make sure it is on PATH.']);
    end
else
    % Prefer the copy bundled with this project; fall back to PATH.
    bundledExe = fullfile(binFolder, 'dcm2niix.exe');
    if isfile(bundledExe)
        dcm2niix_exe = bundledExe;
    else
        dcm2niix_exe = which('dcm2niix.exe');
        if isempty(dcm2niix_exe)
            error('dcm2niix.exe not found in %s or on the MATLAB path.', binFolder);
        end
    end
end

for ii = 1:numel(seriesDirs)
    seriesFolder = fullfile(seriesRoot, seriesDirs(ii).name);
    instanceFiles = dir(fullfile(seriesFolder, '**', '*'));
    instanceFiles = instanceFiles(~[instanceFiles.isdir]);
    if isempty(instanceFiles)
        fprintf('Skipping %s - no files found in it.\n', seriesDirs(ii).name);
        continue
    end

    stageFolder = fullfile(tempdir, ['dcmstage_' seriesDirs(ii).name]);
    if isfolder(stageFolder), rmdir(stageFolder, 's'); end
    mkdir(stageFolder);
    copy_dicom_files_plain(instanceFiles, stageFolder);

    if isunix
        system(sprintf('%s -b n -f "%s" -o %s %s', dcm2niix_exe, 'MID%6s_%p', niiFolder, stageFolder));
    else
        dos(sprintf('"%s" -b n -f "%s" -o "%s" "%s"', dcm2niix_exe, 'MID%6s_%p', niiFolder, stageFolder));
    end
    rmdir(stageFolder, 's');
end
end

function copy_dicom_files_plain(files, destFolder)
for jj = 1:numel(files)
    srcFile = fullfile(files(jj).folder, files(jj).name);
    copyfile(srcFile, fullfile(destFolder, sprintf('%06d_%s.dcm', jj, files(jj).name)));
end
end

function regFile = ensure_motion_corrected(niiFolder, aptwFile, wasabiFile, cfg)
% Motion-corrects the APTw Z-spectrum time series onto offset
% offset 1 of the WASABI volume, using CEST_MOCO. Reuses an
% existing *_REG_* result instead of recomputing it unless
% cfg.force_moco is true.
[~, aptwBase] = fileparts(aptwFile);
existing = dir(fullfile(niiFolder, [aptwBase '_REG_*.nii']));
if ~isempty(existing) && ~cfg.force_moco
    [~, idx] = max([existing.datenum]);
    regFile = fullfile(niiFolder, existing(idx).name);
    fprintf('Reusing existing motion-corrected file: %s\n', existing(idx).name);
    return
end

origDir = pwd;
cleanupObj = onCleanup(@() cd(origDir)); %#ok<NASGU>
cd(niiFolder);
[~, aptwName, aptwExt]     = fileparts(aptwFile);
[~, wasabiName, wasabiExt] = fileparts(wasabiFile);
fprintf('Running motion correction of %s onto %s (offset %d)...\n', ...
    [aptwName aptwExt], [wasabiName wasabiExt], 1);
newName = CEST_MOCO([wasabiName wasabiExt], [aptwName aptwExt], 1, [], ...
    'spm', 'bfc', cfg.aptw_seq.moco_interp_idx);
regFile = fullfile(niiFolder, newName);
end
