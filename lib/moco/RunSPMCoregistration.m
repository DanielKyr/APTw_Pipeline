function [T_RS, T_R, Tx] = RunSPMCoregistration(refImg, srcImg, spmMethod, costFunction, otherImg, sep)
% spmMethod 0/1 (coregister: estimate) call spm_coreg directly - the same
% computation spm_run_coreg does, minus the matlabbatch/spm_jobman layer,
% which adds ~1s of overhead per call and is not needed for a single
% estimate. sep (optional) overrides the sampling schedule in mm
% (default [4] for method 0, [7 4 2] for method 1).

%init output matrices
T_RS = eye(4);
T_R = spm_get_space(refImg);
Tx=zeros(1,6);

%get spm version and path
spm_Version = which('spm');
if isempty(spm_Version)
    error('SPM not found!');
end

if nargin < 3
    spmMethod = 1;
end

if nargin < 4
    costFunction = 'nmi';
end

if nargin < 5
    otherImg = {''};
end

if nargin < 6
    sep = [];
end

if spmMethod==0 || spmMethod==1
    if isempty(sep)
        if spmMethod==0, sep = 4; else, sep = [7 4 2]; end % 0: like 1 but fast
    end
    flags = struct('cost_fun', costFunction, 'sep', sep, ...
        'tol', [0.02 0.02 0.02 0.001 0.001 0.001 0.01 0.01 0.01 0.001 0.001 0.001], ...
        'fwhm', [7 7], 'graphics', 0);
    x = spm_coreg(refImg, srcImg, flags);

    % apply the estimated rigid transform to the source (and any "other")
    % image headers, exactly as spm_run_coreg does
    PO = [{srcImg}; otherImg(~cellfun(@isempty, otherImg(:)))];
    M  = spm_matrix(x);
    MM = zeros(4, 4, numel(PO));
    for j = 1:numel(PO)
        MM(:,:,j) = spm_get_space(PO{j});
    end
    for j = 1:numel(PO)
        spm_get_space(PO{j}, M\MM(:,:,j));
    end

    %transformation from source to ref
    T_RS = spm_get_space(srcImg);
end
if spmMethod==2
    % spm.spatial.realign
    matlabbatch{1}.spm.spatial.realign.estwrite.data = {
        {
        refImg
        srcImg
        }
        }';
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.quality = 0.9;
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.sep = 4;
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.fwhm = 5;
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.rtm = 0;
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.interp = 2;
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.wrap = [0 0 0];
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.weight = '';
    matlabbatch{1}.spm.spatial.realign.estwrite.roptions.which = [1 0];
    matlabbatch{1}.spm.spatial.realign.estwrite.roptions.interp = 4;
    matlabbatch{1}.spm.spatial.realign.estwrite.roptions.wrap = [0 0 0];
    matlabbatch{1}.spm.spatial.realign.estwrite.roptions.mask = 1;
    matlabbatch{1}.spm.spatial.realign.estwrite.roptions.prefix = 'r';
    spm('defaults', 'FMRI');
    spm_jobman('run', matlabbatch, cell(0,1));
    
    T_RS = spm_get_space(srcImg);
    
%     % movement params auslesen: 
%     cd 'tmp_spm'; 
%     fid = fopen('rp_mfix.txt','r'); % mit bfc
%     if fid == -1
%         fid = fopen('rp_fix.txt','r'); % ohne bfc
%     end 
%     % Skip the header lines:
%     fgetl(fid);
%     M = fgetl(fid);
%     fclose (fid);
%     Mspl=strsplit(M,' ');
%     for count2 = 1:6
%         Tx(count2)=str2num(Mspl{count2+1});
%     end
%     cd ..
end
if spmMethod==3
    % spm.spatial.realign mit high resolution
    matlabbatch{1}.spm.spatial.realign.estwrite.data = {
        {
        refImg
        srcImg
        }
        }';
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.quality = 1;
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.sep = 1;
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.fwhm = 1;
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.rtm = 0;
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.interp = 7;
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.wrap = [0 0 0];
    matlabbatch{1}.spm.spatial.realign.estwrite.eoptions.weight = '';
    matlabbatch{1}.spm.spatial.realign.estwrite.roptions.which = [1 0];
    matlabbatch{1}.spm.spatial.realign.estwrite.roptions.interp = 7;
    matlabbatch{1}.spm.spatial.realign.estwrite.roptions.wrap = [0 0 0];
    matlabbatch{1}.spm.spatial.realign.estwrite.roptions.mask = 1;
    matlabbatch{1}.spm.spatial.realign.estwrite.roptions.prefix = 'r';
    spm('defaults', 'FMRI');
    spm_jobman('run', matlabbatch, cell(0,1));
    
    T_RS = spm_get_space(srcImg);
%     
%     % movement params auslesen: 
%     cd 'tmp_spm'
%     fid = fopen('rp_mfix.txt','r'); % mit bfc
%     if fid == -1
%         fid = fopen('rp_fix.txt','r'); % ohne bfc
%     end
%     % Skip the header lines:
%     fgetl(fid);
%     M = fgetl(fid);
%     fclose (fid);
%     Mspl=strsplit(M,' ');
%     for count2 = 1:6
%         Tx(count2)=str2num(Mspl{count2+1});
%     end
%     cd ..
end