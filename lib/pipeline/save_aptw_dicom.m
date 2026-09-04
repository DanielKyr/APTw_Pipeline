function outFolder = save_aptw_dicom(subjFolder, zevalFolder, subjectID, aptwMap, aptwField, mask, cfg)
% SAVE_APTW_DICOM  Writes the final APTw map as its own DICOM series (one file
% per slice) so it can be reloaded as a proper parametric map (e.g. into Olea)
% instead of just a NIfTI. Every in-FOV voxel is written (same FOV as the NIfTI
% export), but background (outside the brain mask, or non-finite) is flagged
% the same way Olea's own SC_ST_AUC(...)(Masked) export flags it: raw pixel 0,
% tagged as PixelPaddingValue, decoding via RescaleIntercept to a value far
% below any real APTw reading - so a viewer (or a naive re-read of the pixel
% data) can't mistake "no data" for an actual 0% measurement.
%
% RescaleSlope/RescaleIntercept/WindowCenter/WindowWidth are hard-coded to
% Olea's own values (see the encoding note below for why - in short: it's the
% only way to get byte-for-byte the same saturation/contrast behavior Olea's
% own export has, without every subject needing its own matching Olea series).
%
% Geometry (ImagePositionPatient/ImageOrientationPatient/PixelSpacing) is
% derived directly from the WASABI nii's own affine, NOT copied from a raw
% DICOM file - our maps are on the WASABI acquisition's grid (Run_APTw_
% Pipeline.m motion-corrects APTw onto WASABI). This sidesteps needing to
% pick the "right" raw WASABI folder when more than one exists (e.g. a
% "_repeat" acquisition alongside the main one).
niiFolder = fullfile(subjFolder, 'nii');
wasabiNiiFiles = dir(fullfile(niiFolder, '*WASAB*.nii'));
if isempty(wasabiNiiFiles)
    warning('No WASABI nii found under %s\\nii - skipping DICOM export of the APTw map.', subjFolder);
    outFolder = '';
    return
end
info = niftiinfo(fullfile(wasabiNiiFiles(1).folder, wasabiNiiFiles(1).name));
T  = info.Transform.T;
sz = info.ImageSize; nCols = sz(1); nRows = sz(2); nSlices = sz(3);

rowAxis = T(1, 1:3) / norm(T(1, 1:3));
colAxis = T(2, 1:3) / norm(T(2, 1:3));
iop = [rowAxis .* [-1 -1 1], colAxis .* [1 1 -1]]; % RAS -> LPS, col axis reversed (DICOM row 0 = nii j = nRows-1)
pixelSpacing = [norm(T(2, 1:3)), norm(T(1, 1:3))]; % DICOM order: [row spacing, column spacing]
sliceThickness = norm(T(3, 1:3));

% Identity/frame-of-reference tags: only filled in if exactly one raw WASABI
% DICOM series is found whose PixelSpacing matches this nii's grid - otherwise
% proceeds without patient/study linkage rather than silently borrowing the
% wrong acquisition's identity.
template = find_identity_template(subjFolder, cfg.wasabi_raw_id, pixelSpacing);

outFolder = fullfile(zevalFolder, sprintf('%s_%s_DICOM', subjectID, aptwField));
if ~isfolder(outFolder), mkdir(outFolder); end

mapPct = aptwMap * 100; % match Olea's own APTw units (%)
bg = ~isfinite(mapPct) | ~(mask > 0); % Segment uses NaN (not 0) for background, so mask>0 - not mask==0 - is "in-brain"
mapPct(~isfinite(mapPct)) = 0;

% Encoding: unsigned pixels, raw 0 reserved as PixelPaddingValue for background.
% RescaleSlope/RescaleIntercept are hard-coded to Olea's own values, read
% directly off CEST008's raw SC_ST_AUC(...)(Masked) DICOM via dicominfo - not
% looked up per-subject because not every subject has a matching Olea series
% to read, and every subject should get the same encoding regardless. These
% numbers reproduce uint16 saturation at the exact real-value bounds Olea's
% own export saturates at ([-24.12, +24.43]%), not an arbitrary clip.
RescaleSlope = cfg.dicom_rescale_slope; RescaleIntercept = cfg.dicom_rescale_intercept;
pixU = uint16(round((mapPct - RescaleIntercept) / RescaleSlope)); % saturates to [0,65535] automatically
pixU(bg) = 0; % PixelPaddingValue sentinel - forced regardless of what the formula above would have given

