function [moved, txMats]= CEST_MOCO_spm(fix_name, mov_name,new_name,fix_index, mov_index, runBFC, interp_trafo_index,spmMethod, UseOnlyGM)

moved = [];
if nargin < 6
    runBFC = false;
end
if nargin < 7
    interp_trafo_index = [];
end
if nargin < 8
    spmMethod = 1;
end
if nargin < 9
    UseOnlyGM = 0;
end


%get info from input files
[fpM, mov_file_name, ~] = fileparts(mov_name);

%run in current folder if no filepath is specified
if(isempty(fpM))
    fpM = pwd;
    disp(['Writing results to: ' fpM ]);
end

%temp folder for intermediate 3d outputs
tmpFolder = [fpM '/tmp_spm'];
if ~exist(tmpFolder, 'dir')
   mkdir(tmpFolder);
end
%MF fix for parallel computing
% tmpFolder = [fpM '/tmp_spm_' mov_file_name ];
% if ~exist(tmpFolder, 'dir')
%     mkdir(tmpFolder);
% end


%reslice flags
flags.mask =  1;
flags.mean = 0;
flags.interp = 7;
flags.which = 2;
flags.wrap =  [0 0 0];
flags.prefix = '';


fix_spm_vol = spm_vol(fix_name);
fix3DName = fullfile(tmpFolder, 'fix.nii');
spm_file_merge(fix_spm_vol(fix_index),fix3DName);
if runBFC
    if UseOnlyGM
        CreateBinaryBrainmaskWithSPM(fix3DName, .2, fix_index, 0, 0);
        fix3DName = fullfile(tmpFolder, 'c1fix.nii');
    else        
        RunSPM_BFC(fix3DName);
        fix3DName = fullfile(tmpFolder, 'mfix.nii');       
    end
end
if UseOnlyGM
    CreateBinaryBrainmaskWithSPM(fix3DName, .2, fix_index, 0, 0);
    fix3DName = fullfile(tmpFolder, 'c1fix.nii');
end

mov_spm_vol = spm_vol(mov_name);

FOV_mismatch=0;
if any(mov_spm_vol(1).mat(:) ~= fix_spm_vol(1).mat(:))
     warning('Your fix and moving files have a different voxel-to-world trafo.You have to use the resliced file with prefix r. Please, consult your supervisor, if you get this warning!');
     FOV_mismatch=1;
end

if isempty(mov_index) % if [] use :
   mov_index = 1:numel(mov_spm_vol);
else
    if ~isempty(interp_trafo_index)
        if ~(sum(ismember(mov_index, interp_trafo_index))==length(interp_trafo_index))
            error('interp_trafo_index is not completely in mov_index');
        end
    end
end
spm_file_merge(mov_spm_vol(mov_index),new_name);

mov3DName = fullfile(tmpFolder, 'mov.nii');
if runBFC
    mov3DBFCName = fullfile(tmpFolder, 'mmov.nii');
end
if UseOnlyGM
    mov3DUseOnlyGMName = fullfile(tmpFolder, 'c1mov.nii');
end

%% adapted Martin Freudensprung 08.2025
spm_vol_new = spm_vol(new_name); % mov_index = [28:30];interp_trafo_index = [29]
%idx = 1;
txMats = cell(numel(mov_index)+1,1);
txMats{1,1} = spm_get_space(fix_name);
% interpolate txMats for low intensity offsets
% remove mov_index that will be interpolated
mov_index_incomplete = mov_index;
interp_trafo_index2=ismember(mov_index,interp_trafo_index); %interp_trafo_index2 = List which offsets out of mov_index shall be interpolated
mov_index_incomplete(interp_trafo_index2) = [];

parfor ii = mov_index
    if ismember(ii, mov_index_incomplete)
        mov3DName = fullfile(tmpFolder, ['mov_' num2str(ii) '.nii']);
        mov3DBFCName = fullfile(tmpFolder, ['mmov_' num2str(ii) '.nii']);
        mov3DUseOnlyGMName = fullfile(tmpFolder, ['c1mov_' num2str(ii) '.nii']);  

        spm_file_merge(mov_spm_vol(ii), mov3DName); % copy present "offset to move" to tmp_spm\mov.nii
        if runBFC
            if UseOnlyGM
                CreateBinaryBrainmaskWithSPM(mov3DName, .2, ii, 0, 0);
                spm_vol_new(ii).mat = RunSPMCoregistration(fix3DName,mov3DUseOnlyGMName,spmMethod);
            else
                RunSPM_BFC(mov3DName);
                spm_vol_new(ii).mat = RunSPMCoregistration(fix3DName,mov3DBFCName,spmMethod);
            end
        else
            if UseOnlyGM
                CreateBinaryBrainmaskWithSPM(mov3DName, .2, ii, 0, 0);
                spm_vol_new(ii).mat = RunSPMCoregistration(fix3DName,mov3DUseOnlyGMName,spmMethod);
            else
                spm_vol_new(ii).mat = RunSPMCoregistration(fix3DName,mov3DName,spmMethod);
            end
        end
        txMats{ii+1,1} = spm_vol_new(ii).mat;
    %else

    end

