function [Z_stack_corr] = Z_B1_correction(Z_stack,rel_B1map,B1_input,B1_output,Segment,fit_type,B1_input_index)
% Z_B1_CORRECTION performs B1 correction on a stack of Z-spectra.
%
% This function corrects B1 inhomogeneities for a given Z-spectrum stack using the provided relative B1 map,
% specified B1 input values, and output B1 target values. It can handle both 2D and 3D Z-spectra and uses 
% fitting or interpolation to adjust for B1 variations across the dataset.
%
% INPUTS:
%   Z_stack       - A 5D array representing the Z-spectra (y, x, z, offset, B1).
%   rel_B1map     - A relative B1 map, which is used to scale the input B1 values.
%   B1_input      - A vector of B1 values used in the original acquisition.
%   B1_output     - A scalar or vector specifying the target B1 values for correction.
%   Segment       - A binary voxel/pixel mask used to specify which voxels are corrected (default: all voxels).
%   fit_type      - The type of fit or interpolation to use for B1 correction. Options include:
%                   'smoothingspline', 'poly2', 'poly3', 'poly4', 'poly5', 'spline', 'linear' (default: 'smoothingspline').
%   B1_input_index - Index vector specifying which B1 samples should be used for correction (default: all).
%
% OUTPUT:
%   Z_stack_corr  - A 5D array representing the B1-corrected Z-spectra stack.
%
% This function supports both parallel and serial computation for faster processing of the Z-spectrum data,
% particularly when working with larger 3D datasets. If parallel processing is available, it divides the workload
% across available CPU cores.
%
% NOTES:
% - The function can handle both 2D and 3D CEST data, applying B1 correction accordingly.
% - The correction uses various fitting methods to model and correct B1 effects, including smoothing splines,
%   polynomial fits, and linear or spline interpolation.
% - If the relative B1 map exceeds certain thresholds, it is clamped to prevent unrealistic values (rel_B1map >= 3 set to 3,
%   rel_B1map <= 0 set to 0.01).
%
% REFERENCES:
%   Windschuh, J., et al. (2015). Correction of B1-inhomogeneities for relaxation-compensated CEST imaging at 7T.
%   NMR Biomed, 28: 529-537. doi: 10.1002/nbm.3283.
%
%   Zaiss, M., et al. (2015). Relaxation-compensated CEST-MRI of the human brain at 7T.
%   Neuroimage, 112: 180-188. doi: 10.1016/j.neuroimage.2015.02.040.

par_flag = 1;

mysize=size(Z_stack);
if mysize(3) == 1
    par_flag = 0;
end
    par_flag = 1;
    
if nargin<7
    B1_input_index=[1:numel(B1_input)];
end

if nargin<6
    fit_type='smoothingspline';
end

if nargin<5
    Segment=ones(mysize(1),mysize(2),mysize(3));
end

if nargin<4
    B1_output=mean(B1_input);
end

% Define absolute B1map
rel_B1map(rel_B1map>=3)=3;
rel_B1map(rel_B1map<=0)=0.01;

abs_B1map=ones(mysize(1),mysize(2),mysize(3),numel(B1_input));

if mysize(3)==1 % CEST is 2D
    for ii=1:numel(B1_input)
        abs_B1map(:,:,1,ii)= abs_B1map(:,:,1,ii).*B1_input(ii);
        abs_B1map(:,:,1,ii)=abs_B1map(:,:,1,ii).*rel_B1map;
    end
else % CEST is 3D
    if ndims(rel_B1map)==3
        for jj=1:mysize(3)
            for ii=1:numel(B1_input)
                abs_B1map(:,:,jj,ii)= abs_B1map(:,:,jj,ii)*B1_input(ii);
                abs_B1map(:,:,jj,ii)=abs_B1map(:,:,jj,ii).*rel_B1map(:,:,jj);
            end
        end
    else
        sprintf('careful B1map is only 2D');
        for jj=1:mysize(3)
            for ii=1:numel(B1_input)
                abs_B1map(:,:,jj,ii)= abs_B1map(:,:,jj,ii)*B1_input(ii);
                abs_B1map(:,:,jj,ii)=abs_B1map(:,:,jj,ii).*rel_B1map(:,:);
            end
        end
        
    end
    % add 3rd dimension to Segment if necessary
    if ismatrix(Segment)
        sprintf('careful Segment is only 2D!');
        for jj=1:mysize(3)
            Segment(:,:,jj)=Segment(:,:,1);
        end
    end
    
end


try 
    license('test','Distrib_Computing_Toolbox')
    Composite();
catch
    par_flag=0;
end

