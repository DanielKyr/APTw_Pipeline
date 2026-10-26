function tf = nii_on_same_grid(fileA, fileB)
% NII_ON_SAME_GRID  True if two NIfTI files share the same voxel grid: same
% matrix size and the same voxel-to-world matrix (to 1e-3 mm, i.e. ignoring
% float noise between headers). The pipeline indexes voxel arrays directly,
% so data from two files can only be combined voxel-for-voxel when this holds
% - e.g. the motion-corrected APTw stack and the WASABI B0/B1 maps.
Va = spm_vol(fileA); Vb = spm_vol(fileB);
tf = isequal(Va(1).dim, Vb(1).dim) && max(abs(Va(1).mat(:) - Vb(1).mat(:))) < 1e-3;
end
