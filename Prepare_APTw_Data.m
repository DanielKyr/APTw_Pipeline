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

% All cfg fields start from the shared defaults in lib/pipeline/aptw_default_cfg.m
% - the same defaults the GUI (gui/APTwPipelineApp.m) and Run_APTw_Pipeline.m /
% Evaluate_APTw_Results.m use.
cfg = aptw_default_cfg();

% Set true to force a step to re-run even if its output already exists.
% force_moco is deliberately separate and defaults to false - see the note
% at the top of this file about why re-running motion correction is not free.
cfg.force_dicom_conversion = false;
cfg.force_moco             = false;

%% ========================= SELECT SUBJECTS =========================
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

