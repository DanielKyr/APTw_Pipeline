function cmap = bluewhitered(w)
% BLUEWHITERED  Blue-white-red diverging colormap with white anchored at value 0.
% w = [lo hi] is the caxis window this colormap will be applied to; the
% blue/red split is proportioned so 0 lands on white even when the window
% isn't symmetric (e.g. APTw's 2-98% range, which skews positive). With no
% argument, behaves like the old always-symmetric version.
if nargin < 1 || isempty(w), w = [-1 1]; end
n = 256;
lo = w(1); hi = w(2);
if hi <= lo, hi = lo + eps; end
if lo >= 0
    frac = 0;   % window is all non-negative -> white-to-red only
elseif hi <= 0
    frac = 1;   % window is all non-positive -> blue-to-white only
else
    frac = -lo / (hi - lo); % fraction of the window below zero
end
nBlue = min(n-1, max(1, round(frac*n)));
nRed  = n - nBlue;
up1 = linspace(0, 1, nBlue)'; blueSide = [up1 up1 ones(nBlue,1)];         % blue -> white
up2 = linspace(1, 0, nRed)';  redSide  = [ones(nRed,1) up2 up2];          % white -> red
cmap = [blueSide; redSide];
end
