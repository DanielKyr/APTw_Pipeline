function run_subject_worker(argsFile)
% RUN_SUBJECT_WORKER  Runs prepare -> pipeline -> export for ONE subject, given
% a .mat file (argsFile) with fields: subjPath, cfg, binFolder, pidFile,
% logFile, doneFile. Writes its own PID to pidFile immediately (so a caller
% can kill it), diary-captures everything to logFile, and always writes
% 'OK' or 'FAILED: <message>' to doneFile when finished.
%
% This is the single background-work entry point used by
% gui/APTwPipelineApp.m's batch runner, in BOTH of the two ways it can be
% launched:
%   - interpreted/dev mode: as a plain function call via a detached
%     "matlab -batch" process (matlab.exe is available and licensed there)
%   - compiled standalone .exe mode (no MATLAB installed on the target
%     machine): the compiled app relaunches ITSELF with a "--worker" flag
%     (see APTwGUI.m), which dispatches here instead of opening the GUI -
%     no separate matlab.exe invocation is needed or possible.
%
% Keeping this as one real, pre-compiled function (rather than writing out a
% throwaway .m script and calling run() on it, which is not a reliable
% pattern once code is AOT-compiled by MATLAB Compiler) is what makes the
% GUI's background execution model work identically in both modes.

d = load(argsFile);

try
    pid = matlabProcessID; % R2023a+; feature('getpid') is deprecated and not recommended
catch
    pid = feature('getpid'); %#ok<FEATGPID> fallback for older MATLAB releases
end
fid = fopen(d.pidFile, 'w');
fprintf(fid, '%d', pid);
fclose(fid);

diary(d.logFile);
diary('on');
try
    fprintf('__STAGE__:PREPARE_START\n');
    prepare_one_subject(d.subjPath, d.cfg, d.binFolder);
    fprintf('__STAGE__:PREPARE_DONE\n');

    run_APTw_subject(d.subjPath, d.cfg); % emits its own SEGMENT/WASABI/PROCESS markers (cfg.emit_stage_markers)

    fprintf('__STAGE__:EXPORT_START\n');
    evaluate_subject_own_maps(d.subjPath, d.cfg);
    fprintf('__STAGE__:EXPORT_DONE\n');

    diary('off');
    fid2 = fopen(d.doneFile, 'w');
    fprintf(fid2, 'OK');
    fclose(fid2);
catch ME
    diary('off');
    fid2 = fopen(d.doneFile, 'w');
    fprintf(fid2, 'FAILED: %s', strrep(ME.message, newline, ' | '));
    fclose(fid2);
end
end
