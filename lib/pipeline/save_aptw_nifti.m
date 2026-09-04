function outFile = save_aptw_nifti(subjFolder, zevalFolder, subjectID, aptwMap, aptwField)
% SAVE_APTW_NIFTI  Writes an APTw (or B0/B1) map to its own .nii file in Zeval/,
% using the subject's motion-corrected "_REG_" NIfTI as a header/affine template
% so the exported map opens correctly aligned in any NIfTI viewer (ITK-SNAP,
% MRIcroGL, fsleyes, ...) or alongside the raw data. aptwField (e.g. 'APTw_rex'
% or 'APTw_rex_noB1') names the maps.* field this came from, and is used as-is
% in the output filename.
regFile = dir(fullfile(subjFolder, 'nii', '*_REG_*.nii'));
if isempty(regFile)
    warning('No "_REG_" NIfTI found under %s\\nii - skipping NIfTI export of the %s map.', subjFolder, aptwField);
    outFile = '';
    return
end
info = niftiinfo(fullfile(regFile(1).folder, regFile(1).name));
info.ImageSize       = size(aptwMap);
info.PixelDimensions = info.PixelDimensions(1:numel(info.ImageSize));
info.Datatype        = 'single';

outFile = fullfile(zevalFolder, sprintf('%s_%s.nii', subjectID, aptwField));
niftiwrite(single(aptwMap), outFile, info, 'Compressed', false);
fprintf('Saved %s map as NIfTI: %s\n', aptwField, outFile);
end