end

% for ii = mov_index_incomplete
%     spm_file_merge(mov_spm_vol(ii), mov3DName); % copy present "offset to move" to tmp_spm\mov.nii
%     if runBFC
%         if UseOnlyGM
%             CreateBinaryBrainmaskWithSPM(mov3DName, .2, ii, 0, 0);
%             spm_vol_new(idx).mat = RunSPMCoregistration(fix3DName,mov3DUseOnlyGMName,spmMethod);
%         else
%             RunSPM_BFC(mov3DName);
%             spm_vol_new(idx).mat = RunSPMCoregistration(fix3DName,mov3DBFCName,spmMethod);
%         end
%     else
%         if UseOnlyGM
%             CreateBinaryBrainmaskWithSPM(mov3DName, .2, ii, 0, 0);
%             spm_vol_new(idx).mat = RunSPMCoregistration(fix3DName,mov3DUseOnlyGMName,spmMethod);
%         else
%             spm_vol_new(idx).mat = RunSPMCoregistration(fix3DName,mov3DName,spmMethod);
%         end
%     end
%     txMats{idx+1,1} = spm_vol_new(idx).mat;
%     idx = idx+1; % jump to next idx
%     if idx < length(interp_trafo_index2) % if not already done the whole stack... 
%         while interp_trafo_index2(idx), idx = idx +1; end % ...skip offsets from interp_trafo_index
%     end
%     %disp (['run spm_coreg for mov_index number (idx): ' num2str(idx) ' = offset number (ii): ' num2str(ii)]);
%     waitbar((idx-sum(interp_trafo_index2))/length(mov_index_incomplete));
% end
%% start 2019/12/04 Alexander German 
% spm_vol_new = spm_vol(new_name); % mov_index = [28:30];interp_trafo_index = [29]
% idx = 1;
% txMats = cell(numel(mov_index)+1,1);
% txMats{1,1} = spm_get_space(fix_name);
% % interpolate txMats for low intensity offsets
% % remove mov_index that will be interpolated
% mov_index_incomplete = mov_index;
% interp_trafo_index2=ismember(mov_index,interp_trafo_index); %interp_trafo_index2 = List which offsets out of mov_index shall be interpolated
% mov_index_incomplete(interp_trafo_index2) = [];
% for ii = mov_index_incomplete
%     spm_file_merge(mov_spm_vol(ii), mov3DName); % copy present "offset to move" to tmp_spm\mov.nii
%     if runBFC
%         if UseOnlyGM
%             CreateBinaryBrainmaskWithSPM(mov3DName, .2, ii, 0, 0);
%             spm_vol_new(idx).mat = RunSPMCoregistration(fix3DName,mov3DUseOnlyGMName,spmMethod);
%         else
%             RunSPM_BFC(mov3DName);
%             spm_vol_new(idx).mat = RunSPMCoregistration(fix3DName,mov3DBFCName,spmMethod);
%         end
%     else
%         if UseOnlyGM
%             CreateBinaryBrainmaskWithSPM(mov3DName, .2, ii, 0, 0);
%             spm_vol_new(idx).mat = RunSPMCoregistration(fix3DName,mov3DUseOnlyGMName,spmMethod);
%         else
%             spm_vol_new(idx).mat = RunSPMCoregistration(fix3DName,mov3DName,spmMethod);
%         end
%     end
%     txMats{idx+1,1} = spm_vol_new(idx).mat;
%     idx = idx+1; % jump to next idx
%     if idx < length(interp_trafo_index2) % if not already done the whole stack... 
%         while interp_trafo_index2(idx), idx = idx +1; end % ...skip offsets from interp_trafo_index
%     end
%     %disp (['run spm_coreg for mov_index number (idx): ' num2str(idx) ' = offset number (ii): ' num2str(ii)]);
%     waitbar((idx-sum(interp_trafo_index2))/length(mov_index_incomplete));
% end

