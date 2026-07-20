# APTw_Pipeline

Self-contained, single-B1 3T APTw (CEST) evaluation pipeline. Everything
it calls, other than SPM12 and a few MATLAB toolboxes, lives in this
folder.

## Folder structure

```
APTw_Pipeline/
    Run_APTw_Pipeline.m       <- entry point: DICOM -> NIfTI -> WASABI fit -> APTw map
    Evaluate_APTw_Results.m   <- standalone: QC figures + Olea/scanner-map comparison
    Check_DICOM_Series.m      <- standalone diagnostic (see below)
    README.md                 <- this file
    bin/
        dcm2niix.exe          Windows DICOM->NIfTI converter (bundled)
    lib/                      everything on the MATLAB path these scripts need
        loading/              readnifti.m
        segmentation/         CreateBinaryBrainmaskWithSPM.m (SPM-based)
        moco/                 CEST_MOCO.m + SPM motion-correction/BFC wrappers
        evaluation/           B0 correction, normalization, WASABI fit dispatch
        denoising/            local-PCA denoising
        b1_correction/        B1 correction
        fitting/              WASABI curve-fit model + levmar MEX binaries
        wasabi/                WASABI lookup-table helpers (fit initial guess)
        tools/                 small numeric utilities (gamma_, find_nearest)
```

Both scripts add `lib/` (recursively) to the MATLAB path automatically
the moment they run - you don't need to run any setup step yourself.

`Run_APTw_Pipeline.m` and `Evaluate_APTw_Results.m` are deliberately
separate: the pipeline only computes and saves results (no figures, no
comparison), and the evaluation script only reads what the pipeline
already saved. Re-running an evaluation (e.g. after tweaking
`cfg.olea_orient`) never re-runs any of the actual processing.

## Prerequisites

- **SPM12**, installed separately and on the MATLAB path (`Run_APTw_Pipeline.m`
  checks for it and errors immediately with a clear message if it's
  missing). Get it from
  https://www.fil.ion.ucl.ac.uk/spm/software/spm12/
- MATLAB toolboxes: Statistics and Machine Learning Toolbox, Curve
  Fitting Toolbox, Image Processing Toolbox. Optimization Toolbox is
  used only as a fallback if the bundled `levmar` MEX binary isn't
  supported on your platform. Parallel Computing Toolbox is optional -
  the code degrades to serial execution automatically if it's not
  licensed.
- **dcm2niix**: bundled as `bin/dcm2niix.exe` on Windows. On
  macOS/Linux, install it separately (e.g. via your package manager or
  https://github.com/rordenlab/dcm2niix) and make sure it's on your
  system PATH - it's a small external binary, not something MATLAB code
  can substitute for.
- Nothing extra is needed for `Evaluate_APTw_Results.m` -
  `dicominfo`/`dicomread`/`corrcoef`/plotting are all base MATLAB.

## Running it

1. Open `Run_APTw_Pipeline.m`. In `USER SETTINGS`, set `DATA_ROOT` to
   either a single subject folder or a folder containing one sub-folder
   per subject - both are auto-detected, so either is fine (or leave it
   `''` to pick interactively via a standard folder dialog). Adjust
   `cfg.aptw_seq` / `cfg.wasabi_seq` if your protocol differs from the
   defaults (read off from MID0013_..._APTw_001...log /
   MID0017_..._WASABI.log).
2. Run it. No further clicking required - it converts DICOM to NIfTI if
   needed, motion-corrects, fits WASABI for B0/B1, corrects and denoises
   the APTw Z-spectra, and writes results per subject (see below).
3. Open `Evaluate_APTw_Results.m` to look at the results: QC figures for
   the pipeline's own APTw/B0/B1 maps, plus - if a scanner/Olea-computed
   map is found next to the raw data - a full comparison (orientation
   check, side-by-side + difference maps, scatter + Bland-Altman,
   distributions, per-slice correlation, and B1-dependence diagnostics
   for APTw). Set `DATA_ROOT` the same way as step 1 and run it; look at
   the "orientation check" figure first for each map and adjust
   `cfg.olea_orient` if the two panels aren't anatomically aligned.

## Output per subject (in `<subject>/Zeval/`)

From `Run_APTw_Pipeline.m`:
- `<subjectID>_APTw_results.mat` - small: the APTw map (fluid-suppressed,
  ~3.5 ppm) plus B0/B1 maps and QC info. This is what
  `Evaluate_APTw_Results.m` reads, and the file to open first.
- `<subjectID>_APTw_full_Zspectra.mat` - large: full Z-spectrum stacks at
  every processing stage, for deeper QA/reuse.
- `<subjectID>_WASABI_fit.mat` - cached WASABI B0/B1 fit (reused on
  reruns unless `cfg.overwrite_wasabi = true`).

From `Evaluate_APTw_Results.m` (one set per scanner/Olea map found - a
DICOM series folder whose name contains `cfg.olea_id`/`cfg.olea_b0_id`/
`cfg.olea_b1_id`, defaults `'SC_ST'`/`'dB0'`/`'rB1'` - each independent,
any subset may be missing), tagged `aptw`/`b0`/`b1`:
- `<subjectID>_<tag>_orientcheck.png`, `_maps.png`, `_diff.png`,
  `_scatter_BA.png`, `_distributions.png` - the full comparison figure
  set, plus `_B1resid.png`/`_B1value.png` for APTw specifically.
- `<subjectID>_<tag>_agreement_stats.mat` - Pearson/Spearman, bias, 95%
  limits of agreement, MAE, per-slice r.
- Set `cfg.saveOutputs = false` in `Evaluate_APTw_Results.m` to only show
  figures without saving any of the above.

## If dcm2niix fails to convert a series

`Check_DICOM_Series.m` is a standalone diagnostic (no pipeline
dependency) that reads DICOM headers in a folder and reports how many
distinct SeriesInstanceUIDs, slice positions, and instance numbers are
actually in there - run it directly against the offending raw series
folder to see facts instead of guessing:

```matlab
Check_DICOM_Series('C:\...\CEST008\CEST008_..._WASABI')
```

## What's deliberately excluded

This folder contains only the functions actually reached at runtime
given this pipeline's fixed settings (motion correction via SPM only,
WASABI fit model `WASABIFIT_2abs`/021031, non-neural lookup table for
fit initial guesses). The full `cest_eval-main` repository has many
other pipelines, MOCO methods (AFNI, elastix, LRAZ), and fit models
that this pipeline doesn't use - none of that is copied here. If you
need those, use the full repository instead.

One thing no script can check for you: if your B1 (slab-selective
transmit) data differs in brightness between slices, run
`FAUBATCH_B1map_Correction.m` (in the full `cest_eval-main` repository)
on it BEFORE using this pipeline.
