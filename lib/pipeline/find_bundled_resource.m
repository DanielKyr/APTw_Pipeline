function resourceFolder = find_bundled_resource(searchRoot, markerFile)
% FIND_BUNDLED_RESOURCE  Locates a resource folder bundled into a MATLAB
% Compiler standalone exe via mcc's -a flag, by searching for a known
% marker file (e.g. 'spm.m', 'dcm2niix.exe') under searchRoot (normally
% ctfroot()).
%
% MATLAB Compiler does NOT place each -a folder at a fixed, predictable
% path inside the CTF archive - it mirrors a path derived from where the
% folder sat relative to the build's working directory, which changes
% depending on how/where the build was run (confirmed by inspecting
% packaging/build/APTwGU*/.META/manifest.xml after a real build: a folder
% added as -a "..\packaging\build\spm_staged" landed at
% "<ctfroot>/APTwGUI/build/spm_staged", not "<ctfroot>/spm_staged" or
% anything else guessable in advance). Searching for a marker file is the
% robust way to find a bundled resource at runtime instead of hard-coding
% an assumed layout that a different build run could silently break.
%
% Returns '' if not found (e.g. running interpreted, where callers should
% use their own known project-relative path instead of this function).
d = dir(fullfile(searchRoot, '**', markerFile));
if isempty(d)
    resourceFolder = '';
else
    resourceFolder = d(1).folder;
end
end
