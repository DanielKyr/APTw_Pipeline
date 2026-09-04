function w = pctwin(v)
% PCTWIN  Robust 2-98 percentile display window (no toolbox needed).
s = sort(v(:)); s = s(~isnan(s)); n = numel(s);
if n < 2, w = [0 1]; return; end
w = [s(max(1, round(0.02*n)))  s(min(n, round(0.98*n)))];
if w(2) <= w(1), w(2) = w(1) + eps; end
end
