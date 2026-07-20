function [M0_stack,P]=fitM0(M_nosat_stack,P)

%function M0_stack=fitM0(M_nosat_stack,P)
mysize=size(M_nosat_stack);
if numel(P.SEQ.w) == 0 %SM: might happen for tSNR measurement @ M0 offsets
    warning('seems there were no saturated but only multiple M0 images recorded!');
    M0_stack=zeros(mysize(1),mysize(2),mysize(3),1);
else
    M0_stack=zeros(mysize(1),mysize(2),mysize(3),numel(P.SEQ.w));
end

M_nosat_stack(:,:,:,mysize(4)+1)=M_nosat_stack(:,:,:,mysize(4)); %% the M0 stack is extended by 1 to make sure that the last point is not crazily extrapolated
P.SEQ.index_M0= [P.SEQ.index_M0 max([P.SEQ.index_no_M0(end) P.SEQ.index_M0(end)])+1 ]; %% the index M0 is also extended by the last measured offset index +1

%% SM: we may have 2 repeated M0 directly after each other --> take mean value
% % treat these as one M0-image!
% % SM: we may have 2 repeated M0 directly after each other --> take mean value
% % treat these as one M0-image!
% if length(P.SEQ.index_M0)>1
%     answer = questdlg('want to select M0 or average?','GUI','select','average','select');
%     switch answer
%         case 'select'
%             answer = inputdlg(['Replace by NaN to remove! Current M0s: '],'GUI',1,{num2str(P.SEQ.index_M0)});
%             P.SEQ.index_M0_meas = P.SEQ.index_M0(1:end-1); % just for documentation 
%             keepThese           = ~isnan(str2num(answer{1,1}));
%             P.SEQ.index_M0      = P.SEQ.index_M0(keepThese);
%             indx                = find(keepThese);
%             M_nosat_stack       = M_nosat_stack(:,:,:,indx); %% WE REMOVE FRAMES HERE THIS MIGHT BE TRICKY!!!!!!!
%             % update index:
%             [after_mod,sortInd] = sort(cat(2,P.SEQ.index_M0,P.SEQ.index_no_M0));% these are all index after removal of M0
%             [~,J] = sort(sortInd);
%             if min(after_mod) == 2;after_mod =after_mod-1;end; %in case 1st image was M0 and was removed 
%             runIndex = (after_mod([1,1:end-1])-after_mod)+1; 
%             while min(runIndex<0)
%                 firstElement = find(runIndex<0,1);%first step ~=0
%                after_mod(firstElement:end) = after_mod(firstElement:end) + 1 ; 
%                runIndex = (after_mod([1,1:end-1])-after_mod)+1; %ok check again
%             end
%             % now we "invert" the sort again
%             beforeSort = after_mod(J);
%             P.SEQ.index_M0      = beforeSort([1:length(P.SEQ.index_M0)]);
%             P.SEQ.index_no_M0   = beforeSort([length(P.SEQ.index_M0)+1:end]);
% %             P.SEQ.index_M0      = P.SEQ.index_M0(indx);
%         case 'average'
%             indx = abs(P.SEQ.index_M0-P.SEQ.index_M0([2:end,end])); %extended M0 will apper as 0 in here!
%             indx(indx~=1) = 0; % indx==1 is now: "me and next are M0"
%             indx(end-1)=0; % last one simply was repetition of end-1!
%             temp = M_nosat_stack;
%             for n=1:length(indx)
%               if indx(n)==1 %this image and the next one are both M0
%                   temp(:,:,:,n)    = (temp(:,:,:,n)+temp(:,:,:,n+1))/2;
%                   temp(:,:,:,n+1)  = temp(:,:,:,n);
%               end
%             end
%             M_nosat_stack               = temp;
%             M_nosat_stack(:,:,:,end)    = M_nosat_stack(:,:,:,end-1);% we might have to replaced by averaged M0 now. If not: nothing happens
%             P.SEQ.index_M0              = P.SEQ.index_M0(find(indx==0)); %also set new index
%     end % select or average multiple M0s
% end

%%
for ii=1:mysize(1)
    for jj=1:mysize(2)
        for kk=1:mysize(3)
            M0_stack(ii,jj,kk,:)  = interp1(P.SEQ.index_M0,squeeze(M_nosat_stack(ii,jj,kk,:)),P.SEQ.index_no_M0,'linear','extrap');
        end
        
    end
    
end

% referencing is done on indizes not on Offsets to correct for the signal
% drift over time. Non-uniform offset spacing falsifies that.