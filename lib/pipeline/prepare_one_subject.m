function regFile = prepare_one_subject(subjFolder, cfg, binFolder)
% PREPARE_ONE_SUBJECT  DICOM -> NIfTI -> motion-corrected NIfTI for one subject.
%
% Recognized cfg fields (see aptw_default_cfg.m for defaults):
%   singleB1_id, wasabi_id, aptw_seq, wasabi_seq   - sequence identification
%   force_dicom_conversion, force_moco             - cache-bypass toggles
%   emit_stage_markers                             - if true, prints DICOM/MOCO "__STAGE__:" sentinels
if ~isfield(cfg, 'emit_stage_markers'), cfg.emit_stage_markers = false; end
if isfield(cfg, 'use_parallel')
    if ~isfield(cfg, 'max_workers'), cfg.max_workers = 0; end
    aptw_parallel_enabled(cfg.use_parallel, cfg.max_workers);
end
if ~isfield(cfg, 'moco_coreg_sep'), cfg.moco_coreg_sep = []; end
niiFolder = fullfile(subjFolder, 'nii');

% ---- 1. Convert DICOM to NIfTI if needed. convert_dicom_to_nii decides
%         for itself by checking nii CONTENT (correct volume count), not
%         mere file existence, so an interrupted earlier conversion cannot
%         leave stale fragments that get reused forever.
if cfg.emit_stage_markers, fprintf('__STAGE__:DICOM_START\n'); end
convert_dicom_to_nii(subjFolder, cfg, binFolder);
if cfg.emit_stage_markers, fprintf('__STAGE__:DICOM_DONE\n'); end

aptwFile   = find_series_file(niiFolder, cfg.singleB1_id, numel(cfg.aptw_seq.offsetlist_ppm));
wasabiFile = find_series_file(niiFolder, cfg.wasabi_id,   numel(cfg.wasabi_seq.offsetlist_ppm));

% ---- 2. Motion-correct the Z-spectrum time series onto the WASABI volume.
if cfg.emit_stage_markers, fprintf('__STAGE__:MOCO_START\n'); end
regFile = ensure_motion_corrected(niiFolder, aptwFile, wasabiFile, cfg);
if cfg.emit_stage_markers, fprintf('__STAGE__:MOCO_DONE\n'); end
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
% find_series_file() below ignores.
%
% Skips the whole conversion step if <subjFolder>/nii already has a
% correctly-sized APTw nii (matching cfg.singleB1_id, with
% numel(cfg.aptw_seq.offsetlist_ppm) volumes) and WASABI nii (matching
% cfg.wasabi_id, with numel(cfg.wasabi_seq.offsetlist_ppm) volumes).
% Set cfg.force_dicom_conversion = true to force reconversion regardless.
%
% If reconversion IS going to happen, every existing file in the nii
% folder is deleted first (including any *_REG_* motion-correction
% output, which would otherwise silently get reused against the new
% source data).
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
%
% CEST_MOCO_spm creates the *_REG_* file as an UNCORRECTED copy of the raw
% stack before registering any offset, so an interrupted run (cancel, crash,
% hang + restart) leaves a *_REG_* file that looks finished but isn't
% motion-corrected at all. Only a *_REG_* file with a "<name>.complete"
% marker next to it - written below once CEST_MOCO has fully returned - is
% trusted; anything else is deleted and redone.
[~, aptwBase] = fileparts(aptwFile);
existing = dir(fullfile(niiFolder, [aptwBase '_REG_*.nii']));
if ~cfg.force_moco
    complete = arrayfun(@(e) isfile(fullfile(niiFolder, [e.name '.complete'])), existing);
    if any(complete)
        done = existing(complete);
        [~, idx] = max([done.datenum]);
        regFile = fullfile(niiFolder, done(idx).name);
        fprintf('Reusing existing motion-corrected file: %s\n', done(idx).name);
        return
    end
end
for k = 1:numel(existing)
    fprintf('Discarding incomplete/stale motion-corrected file: %s\n', existing(k).name);
    delete(fullfile(niiFolder, existing(k).name));
    staleMarker = fullfile(niiFolder, [existing(k).name '.complete']);
    if isfile(staleMarker), delete(staleMarker); end
    staleResliced = fullfile(niiFolder, ['r' existing(k).name]); % WASABI-grid copy, see CEST_MOCO_spm
    if isfile(staleResliced), delete(staleResliced); end
end

origDir = pwd;
cleanupObj = onCleanup(@() cd(origDir)); %#ok<NASGU>
cd(niiFolder);
[~, aptwName, aptwExt]     = fileparts(aptwFile);
[~, wasabiName, wasabiExt] = fileparts(wasabiFile);
fprintf('Running motion correction of %s onto %s (offset %d)...\n', ...
    [aptwName aptwExt], [wasabiName wasabiExt], 1);
newName = CEST_MOCO([wasabiName wasabiExt], [aptwName aptwExt], 1, [], ...
    'spm', 'bfc', cfg.aptw_seq.moco_interp_idx, 0, 0, cfg.moco_coreg_sep);
regFile = fullfile(niiFolder, newName);
fid = fopen([regFile '.complete'], 'w');
fprintf(fid, 'motion correction completed %s\n', char(datetime('now')));
fclose(fid);
end
