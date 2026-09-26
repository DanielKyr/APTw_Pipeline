function [tf, maxWorkers] = aptw_parallel_enabled(newValue, newMaxWorkers)
% APTW_PARALLEL_ENABLED  Global on/off switch (and pool-size cap) for every
% parallel-pool step in the pipeline (MOCO coregistration, WASABI fit,
% spline B0 correction, B1 correction).
%
%   aptw_parallel_enabled(false)       turn parallel processing off (serial everywhere)
%   aptw_parallel_enabled(true, n)     turn it on, with at most n pool workers
%                                      (n = 0: auto, one per physical core)
%   [tf, n] = aptw_parallel_enabled()  query the current settings
%
% prepare_one_subject and run_APTw_subject set this from cfg.use_parallel /
% cfg.max_workers, so callers normally just set those cfg fields. It is a
% process-wide setting (not threaded through every low-level function's
% arguments) because the library functions that go parallel don't receive
% cfg. The pool itself is started lazily, by aptw_ensure_pool, the first time
% a step actually needs it.
persistent enabled maxW
if isempty(enabled), enabled = true; maxW = 0; end
if nargin > 0, enabled = logical(newValue); end
if nargin > 1, maxW = max(0, round(newMaxWorkers)); end
tf = enabled;
maxWorkers = maxW;
end
