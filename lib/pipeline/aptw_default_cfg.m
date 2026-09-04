function cfg = aptw_default_cfg()
% APTW_DEFAULT_CFG  Single source of truth for every cfg field the pipeline
% functions (prepare_one_subject, run_APTw_subject, evaluate_subject_own_maps,
% save_aptw_dicom, ...) recognize, with the values the pipeline has always
% shipped with. Run_APTw_Pipeline.m / Prepare_APTw_Data.m / Evaluate_APTw_
% Results.m and APTwPipelineApp.m all start from this and override what they
% need, so there is exactly one place values are hard-coded.

cfg = struct();

% ---- series identification (Prepare + Run) ----
cfg.singleB1_id  = 'APTw_001';   % substring identifying the CEST Z-spectrum series
cfg.wasabi_id    = 'WASAB';      % substring identifying the WASABI series
[cfg.aptw_seq, cfg.wasabi_seq] = aptw_sequence_config();

% ---- cache-bypass toggles ----
cfg.force_dicom_conversion = false; % Prepare: redo DICOM->NIfTI even if a valid conversion exists
cfg.force_moco             = false; % Prepare: redo motion correction even if a "_REG_" file exists
cfg.force_segmentation     = false; % Run: redo SPM brain segmentation even if cached
cfg.force_wasabi           = false; % Run: redo the WASABI B0/B1 fit even if cached

% ---- brain mask definition (Run) ----
cfg.mask_threshold = 0.2;    % GM+WM+CSF probability threshold (BrainOnlyMask / PCA training set)
cfg.use_c6         = true;   % true: Segment = everything but pure background air (c6); false: GM+WM+CSF>threshold only

% ---- denoising / smoothing (Run) ----
cfg.pca_components      = 1:15; % which local-PCA components pcca_3D keeps
cfg.spatial_smooth_sigma = 0;   % optional per-slice/offset Gaussian blur sigma (voxels), 0 = off

% ---- output map selection (Evaluate) ----
cfg.aptw_metric       = 'rex';  % 'fs' (conventional 1/Zref^2) or 'rex' (inverse-Z / MTRRex)
cfg.aptw_b1_corrected = true;   % true: grade/export the B1-corrected map; false: the *_noB1 variant
cfg.saveOutputs       = true;   % write NIfTI + DICOM export (and, in the scripts, stats/figures)

% ---- DICOM export encoding (Evaluate), matched to Olea's own SC_ST_AUC export ----
cfg.wasabi_raw_id          = 'WASAB';        % raw WASABI DICOM series, used as the export's geometry/identity template
cfg.dicom_rescale_slope    = 0.000740738993;
cfg.dicom_rescale_intercept = -24.1181;
cfg.dicom_window_center    = 2;
cfg.dicom_window_width     = 6;

% ---- progress reporting (Run) ----
% OFF by default so the plain scripts' console output is unchanged. The GUI
% (gui/APTwPipelineApp.m) sets this true so it can parse "__STAGE__:..."
% sentinel lines out of the streamed log to drive its live stage checklist.
cfg.emit_stage_markers = false;
end
