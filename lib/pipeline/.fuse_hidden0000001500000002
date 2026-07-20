function tf = looks_like_subject_folder(folder, cfg)
% Tells a single SUBJECT folder (immediate children are DICOM SERIES, or
% its nii/ is already populated) apart from a batch folder (immediate
% children are separate SUBJECT folders) - so DATA_ROOT can point at
% either level and just work.
niiFolder = fullfile(folder, 'nii');
haveAPTw   = ~isempty(dir(fullfile(niiFolder, ['*' cfg.singleB1_id '*.nii'])));
haveWasabi = ~isempty(dir(fullfile(niiFolder, ['*' cfg.wasabi_id '*.nii'])));
if haveAPTw && haveWasabi
    tf = true;
    return
end

% Not converted yet - look for a raw WASABI series sub-folder. The
% WASABI series' folder naming tends to be far more consistent across
% exports than the APTw series (whose DICOM SeriesDescription, and hence
% its converted filename, may differ from the raw folder name - e.g.
% CEST008_..._APT on disk becomes ..._APTw_001_FA7_fatsat.nii once
% converted - see convert_dicom_to_nii), so it's the more reliable signal
% here.
seriesRoot = folder;
legacyDcmRoot = fullfile(folder, 'dcm');
if isfolder(legacyDcmRoot)
    seriesRoot = legacyDcmRoot;
end
d = dir(seriesRoot);
names = {d([d.isdir] & ~ismember({d.name}, {'.', '..'})).name};
tf = any(contains(names, cfg.wasabi_id));
end
