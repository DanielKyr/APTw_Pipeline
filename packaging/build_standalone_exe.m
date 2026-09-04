%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%   build_standalone_exe.m
%
%   Builds APTwGUI.exe - a standalone Windows application meant to run on a
%   machine with NO MATLAB installed and NO MATLAB license. The target
%   machine only needs the free, separately-redistributable MATLAB Runtime
%   (see "AFTER THE BUILD" below) - that's what MATLAB Compiler is for.
%
%   Requires, on THIS (build) machine: a licensed MATLAB Compiler, and
%   every toolbox the pipeline itself needs (see README.md's
%   Prerequisites - Statistics and Machine Learning, Curve Fitting, Image
%   Processing; Parallel Computing and Optimization if present/used).
%
%   WHAT THIS DOES
%   -----------------------------------------------------------------
%   1. Stages a Windows-only copy of the SPM12 install found via
%      which('spm') into packaging/build/spm_staged/, stripping the
%      non-Windows MEX binaries SPM ships for Linux/Mac
%      (.mexa64/.mexmaci64/.mexmaca64) - dead weight for a Windows-only
%      package, and roughly halves its size. Does NOT touch the real SPM
%      install.
%   2. Runs mcc to compile APTwGUI.m (the dual GUI/background-worker entry
%      point - see its own header comment) into a standalone .exe,
%      bundling gui/, lib/, bin/ (dcm2niix.exe) and the staged SPM12 copy
%      as resource folders (-a). Bundling SPM as a resource folder, not
%      just relying on mcc's automatic dependency analysis, matters
%      because SPM's matlabbatch config system resolves many of its own
%      functions by name at runtime rather than by direct call, which
%      static analysis can't trace - -a on a folder includes everything
%      in it regardless.
%
%   AFTER THE BUILD - see packaging/build/APTwGUI/:
%     for_testing/               the raw .exe + support files. Fastest to
%                                 test with on a machine that already has
%                                 a compatible MATLAB Runtime OR MATLAB
%                                 itself installed.
%     for_redistribution/        a single installer exe to hand to a user
%                                 with a genuinely clean machine - it
%                                 installs the free MATLAB Runtime (no
%                                 license needed) if not already present,
%                                 then the app.
%     for_redistribution_files_only/   raw files, if you want to build
%                                 your own installer/deployment instead.
%   requiredMCRProducts.txt (inside for_testing/) lists exactly which
%   MATLAB Runtime component version the target machine needs.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

packagingDir = fileparts(mfilename('fullpath'));
projectRoot  = fileparts(packagingDir);

SPM_SOURCE = fileparts(which('spm'));
if isempty(SPM_SOURCE)
    error('SPM12 not found on the MATLAB path - addpath it before running this build script.');
end

buildDir  = fullfile(packagingDir, 'build');
spmStaged = fullfile(buildDir, 'spm_staged');

%% ---- 1. Stage a Windows-only copy of SPM12 ----
if isfolder(spmStaged)
    fprintf('Removing previous staged SPM copy: %s\n', spmStaged);
    rmdir(spmStaged, 's');
end
if ~isfolder(buildDir), mkdir(buildDir); end
fprintf('Staging a Windows-only SPM12 copy from %s ...\n', SPM_SOURCE);
mkdir(spmStaged);
copyfile(SPM_SOURCE, spmStaged);
foreignMex = [dir(fullfile(spmStaged, '**', '*.mexa64')); dir(fullfile(spmStaged, '**', '*.mexmaci64')); ...
              dir(fullfile(spmStaged, '**', '*.mexmaca64'))];
for k = 1:numel(foreignMex)
    delete(fullfile(foreignMex(k).folder, foreignMex(k).name));
end
fprintf('Removed %d non-Windows MEX file(s) (kept .mexw64).\n', numel(foreignMex));

% SPM's own test suite - never called by anything this pipeline uses, and
% the one source of mcc's "unresolved symbol" warning (test_checkcode.m
% calls analyzeCodeCompatibility, which isn't supported in deployed code).
testsDir = fullfile(spmStaged, 'tests');
if isfolder(testsDir)
    rmdir(testsDir, 's');
    fprintf('Removed SPM''s tests/ folder (dev-only, not used at runtime).\n');
end

%% ---- 2. Make sure everything mcc needs to trace is actually on the path ----
% (belt-and-suspenders alongside the -a folder bundling below: this lets
% mcc's static dependency analysis resolve APTwPipelineApp/prepare_one_subject/
% etc. the same way the interpreted app does, via addpath, rather than relying
% on -a alone to make them discoverable at compile time.)
addpath(fullfile(projectRoot, 'gui'));
addpath(genpath(fullfile(projectRoot, 'lib')));

%% ---- 3. Compile ----
appOutDir = fullfile(buildDir, 'APTwGUI');
if isfolder(appOutDir)
    fprintf('Removing previous build output: %s\n', appOutDir);
    rmdir(appOutDir, 's');
end
fprintf('Running mcc (this can take several minutes, especially the first time)...\n');
mcc('-m', fullfile(projectRoot, 'APTwGUI.m'), ...
    '-d', buildDir, ...
    '-o', 'APTwGUI', ...
    '-a', fullfile(projectRoot, 'gui'), ...
    '-a', fullfile(projectRoot, 'lib'), ...
    '-a', fullfile(projectRoot, 'bin'), ...
    '-a', spmStaged);

fprintf('\nBuild finished. Output: %s\n', buildDir);