%% 
moved = spm_vol_new;
offsets = (1:1:numel(txMats)).';
% remove indices and elements of txMats that will be interpolated
offsets(logical([0 interp_trafo_index2])) = [];
% Deal with exception interp_trafo_index extends to margin of mov_index
if ~isempty(interp_trafo_index)
    if (interp_trafo_index(1) == mov_index(1))||(interp_trafo_index(end) == mov_index(end))
        for ii = interp_trafo_index    
            txMats{ii+1,1} = txMats{interp_trafo_index(1),1};
        end
        offsets = (1:1:numel(txMats)).';
    end
end
%    
txMats_incomplete = txMats(offsets);
% convert txMats_incomplete to array txMats_array
txMats_array = zeros(numel(txMats_incomplete),4,4); 
for ii = 1:1:numel(txMats_incomplete)
    txMats_array(ii,:,:) = txMats_incomplete{ii};
end
% perform linear interpolation
txMats_interpol_array = zeros(numel(txMats),4,4);
for ii =1:1:4
    for jj = 1:1:4
        txMats_interpol_array(:,ii,jj) = interp1q(offsets,squeeze(txMats_array(:,ii,jj)),(1:numel(txMats)).');
    end
end
% convert txMats_interpol_array to back to cell format
txMats_interpol = mat2cell(txMats_interpol_array,ones(numel(txMats),1));
for ii = 1:1:numel(txMats)
txMats_interpol{ii} = squeeze(txMats_interpol{ii});
end
% overwrite txMats
txMats = txMats_interpol;
% overwrite spm_vol_new
idx = 1;
for ii = mov_index
    spm_vol_new(idx).mat = txMats{idx+1,1};
    Tx = txMats{idx}*inv(txMats{1,1});
    TxParams = spm_imatrix(Tx);
    x(idx) = TxParams(1);
    y(idx) = TxParams(2);
    z(idx) = TxParams(3);
    pitch(idx) = TxParams(4)*180/pi;
    roll(idx) = TxParams(5)*180/pi;
    yaw(idx) = TxParams(6)*180/pi;
    idx = idx+1;
end

% Adapted for parallel Freudensprung 08.2025
% parfor idx = 1:length(mov_index)
%     spm_vol_new(idx).mat = txMats{idx+1,1};
%     Tx = txMats{idx}*inv(txMats{1,1});
%     TxParams = spm_imatrix(Tx);
%     x(idx) = TxParams(1);
%     y(idx) = TxParams(2);
%     z(idx) = TxParams(3);
%     pitch(idx) = TxParams(4)*180/pi;
%     roll(idx) = TxParams(5)*180/pi;
%     yaw(idx) = TxParams(6)*180/pi;
%     %idx = idx+1;
% end

%% end 2019/12/04 Alexander German

save([fpM '/TxParams.mat'], 'txMats');


%reslice the motion corrected image onto fix stack (including resolution)
if FOV_mismatch
    % copyfile(new_name,['r' new_name]); 
    spm_file_merge(spm_vol_new,['r' new_name]);  % seems to be necessary before reslicing
    
    flags.which=1;
    flags.mask=0;
    Image_stack = {fix3DName;['r' new_name]};
    spm_reslice(Image_stack,flags); %Reslicing: adjust the resolution
end

%reslice the motion corrected image intrinsically 
spm_reslice(spm_vol_new, flags);

rmdir(tmpFolder, 's');
delete *]spm.mat temp.nii

 fig = figure('Visible', 'off'); 
 subplot(2,1,1)
 hold on
 plot(x),plot(y),plot(z)
 ylabel('Movement [mm]');
 legend('x','y','z');
 title(['Xmax= ' num2str(abs(max(x))) ', Ymax= ' num2str(abs(max(y))) ', Zmax= ' num2str(abs(max(z)))])
 subplot(2,1,2)
 hold on
 plot(pitch),plot(roll),plot(yaw)
 ylabel('Rotation [�]');
 xlabel('Measurement');
 legend('pitch','roll','yaw');
 title(['Pitchmax= ' num2str(abs(max(pitch))) ', Rollmax= ' num2str(abs(max(roll))) ', Yawmax= ' num2str(abs(max(yaw)))])
 saveas(gcf,[fpM '/' mov_file_name '_Movement.png'])
 close(fig);



end