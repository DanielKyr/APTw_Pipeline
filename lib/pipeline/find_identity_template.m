function template = find_identity_template(subjFolder, seriesID, targetPixelSpacing)
% FIND_IDENTITY_TEMPLATE  Finds the raw DICOM series whose folder name contains
% seriesID and whose PixelSpacing is closest to targetPixelSpacing -
% disambiguates e.g. a "_repeat" acquisition sitting alongside the main one
% (see save_aptw_dicom's header comment for why this matters). Returns []
% (with a warning) if no matching series is found at all.
d = dir(fullfile(subjFolder, '**', ['*' seriesID '*']));
d = d([d.isdir]);
candidates = unique(fullfile({d.folder}, {d.name}));
template = []; bestErr = Inf;
for i = 1:numel(candidates)
    files = dir(fullfile(candidates{i}, '**', '*'));
    files = files(~[files.isdir]);
    % First file alphabetically is often a DICOMDIR (a valid DICOM file, so
    % dicominfo doesn't error on it, but it lacks PixelSpacing/image tags) -
    % keep trying files until one actually has PixelSpacing.
    di = [];
    for k = 1:numel(files)
        try
            diCandidate = dicominfo(fullfile(files(k).folder, files(k).name));
        catch
            continue
        end
        if isfield(diCandidate, 'PixelSpacing')
            di = diCandidate;
            break
        end
    end
    if isempty(di), continue; end
    err = max(abs(di.PixelSpacing(:)' - targetPixelSpacing));
    if err < bestErr
        bestErr = err; template = di;
    end
end
if isempty(template)
    warning(['No raw DICOM series found matching "%s" - the exported DICOM will have a fresh ' ...
        'FrameOfReferenceUID and no patient/study linkage tags.'], seriesID);
end
end
