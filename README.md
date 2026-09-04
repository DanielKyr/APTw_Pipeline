# APTw_Pipeline

Self-contained, single-B1 3T APTw (CEST) evaluation pipeline. Everything
it calls, other than SPM12 and a few MATLAB toolboxes, lives in this
folder.

## Folder structure

```
APTw_Pipeline/
    APTwGUI.m                 <- interactive GUI front-end (see "GUI" below)
    Prepare_APTw_Data.m       <- entry point: DICOM -> NIfTI -> motion correction (run once per subject)
    Run_APTw_Pipeline.m       <- entry point: WASABI fit -> APTw map
    Evaluate_APTw_Results.m   <- standalone: QC figures + Olea/scanner-map comparison
    Check_DICOM_Series.m      <- standalone diagnostic (see below)
    README.md                 <- this file
    bin/
        dcm2niix.exe          Windows DICOM->NIfTI converter (bundled)
    gui/
        APTwPipelineApp.m     GUI app (plain uifigure handle class, not .mlapp - see "GUI" below)
    lib/                      everything on the MATLAB path these scripts need
        pipeline/              per-subject processing steps (prepare/run/evaluate + shared
                                 defaults) called by BOTH the scripts above and the GUI, so
                                 results are identical either way - see below
        loading/              readnifti.m
        segmentation/         CreateBinaryBrainmaskWithSPM.m (SPM-based)
        moco/                 CEST_MOCO.m + SPM motion-correction/BFC wrappers
        evaluation/           B0 correction, normalization, WASABI fit dispatch
        denoising/            local-PCA denoising
        b1_correction/        B1 correction
        fitting/              WASABI curve-fit model + levmar MEX binaries
        wasabi/                WASABI lookup-table helpers (fit initial guess)
        tools/                 small numeric utilities (gamma_, find_nearest, pctwin, bluewhitered)
```

All entry points add `lib/` (recursively) to the MATLAB path automatically
the moment they run - you don't need to run any setup step yourself.

The three per-subject steps - `lib/pipeline/prepare_one_subject.m`,
`lib/pipeline/run_APTw_subject.m`, `lib/pipeline/evaluate_subject_own_maps.m`
- are the actual implementation; `Prepare_APTw_Data.m` / `Run_APTw_Pipeline.m`
/ `Evaluate_APTw_Results.m` and the GUI are thin drivers that call them in a
loop over subjects. `lib/pipeline/aptw_default_cfg.m` is the one place every
`cfg` field and its default value is defined - every driver (scripts and GUI)
starts from it. `Run_APTw_Pipeline.m` / `Evaluate_APTw_Results.m` are
deliberately separate from `Prepare_APTw_Data.m`: preparation and analysis
only compute and save results (no figures, no comparison), and the evaluation
script only reads what was already saved. Re-running an evaluation (e.g.
after tweaking `cfg.olea_orient`) never re-runs any of the actual processing.

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

## GUI

`APTwGUI.m` launches an interactive front-end (`gui/APTwPipelineApp.m`) as an
alternative to editing and running the three scripts by hand:

- **Subjects**: "Add Folder(s)" accepts either a single subject folder or a
  folder containing many (auto-detected, same rule the scripts use); each
  gets a row showing whether it's already Prepared/Processed from a past run
  (detected from `nii/`/`Zeval/` on disk). Select rows and "Run Selected", or
  "Run All" to batch the whole list. Each subject processes as its own
  background process (so the GUI stays fully usable while a subject runs -
  switch tabs, browse already-finished results, keep adjusting settings),
  with a live per-stage checklist and a "Cancel" that kills the running
  subject within about a second rather than waiting for it to finish.
- **Processing options**: force-recompute toggles for each cached stage
  (DICOM conversion, motion correction, brain segmentation, WASABI fit -
  all reused from `Zeval/`/`nii/` by default, same as the scripts), the
  APTw metric/B1-correction/smoothing/export choices, and an "Advanced"
  section for series IDs, brain-mask threshold, PCA component count, and
  the DICOM export encoding constants.
