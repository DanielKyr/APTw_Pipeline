function [Z4pc, order, latent,SCORE,COEFF,varargout] = pcca_3D(Z,P, order, plotflag, Segment_3D,slc)

if nargin<6
slc=fix(size(Z,3)/2); % for plotting
end

if nargin<3
    order=4;
end;

if nargin<4
    plotflag=0;
end;


    
 
    if nargin>4
     for ii=1:size(Z,4)
     Z(:,:,:,ii)=squeeze(Z(:,:,:,ii)).*Segment_3D;
     end;
    end;

    
    Z(isnan(Z))=0;
    
%     X=reshape(Z,size(Z,1)*size(Z,2)*size(Z,3),size(Z,4));
    maskind = find(Segment_3D);
    Z1 = permute(Z,[4 1 2 3]);
    X = Z1(:,maskind)';
    X(isinf(X)) = 0;
    [COEFF,SCORE,latent,~,~,mu] = pca(X) ;
            
    if (plotflag>0)
        %figure; plot(log10(latent)); xlabel('Component'); ylabel('log_{10} Eigenvalue')
        
        h1=figure('Unit','normalized','OuterPosition',[0 0, 0.5 0.5]);
        subplot(2,2,1),plot(P.SEQ.w,mean(X)'); title('mean Z-spectrum');
        subplot(2,2,2),plot(P.SEQ.w,COEFF(:,1:8));   title('first eight eigenvectors');
        subplot(2,2,3),imagesc(COEFF); title('all eigenvectors');
%         saveas(h1,'PCA_eigenvectors');
        
%         SCORE_S=reshape(SCORE,size(Z,1),size(Z,2),size(Z,3),size(Z,4));
        SCORE_S = zeros(size(Z1));
        SCORE_S(:,maskind)=SCORE.'; 
        SCORE_S = permute(SCORE_S,[2 3 4 1]);
        h2=figure;
        montage(SCORE_S(:,:,slc,:),'DisplayRange',[-0.1 0.1]); title('all EV/coeff maps'); 
        set(h2,'Unit','normalized','OuterPosition',[0 0.5, 0.5 0.5]);
%         saveas(h2,'PCA_all.fig');
        
        figure('Unit','normalized','OuterPosition',[0.5 0.5, 0.5 0.5]),
        for ii=1:order(end)       
            IM=SCORE_S(:,:,slc,ii); 
            subplot(3,ceil(order(end)/3),ii), imagesc(IM,2*[-std(IM(:)) +std(IM(:))]); axis image;
        title(sprintf('EV %d',ii));
        end;
        end;
        
        if (plotflag>0)
            [order,P] = PCA_autoselect(latent,order,0); %lat input arg is flag to save (=1) the figure or not (=0)
        
        varargout{1} = P.EVAL.PCA.Median;
        varargout{2} = P.EVAL.PCA.Mali;
        end
    
    
    if numel(order)>1
        ZZ=SCORE(:,1)*COEFF(:,1)'*0;    
        for ii=order(1:end);   
            ZZ= ZZ+SCORE(:,ii)*COEFF(:,ii)';
        end;
    elseif numel(order)==1
         % do multiplication here
         ZZ = SCORE*COEFF'; 
    end
    
    ZZ = ZZ + repmat(mu,size(ZZ,1),1); % mittelwert wieder dazu
    
%     Z4pc=reshape(ZZ,size(Z,1),size(Z,2),size(Z,3),size(Z,4));
    Z4pc = zeros(size(Z1));
    Z4pc(:,maskind)=ZZ.';
    Z4pc = permute(Z4pc,[2 3 4 1]);
    
    
   
    

