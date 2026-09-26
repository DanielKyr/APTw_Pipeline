function [Segment, c_all] = ensure_brain_segmentation(regFile, zevalFolder, subjectID, cfg)
% ENSURE_BRAIN_SEGMENTATION  Cached wrapper around CreateBinaryBrainmaskWithSPM.
%
% SPM tissue segmentation is one of the slower steps in the pipeline and,
% unlike the WASABI fit, was previously never cached - every run redid it
% from scratch. This reuses Zeval/<subjectID>_Segmentation.mat unless
% cfg.force_segmentation is true.
%
% cfg.mask_threshold and cfg.use_c6 select which SPM tissue classes are
% combined into the binary mask - see CreateBinaryBrainmaskWithSPM's own
% header for the GM+WM+CSF>threshold vs "everything but air" (c6) choice.

segMat = fullfile(zevalFolder, [subjectID '_Segmentation.mat']);
% A segmentation older than regFile was computed from a previous (possibly
% incomplete/uncorrected) motion-correction output, so it is stale.
isStale = false;
if isfile(segMat) && isfile(regFile)
    segInfo = dir(segMat); regInfo = dir(regFile);
    isStale = segInfo.datenum < regInfo.datenum;
end
if isStale
    fprintf('Existing brain segmentation predates the motion-corrected input - recomputing.\n');
end
if isfile(segMat) && ~cfg.force_segmentation && ~isStale
    fprintf('Reusing existing brain segmentation: %s\n', segMat);
    segData = load(segMat);
    Segment = segData.Segment;
    c_all   = segData.c_all;
    return
end

fprintf('Running SPM brain segmentation...\n');
[Segment, c_all] = CreateBinaryBrainmaskWithSPM(regFile, cfg.mask_threshold, 1, 0, 1, cfg.use_c6);

segData = struct();
segData.Segment = Segment;
segData.c_all   = c_all;
save(segMat, '-struct', 'segData');
end