- **Results Viewer** tab: pick a processed subject and map (APTw/APTw_rex/
  B0/B1/...), scroll slices, adjust window/level or colormap, click any
  voxel on the map to plot its raw vs. denoised Z-spectrum, see a live
  histogram + stats panel, and toggle a side-by-side comparison against a
  second map variant.
- The GUI calls the exact same `lib/pipeline/` functions the scripts do, so
  results are identical either way. It deliberately does **not** do the
  scanner/Olea comparison - run `Evaluate_APTw_Results.m` for that.

Brain segmentation is now cached too (`Zeval/<subjectID>_Segmentation.mat`,
reused unless forced) - previously only the WASABI fit was, so segmentation
re-ran on every pipeline invocation even for an already-processed subject.

### Packaging as a standalone .exe

`packaging/build_standalone_exe.m` builds `APTwGUI.exe` - a standalone
Windows app that runs on a machine with **no MATLAB installed and no
MATLAB license**. The target machine only needs the free, separately
redistributable MATLAB Runtime (see the readme.txt the build produces, or
`packaging/build/APTwGUI/requiredMCRProducts.txt` for exactly which
version). Requires MATLAB Compiler (a licensed product - `license('test',
'Compiler')` - that must actually be *installed*, not just entitled; if
`mcc` is undefined, install it via your MathWorks account / the MATLAB
installer's "add products" flow for this exact release).

What makes this work, beyond just pointing the compiler at the GUI:
- **No `matlab.exe` dependency at runtime.** The GUI's background batch
  runner used to spawn `matlab.exe -batch ...` per subject - fine when
  interpreted, but there is no `matlab.exe` on the deployment target. The
  compiled exe instead relaunches **itself** with a `--worker <argsFile>`
  flag (dispatched in `APTwGUI.m`, doing the actual work in
  `lib/pipeline/run_subject_worker.m`), since that only needs the Runtime
  it already has. `APTwGUI.exe --check` runs a lightweight dependency
  check (SPM12/dcm2niix found?) without opening the GUI - useful for
  verifying a deployment.
- **SPM12 is bundled as a raw resource folder** (`-a`), not left to mcc's
  automatic dependency analysis - SPM's `matlabbatch` config system
  resolves many of its own files by name at runtime, which static analysis
  can't trace. The build script stages a Windows-only copy first (strips
  the non-Windows `.mex` binaries SPM ships, and its own dev-only `tests/`
  folder) so the package isn't carrying dead weight.
- **Bundled folders don't land at a predictable path inside the compiled
  app.** MATLAB Compiler does not place each `-a` folder at
  `<ctfroot>/<foldername>` - it mirrors a path derived from where the
  build was run from, which varies run to run. `find_bundled_resource.m`
  finds a bundled folder at runtime by searching for one of its own files
  (e.g. `spm.m`, `dcm2niix.exe`) instead of assuming a fixed layout - see
  its header for what was actually observed in a real build.

Verified end to end: a subject processed through the compiled exe (forcing
a fresh SPM segmentation and WASABI fit, not just cache reuse, and
confirming `parpool`/`parfor` genuinely works under the MATLAB Runtime)
produced bit-identical results to the interpreted pipeline.

## Output per subject (in `<subject>/Zeval/`)

From `Run_APTw_Pipeline.m`:
- `<subjectID>_APTw_results.mat` - small: the APTw map (fluid-suppressed,
  ~3.5 ppm) plus B0/B1 maps and QC info. This is what
  `Evaluate_APTw_Results.m` reads, and the file to open first.
- `<subjectID>_APTw_full_Zspectra.mat` - large: full Z-spectrum stacks at
  every processing stage, for deeper QA/reuse.
- `<subjectID>_WASABI_fit.mat` - cached WASABI B0/B1 fit (reused on
  reruns unless `cfg.force_wasabi = true`).
- `<subjectID>_Segmentation.mat` - cached SPM brain segmentation (reused
  on reruns unless `cfg.force_segmentation = true`).

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
