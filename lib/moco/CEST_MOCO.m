function varargout = CEST_MOCO(fix_name, mov_name, fix_index, mov_index, method, bfc, interp_trafo_index ,pure_interpolate, UseOnlyGM, coregSep)
% call by e.g.
%  CEST_MOCO('WASABI.nii','NOE.nii',[1],[],'matlab_edge')
% CEST_MOCO('MIMOSA_MPI3M0_720nT_VS_20191125092128_10.nii','MIMOSA_MPI3M0_720nT_20191125092128_8.nii',[2],[],'spm','bfc')
% CEST_MOCO('MIMOSA_MPI3M0_720nT_VS_20191125092128_10.nii','MIMOSA_MPI3M0_1000nT_20191125092128_9.nii',[2],[],'spm','bfc')
varargout = cell(1);

runBFC = false;
if nargin > 5
    if strcmp(bfc, 'bfc')
        runBFC = true;
    end
end
if nargin < 7
    interp_trafo_index = [];
end
if nargin < 8
    pure_interpolate=0;
end

if nargin < 9
    UseOnlyGM = 0;
end

if nargin < 10
    coregSep = []; % spm methods only: SPM coregistration sampling schedule, [] = default
end

% get path of mov image for storage
[filepath,name,~] = fileparts(mov_name); if isempty(filepath) filepath='.'; end;
[filepath,fname,~] = fileparts(fix_name); if isempty(filepath) filepath='.'; end;
fname=fname(1:8);
if UseOnlyGM
    useGM = '_GM';
else
    useGM='';
end

if isempty(mov_index)
    if nargin > 6
        if(pure_interpolate)
            new_name=['interpolated_' name '_REG_' fname '[' mat2str(fix_index) ']' '[' 'all' ']' method bfc useGM '.nii'];
        else
            new_name=[name '_REG_' fname '[' mat2str(fix_index) ']' '[' 'all' ']' method bfc mat2str(interp_trafo_index) useGM '.nii'];
        end
    elseif nargin > 5
        new_name=[name '_REG_' fname '[' mat2str(fix_index) ']' '[' 'all' ']' method bfc useGM '.nii'];
    else
        new_name=[name '_REG_' fname '[' mat2str(fix_index) ']' '[' 'all' ']' method useGM '.nii'];
    end
else
    if nargin > 6
        if(pure_interpolate)
            new_name=['interpolated_' name '_REG_' fname '[' mat2str(fix_index) ']' '[' mat2str(mov_index) ']' method bfc useGM '.nii'];
        else
            new_name=[name '_REG_' fname '[' mat2str(fix_index) ']' '[' mat2str(mov_index) ']' method bfc mat2str(interp_trafo_index) useGM '.nii'];
        end
    elseif nargin > 5
        new_name=[name '_REG_' fname '[' mat2str(fix_index) ']' '[' mat2str(mov_index) ']' method bfc useGM '.nii'];
    else
        new_name=[name '_REG_' fname '[' mat2str(fix_index) ']' '[' mat2str(mov_index) ']' method useGM '.nii'];
    end
end
varargout{1}=new_name;
% call different subfunctions for fixedVolume adn movingVolume(4D)
switch method
    case 'matlab'
        
        CEST_MOCO_matlab(fix_name, mov_name,new_name,fix_index, mov_index,0);
        
    case 'matlab_edge'
        
        CEST_MOCO_matlab(fix_name, mov_name,new_name,fix_index, mov_index,1);
        
    case 'elastix'
        % elastix needs the niftis
	if(pure_interpolate)
	    CEST_MOCO_elastix_interpolate(fix_name,mov_name,new_name,fix_index,mov_index,offset_skip, 0, false, runBFC);
	else
	    CEST_MOCO_elastix(fix_name, mov_name,new_name,fix_index, mov_index,0,false,runBFC,interp_trafo_index);
    end
    
    case 'elastix_nonrigid'
        % elastix needs the niftis	
	    CEST_MOCO_elastix_nonrigid(fix_name, mov_name,new_name,fix_index, mov_index,0,false,runBFC,interp_trafo_index);
	    
     case 'elastix_translation'
        % elastix needs the niftis	
	    CEST_MOCO_elastix_translation(fix_name, mov_name,new_name,fix_index, mov_index,0,false,runBFC,interp_trafo_index);
	             
     case 'elastix_euler'
        % elastix needs the niftis	
	    CEST_MOCO_elastix_euler(fix_name, mov_name,new_name,fix_index, mov_index,0,false,runBFC,interp_trafo_index);
	             
    case 'elastixMasked'
        % elastix needs the niftis
        CEST_MOCO_elastix(fix_name, mov_name,new_name,fix_index, mov_index,1,false,runBFC,interp_trafo_index);
        
    case 'afni'
        
        CEST_MOCO_afni(fix_name, mov_name,new_name,fix_index, mov_index);
        
    case 'spm'

        CEST_MOCO_spm(fix_name, mov_name,new_name,fix_index, mov_index,runBFC, interp_trafo_index, 1, UseOnlyGM, coregSep);
        
    case 'spm_realign'

        CEST_MOCO_spm(fix_name, mov_name,new_name,fix_index, mov_index,runBFC, interp_trafo_index, 2, UseOnlyGM); 
   
    case 'spm_realign_highres'

        CEST_MOCO_spm(fix_name, mov_name,new_name,fix_index, mov_index,runBFC, interp_trafo_index, 3, UseOnlyGM); 
        
    case 'LRAZ_SPM'
        CEST_MOCO_LRAZ(fix_name, mov_name,new_name,fix_index, mov_index,'LRAZ_SPM'); 
        
end

end