% parallel
if (par_flag)
    
    % DEFINE COMPOSITS
    Segment_c = Composite();
    abs_B1map_c = Composite();
    Z_stack_corr_c = Composite();
    Z_stack_c = Composite();
    % wieviele matlabpools
    npools=size(Z_stack_corr_c,2); % second dimension if composite is always number of CPUs
    np=mysize(3)/npools;
    % teilintervalle
    IV = @(i) 1+fix(np*(i-1)):fix(np*(i)); %InterVals
    
    for ii = 1:npools
        Segment_c{ii}=Segment(:,:,IV(ii));
        abs_B1map_c{ii}=abs_B1map(:,:,IV(ii),:);
        Z_stack_c{ii}=Z_stack(:,:,IV(ii),:,:);
        Z_stack_corr_c{ii}=NaN(mysize(1),mysize(2),numel(IV(ii)),mysize(4),numel(B1_output));
        
    end
    
    spmd
        
        %Choose fit/interpolation type
        if (strcmp(fit_type,'smoothingspline'))
            fo_ = fitoptions('method','SmoothingSpline','SmoothingParam',0.998);
            ft_ = fittype('SmoothingSpline');
        elseif(strcmp(fit_type,'poly2'))
            ft_ = fittype(fit_type);
            fo_ = fitoptions(ft_);
        elseif(strcmp(fit_type,'poly3'))
            ft_ = fittype(fit_type);
            fo_ = fitoptions(ft_);
        elseif(strcmp(fit_type,'poly4'))
            ft_ = fittype(fit_type);
            fo_ = fitoptions(ft_);
        elseif(strcmp(fit_type,'poly5'))
            ft_ = fittype(fit_type);
            fo_ = fitoptions(ft_);
        elseif(strcmp(fit_type,'spline'))
            inter_method=fit_type;
        elseif(strcmp(fit_type,'linear'))
            inter_method=fit_type;
        end
        
        for ll = 1:numel(IV(labindex))  %slice
            for ii = 1:mysize(1) %y
                for jj = 1:mysize(2) %x
                    for kk = 1:mysize(4) % Offset
                        
                        Ztemp = squeeze(Z_stack_c(ii,jj,ll,kk,B1_input_index));
                        
                        if(Segment_c(ii,jj,ll)==1 && max(isinf(Ztemp))==0 && max(isnan(abs_B1map_c(ii,jj,ll,:)))==0 ) ...
                                && numel(~isnan(Ztemp)>=3 ) % three points are at least available!
                            
                            B1_idx = B1_input_index(~isnan(Ztemp)); % all NaNs within the Ztemp vector are not used
                            Ztemp = Ztemp(~isnan(Ztemp));
                            
                            if (strcmp(fit_type,'linear') || strcmp(fit_type,'spline'))
                                Z_stack_corr_c(ii,jj,ll,kk,:) = interp1(squeeze(abs_B1map_c(ii,jj,ll,B1_input_index(B1_idx))),Ztemp,B1_output,inter_method,'extrap');
                            else
                                cf_ = fit(squeeze(abs_B1map_c(ii,jj,ll,B1_input_index(B1_idx))),Ztemp,ft_,fo_);
                                Z_stack_corr_c(ii,jj,ll,kk,:)=cf_(B1_output);
                            end
                            
                        else
                            Z_stack_corr_c(ii,jj,ll,kk,:)  = NaN(numel(B1_output),1);
                        end
                    end
                    
                end
            end
        end
          
        
    end
    
    % reallocate labs to local
    Z_stack_corr=cat(3,Z_stack_corr_c{:});
    
elseif par_flag == 0 % not parallel
    disp('parallel computation not activated')
    
    %Choose fit/interpolation type
    if (strcmp(fit_type,'smoothingspline'))
        fo_ = fitoptions('method','SmoothingSpline','SmoothingParam',0.998);
        ft_ = fittype('SmoothingSpline');
    elseif(strcmp(fit_type,'poly2'))
        ft_ = fittype(fit_type);
        fo_ = fitoptions(ft_);
    elseif(strcmp(fit_type,'poly3'))
        ft_ = fittype(fit_type);
        fo_ = fitoptions(ft_);
    elseif(strcmp(fit_type,'poly4'))
        ft_ = fittype(fit_type);
        fo_ = fitoptions(ft_);
    elseif(strcmp(fit_type,'poly5'))
        ft_ = fittype(fit_type);
        fo_ = fitoptions(ft_);
    elseif(strcmp(fit_type,'spline'))
        inter_method=fit_type;
    elseif(strcmp(fit_type,'linear'))
        inter_method=fit_type;
    end
    
    Z_stack_corr=NaN(mysize(1),mysize(2),mysize(3),mysize(4),numel(B1_output));
    
    for ll = 1:mysize(3) %slice
        for ii = 1:mysize(1) % y
            for jj = 1:mysize(2) %x
                for kk = 1:mysize(4) % Offsets
                    
                    Ztemp=squeeze(Z_stack(ii,jj,ll,kk,B1_input_index));
                    
                    if(Segment(ii,jj,ll)==1 && max(isinf(Ztemp))==0 && max(isnan(abs_B1map(ii,jj,ll,:)))==0 ) ...
                            && numel(~isnan(Ztemp)>=3 ) % three points are at least available!
                        
                        B1_idx = B1_input_index(~isnan(Ztemp)); % all NaNs within the Ztemp vector are not used
                        Ztemp=Ztemp(~isnan(Ztemp));
                        
                        if (strcmp(fit_type,'linear') || strcmp(fit_type,'spline'))
                           %[ii,jj,ll,kk]
                           Z_stack_corr(ii,jj,ll,kk,:) = interp1(squeeze(abs_B1map(ii,jj,ll,B1_input_index(B1_idx))),Ztemp,B1_output,inter_method,'extrap');
                        else
                            cf_ = fit(squeeze(abs_B1map(ii,jj,ll,B1_input_index(B1_idx))),Ztemp,ft_,fo_);
                            Z_stack_corr(ii,jj,ll,kk,:)=cf_(B1_output);
                        end
                    else
                        Z_stack_corr(ii,jj,ll,kk,:)  = NaN(numel(B1_output),1);
                    end
                    
                end
                
            end
        end
    end
    'B1 correction done'
end %if parallel