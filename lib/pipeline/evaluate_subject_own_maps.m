function result = evaluate_subject_own_maps(subjFolder, cfg)
% EVALUATE_SUBJECT_OWN_MAPS  Loads a subject's Zeval/<id>_APTw_results.mat
% (written by run_APTw_subject) and, if cfg.saveOutputs, exports the selected
% APTw map as NIfTI + DICOM. This is the GUI-facing subset of
% Evaluate_APTw_Results.m's evaluate_subject - it does NOT do any
% scanner/Olea comparison (see Evaluate_APTw_Results.m for that).
%
% Recognized cfg fields (see aptw_default_cfg.m for defaults):
%   aptw_metric        - 'fs' (conventional 1/Zref^2) or 'rex' (inverse-Z / MTRRex)
%   aptw_b1_corrected  - true: grade the normal, B1-corrected map; false: the *_noB1 map
%   saveOutputs        - true: also write the NIfTI + DICOM export
%   wasabi_raw_id, dicom_rescale_slope/intercept, dicom_window_center/width
%                      - passed through to save_aptw_dicom
%
% Returns a struct with fields: subjectID, aptwField, aptwLabel, aptwMap,
% results (the full loaded S struct), niftiFile, dicomFolder.

[~, subjectID] = fileparts(subjFolder);
zevalFolder = fullfile(subjFolder, 'Zeval');
resultsFile = fullfile(zevalFolder, [subjectID '_APTw_results.mat']);
S = load(resultsFile);

switch lower(cfg.aptw_metric)
    case 'fs',  aptwField = 'APTw';
    case 'rex', aptwField = 'APTw_rex';
    otherwise,  error('cfg.aptw_metric must be ''fs'' or ''rex'', got ''%s''.', cfg.aptw_metric);
end
if ~cfg.aptw_b1_corrected, aptwField = [aptwField '_noB1']; end
if ~isfield(S.maps, aptwField)
    error(['%s has no maps.%s field. If cfg.aptw_b1_corrected = false, this results file was ' ...
           'likely written before the *_noB1 maps were added - re-run the pipeline on this ' ...
           'subject to regenerate it.'], resultsFile, aptwField);
end
aptwMap = S.maps.(aptwField);
aptwLabel = 'APTw (%)';
if ~cfg.aptw_b1_corrected, aptwLabel = 'APTw no-B1 (%)'; end

niftiFile = ''; dicomFolder = '';
if cfg.saveOutputs
    niftiFile   = save_aptw_nifti(subjFolder, zevalFolder, subjectID, aptwMap, aptwField);
    dicomFolder = save_aptw_dicom(subjFolder, zevalFolder, subjectID, aptwMap, aptwField, S.qc.Segment, cfg);
end

result = struct('subjectID', subjectID, 'aptwField', aptwField, 'aptwLabel', aptwLabel, ...
    'aptwMap', aptwMap, 'results', S, 'niftiFile', niftiFile, 'dicomFolder', dicomFolder);
end
