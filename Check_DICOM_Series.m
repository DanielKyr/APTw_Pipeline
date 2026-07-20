function Check_DICOM_Series(folder)
% Check_DICOM_Series  Diagnostic only - reads DICOM headers in a folder
% and reports what's actually there. No conversion, no pipeline
% dependency, just dicominfo() on every file.
%
% Run this directly against a raw series folder (e.g. the WASABI folder
% under CEST008) to see facts instead of guesses: how many distinct
% SeriesInstanceUIDs are really in there, how many files per UID, what
% SeriesNumber/SeriesDescription/AcquisitionNumber they carry, what their
% InstanceNumber range is, and how many distinct slice positions there
% are. That's enough to tell whether a folder genuinely bundles more than
% one acquisition, or whether dcm2niix is just choking on something else
% (e.g. a handful of missing slices, or an ordering quirk) while it's
% really one coherent series - which is what MITK opening it cleanly
% would suggest.
%
% Usage:
%   Check_DICOM_Series('C:\...\CEST008\CEST008_03_03_2025_WASABI')
%   Check_DICOM_Series()   % pops up a folder picker

if nargin < 1 || isempty(folder)
    folder = uigetdir(pwd, 'Select a DICOM series folder to inspect');
    if isequal(folder, 0), return; end
end

files = dir(fullfile(folder, '**', '*'));
files = files(~[files.isdir]);
fprintf('%d file(s) found under %s\n\n', numel(files), folder);

uids       = cell(numel(files), 1);
seriesNums = nan(numel(files), 1);
seriesDesc = cell(numel(files), 1);
acqNums    = nan(numel(files), 1);
instNums   = nan(numel(files), 1);
sliceLoc   = nan(numel(files), 1);
ipp        = cell(numel(files), 1);
manufacturer = cell(numel(files), 1);
nBad = 0;

for k = 1:numel(files)
    f = fullfile(files(k).folder, files(k).name);
    try
        info = dicominfo(f);
    catch
        nBad = nBad + 1;
        continue
    end
    uids{k}         = getfield_or(info, 'SeriesInstanceUID', '');
    seriesNums(k)    = getfield_or(info, 'SeriesNumber', NaN);
    seriesDesc{k}    = getfield_or(info, 'SeriesDescription', '');
    acqNums(k)       = getfield_or(info, 'AcquisitionNumber', NaN);
    instNums(k)      = getfield_or(info, 'InstanceNumber', NaN);
    if isfield(info, 'ImagePositionPatient')
        ipp{k} = mat2str(info.ImagePositionPatient(:)');
    else
        ipp{k} = '';
    end
    if isfield(info, 'SliceLocation')
        sliceLoc(k) = info.SliceLocation;
    end
    manufacturer{k} = getfield_or(info, 'Manufacturer', '');
end

fprintf('Could not read %d/%d file(s) as DICOM (likely non-DICOM sidecar files, e.g. DICOMDIR/reports).\n\n', nBad, numel(files));

validIdx = ~cellfun(@isempty, uids);
uUIDs = unique(uids(validIdx));
fprintf('Unique SeriesInstanceUID values: %d\n', numel(uUIDs));
for u = 1:numel(uUIDs)
    idx = strcmp(uids, uUIDs{u});
    firstDesc = seriesDesc{find(idx, 1)};
    fprintf(['  [%d] %d files | SeriesNumber=%s | SeriesDescription="%s" | ' ...
        'AcquisitionNumber(s)=%s | InstanceNumber range=%g-%g | ' ...
        'unique ImagePositionPatient=%d | unique SliceLocation=%d\n'], ...
        u, sum(idx), mat2str(unique(seriesNums(idx))), firstDesc, ...
        mat2str(unique(acqNums(idx))'), min(instNums(idx)), max(instNums(idx)), ...
        numel(unique(ipp(idx))), numel(unique(sliceLoc(idx))));
end

goodManu = unique(manufacturer(~cellfun(@isempty, manufacturer)));
if isempty(goodManu)
    fprintf('\nNo Manufacturer (0008,0070) tag found in any file.\n');
else
    fprintf('\nManufacturer value(s) seen: %s\n', strjoin(goodManu, ', '));
end
end


function v = getfield_or(s, fname, default)
if isfield(s, fname)
    v = s.(fname);
else
    v = default;
end
end
