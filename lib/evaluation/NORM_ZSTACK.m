function [Z,M0_stack_4D,type]=NORM_ZSTACK(Mz_stack,M0_stack,P,Segment,type)


if nargin<5
    type='M0';
end;

if ismatrix(Segment)
    for ii=1:size(Mz_stack,3)
        Segment_3D(:,:,ii)=Segment;
    end;
else
    Segment_3D=Segment;
end

ind_zeros=find(M0_stack==0);
M0_stack(ind_zeros)=0.001;
sizeMz=size(Mz_stack);

M0_stack_4D=zeros(sizeMz);

switch type
    case 'M0'
        
        for ii=1:numel(P.SEQ.w)
            if (ndims(M0_stack)<4)
                M0_stack_4D(:,:,:,ii)=M0_stack;
            else
                M0_stack_4D(:,:,:,ii)=M0_stack(:,:,:,ii);
            end
            Mz_stack(:,:,:,ii)=Mz_stack(:,:,:,ii).*Segment_3D;
        end
        
    case 'baseline1pt'
        for ii=1:numel(P.SEQ.w)
            Mz_stack(:,:,:,ii)=Mz_stack(:,:,:,ii).*Segment_3D;
        end
        
        for ii=1:sizeMz(1)
            for jj=1:sizeMz(2)
                for kk=1:sizeMz(3)
                    if Segment_3D(ii,jj,kk)==1
%                       M0_stack_4D(ii,jj,kk,:)=Segment_3D(ii,jj,kk).*interp1q([P.SEQ.w(1); P.SEQ.w(end)],[Mz_stack(ii,jj,kk,1) ; Mz_stack(ii,jj,kk,end)],P.SEQ.w);
						M0_stack_4D(ii,jj,kk,:)=Segment_3D(ii,jj,kk).*interp1q([0; numel(P.SEQ.w)+1],[Mz_stack(ii,jj,kk,1) ; Mz_stack(ii,jj,kk,end)],(1:numel(P.SEQ.w))');

                    end
                end
            end
        end
    case 'baseline2pt'
        for ii=1:sizeMz(1)
            for jj=1:sizeMz(2)
                for kk=1:sizeMz(3)
                    if Segment_3D(ii,jj,kk)==1
                        M0_stack_4D(ii,jj,kk,:)=Segment_3D(ii,jj,kk).*interp1q([P.SEQ.w(1); P.SEQ.w(end)],[mean(Mz_stack(ii,jj,kk,1:2),4) ; mean(Mz_stack(ii,jj,kk,end-1:end),4)],P.SEQ.w);
                    end
                end
            end
        end
        
end

Z=Mz_stack./M0_stack_4D;