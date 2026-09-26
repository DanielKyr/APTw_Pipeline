function ok = aptw_ensure_pool()
% APTW_ENSURE_POOL  Makes sure a parallel pool of the configured size is
% running, and returns true if the caller should go parallel.
%
% Returns false (caller should run serially) when parallel processing is
% switched off (aptw_parallel_enabled / cfg.use_parallel) or a pool can't be
% started (no Parallel Computing Toolbox, license, etc.).
%
% Pool size: cfg.max_workers (via aptw_parallel_enabled), capped at the local
% "Processes" profile's limit, which defaults to the number of physical
% cores; 0 = auto = that limit. An already-running pool of a different size
% is restarted so the cap actually takes effect. Called right before each
% parallel step, so a pool is only ever started when one is really used.
[enabled, maxWorkers] = aptw_parallel_enabled();
ok = false;
if ~enabled, return; end
try
    cluster = parcluster('Processes');
    target = cluster.NumWorkers;
    if maxWorkers > 0
        target = min(maxWorkers, target);
    end
    pool = gcp('nocreate');
    if ~isempty(pool) && pool.NumWorkers ~= target
        fprintf('Restarting parallel pool: %d -> %d workers (cfg.max_workers)\n', pool.NumWorkers, target);
        delete(pool);
        pool = [];
    end
    if isempty(pool)
        parpool(cluster, target);
    end
    ok = true;
catch ME
    fprintf('Parallel pool unavailable (%s) - running serially.\n', ME.message);
end
end
