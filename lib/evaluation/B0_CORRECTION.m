function [Mz_b0corr] = B0_CORRECTION(Mz_stack,dB0_stack,P,Segment)
% B0_CORRECTION applies B0 correction to the input Z-spectrum.
%
% This function takes an input stack of Z-spectra and corrects it for B0 field inhomogeneities 
% based on the provided field map. The correction can be performed using different interpolation methods 
% as specified by the user.
%
% INPUTS:
%   Mz_stack   - A 4D matrix (x, y, slice, offset) representing the Z-spectra for all voxels.
%   dB0_stack  - A 3D or 4D matrix containing the B0 inhomogeneity field map (ppm). If 4D, the correction is done for each offset individually.
%   P          - A structure containing parameters related to the evaluation, such as interpolation method and 
%                offsets (P.EVAL and P.SEQ fields).
%   Segment    - A 2D or 3D binary mask specifying which voxels are to be corrected (1 indicates voxel to correct).
%                It can be a 3D mask if different slices require unique segments.
%
% OUTPUTS:
%   Mz_b0corr  - A 4D matrix containing B0 corrected Z-spectra for the specified voxels.
%
% The function allows the user to select the interpolation method for the B0 correction if it is not already specified
% in P.EVAL.B0_int_meth. If the field map (dB0_stack) is 4D, the function handles the correction as an individual 
% adjustment, meaning different corecting shifts are applied for different offsets.
%
% The function works with the help of the `B0_CORRECTION_1D` subroutine that processes the correction for each voxel.

if ~isfield(P.EVAL,'B0_int_meth')
    interplist = {'linspline','linear','spline','cubic','pchip'};
    [indx,tf] = listdlg('PromptString','Select B0 Interp:',...
        'SelectionMode','single',...
        'ListString',interplist,...
        'InitialValue',[2]);
    P.EVAL.B0_int_meth = interplist{indx};
end

tic
sizes=size(Mz_stack);

if isfield(P.EVAL,'w_interp')
    Mz_b0corr=zeros(sizes(1),sizes(2),sizes(3),numel(P.EVAL.w_interp)); % this now also works for interpolated data
else
    Mz_b0corr=zeros(sizes(1),sizes(2),sizes(3),sizes(4));
end

[P]=change_w_fit(P);

%% this means we have a online_dB0 correction
online_dB0 = (ndims(dB0_stack)==4) ;

if ismatrix(Segment)
    for ii=1:sizes(3)
        Segment(:,:,ii)=Segment(:,:,1);
    end
end

flag_nonUnique = 0; % see modifications in B0_CORRECTION_1D.m ; Sebastian

    Mz_perm= permute(Mz_stack,[4, 1,2,3]);
    dB0_vec=permute(dB0_stack,[4, 1,2,3]);
    Mz_b0corr_vec =permute(Mz_b0corr,[4, 1,2,3]);
    
    Mz_vec=Mz_perm(:,Segment==1);
    dB0_vec=dB0_vec(:,Segment==1);
    Mz_b0corr_vec=Mz_b0corr_vec(:,Segment==1); % init to zeroes
    
    for ii=1:size(Mz_vec,2)
        tmpzspec=squeeze(Mz_vec(:,ii));
        
        if online_dB0
            %% we can overwrite P.SEQ.w here locally with the actual offsets, given by dB0stack_4D
            PP=P;
            if ~isnan(squeeze(dB0_vec(1:end,ii)))
                PP.SEQ.w = P.SEQ.w-squeeze(dB0_vec(1:end,ii));
            end
            % at the same time we set the second argumnet, which
            % would be the constant shift to 0
            
            [Mz_b0corr_vec(:,ii)]=B0_CORRECTION_1D(tmpzspec,0,PP);
            
            % this should do the job
        else
            if ~isnan(squeeze(dB0_vec(1:end,ii)))
                [Mz_b0corr_vec(:,ii)]=B0_CORRECTION_1D(tmpzspec,dB0_vec(1:end,ii),P);
            end;
        end;
        
    end;
    Mz_b0corr=permute(Mz_b0corr,[4, 1,2,3]);
    Mz_b0corr(:,Segment==1)= Mz_b0corr_vec;
    Mz_b0corr=permute(Mz_b0corr,[2,3,4,1]);
    
toc