function APTwGUI(varargin)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%   APTwGUI.m
%
%   Launches the interactive GUI front-end for the APTw_Pipeline
%   (gui/APTwPipelineApp.m). Lets you add subjects, choose processing
%   options, run prepare -> pipeline -> export interactively, and browse
%   results (slice scroll, window/level, click-to-inspect Z-spectra,
%   side-by-side map comparison) without editing any script.
%
%   The GUI wraps the exact same lib/pipeline/ functions Prepare_APTw_Data.m,
%   Run_APTw_Pipeline.m and Evaluate_APTw_Results.m use, so results are
%   identical either way. It does NOT do the scanner/Olea comparison -
%   run Evaluate_APTw_Results.m separately for that.
%
%   THIS IS ALSO THE MATLAB COMPILER ENTRY POINT for the standalone .exe
%   build (see packaging/build_standalone_exe.m). A function (not a
%   script) so it can receive command-line arguments:
%     (no args)              opens the GUI - the normal case.
%     --worker <argsFile>     processes one subject in the background, no
%                              GUI. The GUI's own batch runner relaunches
%                              THIS SAME exe with this flag to do the
%                              actual pipeline work: a compiled exe has no
%                              matlab.exe available to spawn on a machine
%                              with no MATLAB installed, so it has to be
%                              able to invoke itself instead. See
%                              gui/APTwPipelineApp.m's launchSubjectProcess.
%     --check                 prints whether SPM12 and dcm2niix.exe were
%                              found, then exits without opening the GUI -
%                              useful for verifying a deployed install
%                              without needing a display.
%
%   In deployed (isdeployed) mode, gui/ and lib/ do NOT need addpath - mcc's
%   static dependency analysis already compiles every function this code
%   actually calls directly into the exe. SPM12 is the one exception: its
%   matlabbatch config system resolves many of its own files by name at
%   runtime, which static analysis can't trace, so it's bundled as a raw
%   resource folder (-a) instead and genuinely needs a runtime addpath -
%   found via find_bundled_resource since MATLAB Compiler does not put -a
%   folders at a fixed, predictable path inside the CTF archive (see that
%   function's header for what was actually observed).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if isdeployed
    projectRoot = ctfroot();
    if isempty(which('spm'))
        spmRoot = find_bundled_resource(projectRoot, 'spm.m');
        if ~isempty(spmRoot)
            addpath(spmRoot);
        end
    end
else
    projectRoot = fileparts(mfilename('fullpath'));
    addpath(fullfile(projectRoot, 'gui'));
    addpath(genpath(fullfile(projectRoot, 'lib')));
end

if ~isempty(varargin) && ischar(varargin{1}) && strcmpi(varargin{1}, '--worker')
    if numel(varargin) < 2
        error('APTwGUI:missingArgsFile', '--worker requires an argsFile path argument.');
    end
    run_subject_worker(varargin{2});
elseif ~isempty(varargin) && ischar(varargin{1}) && strcmpi(varargin{1}, '--check')
    print_dependency_check(projectRoot);
else
    app = APTwPipelineApp(); %#ok<NASGU>
end
end


function print_dependency_check(projectRoot)
fprintf('APTwGUI dependency check\n');
fprintf('-------------------------\n');
spmPath = which('spm');
if isempty(spmPath)
    fprintf('SPM12:       NOT FOUND\n');
else
    fprintf('SPM12:       OK (%s)\n', spmPath);
end

if isdeployed
    dcm2niixFolder = find_bundled_resource(projectRoot, 'dcm2niix.exe');
    if isempty(dcm2niixFolder)
        dcm2niixPath = '';
    else
        dcm2niixPath = fullfile(dcm2niixFolder, 'dcm2niix.exe');
    end
else
    dcm2niixPath = fullfile(projectRoot, 'bin', 'dcm2niix.exe');
    if ~isfile(dcm2niixPath), dcm2niixPath = ''; end
end
if isempty(dcm2niixPath)
    fprintf('dcm2niix.exe: NOT FOUND\n');
else
    fprintf('dcm2niix.exe: OK (%s)\n', dcm2niixPath);
end
end