% WindowCenter/WindowWidth: hard-coded to Olea's own values too - checked
% across every slice of CEST008's AND CEST003's raw SC_ST_AUC series, Olea
% writes WindowCenter=2/WindowWidth=6 on every single one, not something
% derived per-subject from the data's own percentiles (a per-subject
% percentile window is fragile: a noisier subject's fit can drag its own
% 2-98th percentile into the thousands, giving a broken initial contrast in
% any viewer that honors these tags).
w = [cfg.dicom_window_center - cfg.dicom_window_width/2, cfg.dicom_window_center + cfg.dicom_window_width/2];

seriesUID = dicomuid();
% 'CreateMode','Copy' below always warns that SOPClassUID is "ignored" for that mode -
% it isn't: MediaStorageSOPClassUID/SOPClassUID come through in the file exactly as
% set (verified against a written-then-reread file). Silence just this one warning
% ID for the duration of the write loop rather than every field-dropping check
% 'Create' mode would otherwise silently do instead.
warnState = warning('off', 'images:dicomwrite:inconsistentIODAndCreateModeOptions');
cleanupWarn = onCleanup(@() warning(warnState));
for k = 1:nSlices
    meta = struct();
    if ~isempty(template)
        for fn = {'PatientName', 'PatientID', 'PatientBirthDate', 'PatientSex', 'PatientAge', ...
                  'StudyInstanceUID', 'StudyID', 'StudyDate', 'StudyTime', 'AccessionNumber', ...
                  'ReferringPhysicianName', 'InstitutionName', 'FrameOfReferenceUID', ...
                  'MagneticFieldStrength', 'BodyPartExamined'}
            if isfield(template, fn{1}), meta.(fn{1}) = template.(fn{1}); end
        end
    end
    meta.Modality                  = 'MR';
    meta.SOPClassUID                = '1.2.840.10008.5.1.4.1.1.4'; % MR Image Storage - matches how Olea exports its own derived maps
    meta.SOPInstanceUID             = dicomuid();
    meta.SeriesInstanceUID          = seriesUID;
    meta.SeriesNumber                = 9100;
    meta.InstanceNumber              = k;
    meta.SeriesDescription           = sprintf('%s (APTw_Pipeline export)', aptwField);
    meta.ImageType                   = 'DERIVED\SECONDARY\OTHER';
    meta.Rows = nRows; meta.Columns = nCols;
    meta.PixelSpacing                = pixelSpacing(:);
    meta.SliceThickness              = sliceThickness;
    meta.ImageOrientationPatient     = iop(:);
    world0 = [0, nRows - 1, k - 1, 1] * T;
    meta.ImagePositionPatient        = (world0(1:3) .* [-1 -1 1])';
    meta.RescaleSlope                = RescaleSlope;
    meta.RescaleIntercept            = RescaleIntercept;
    meta.RescaleType                 = 'US';
    meta.WindowCenter                = mean(w);
    meta.WindowWidth                 = max(diff(w), 1);
    meta.SamplesPerPixel             = 1;
    meta.PhotometricInterpretation   = 'MONOCHROME2';
    meta.PixelRepresentation         = 0;
    meta.PixelPaddingValue           = uint16(0);
    meta.BitsAllocated               = 16;
    meta.BitsStored                  = 16;
    meta.HighBit                     = 15;

    sliceImg = flipud(permute(pixU(:, :, k), [2 1])); % nii (i,j) -> DICOM (row,col)
    outFile = fullfile(outFolder, sprintf('%s_%s_%03d.dcm', subjectID, aptwField, k));
    % 'CreateMode','Create' (the default) validates against MATLAB's built-in module
    % list per SOPClassUID and silently drops any field outside it - including
    % RescaleSlope/RescaleIntercept/RescaleType, which are essential here. 'Copy'
    % mode writes exactly the fields given instead.
    dicomwrite(sliceImg, outFile, meta, 'CreateMode', 'Copy');
end
fprintf('Saved %s map as a %d-slice DICOM series (background = padding value %g%%): %s\n', ...
    aptwField, nSlices, RescaleIntercept, outFolder);
end
