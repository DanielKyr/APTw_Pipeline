function [Z4pc, order, latent,SCORE,COEFF,varargout] = pcca_3D(Z,P, order, plotflag, Segment_3D,slc,trainMask)
% trainMask (optional, 7th arg): voxels that FIT the PCA basis (COEFF/mu).
% Segment_3D still controls which voxels get RECONSTRUCTED/returned in Z4pc, same as
% before. Defaults to Segment_3D (old behavior: train and apply on the same voxels).
%
% Why this split exists: Segment_3D may legitimately be wider than the voxels you'd
% trust to fit a PCA basis from (e.g. a brain+skull display mask vs. brain-only for
% fitting) - pca() is a GLOBAL fit, so training it on noisier, non-brain-physics
% voxels shifts the basis and therefore the reconstruction for EVERY voxel, brain
% included, even though those brain voxels' own input data never changed. Letting
% trainMask stay narrow while Segment_3D is wide keeps the basis exactly as robust
% as a brain-only fit while still reconstructing/returning the wider footprint.

if nargin<6
slc=fix(size(Z,3)/2); % for plotting
end

if nargin<3
    order=4;
end;

if nargin<4
    plotflag=0;
end;

if nargin<7
    trainMask = Segment_3D;
end




    if nargin>4
     for ii=1:size(Z,4)
     Z(:,:,:,ii)=squeeze(Z(:,:,:,ii)).*Segment_3D;
     end;
    end;


    Z(isnan(Z))=0;

%     X=reshape(Z,size(Z,1)*size(Z,2)*size(Z,3),size(Z,4));
    % >0, not a bare truthiness test: Segment_3D/trainMask use NaN (not 0) for
    % background, and find() treats NaN as nonzero - a bare find(Segment_3D) silently
    % includes every background voxel too (confirmed: find([1 NaN 0 2]) == [1 2 4]).
    maskind = find(Segment_3D > 0);
    trainind = find(trainMask > 0);
    Z1 = permute(Z,[4 1 2 3]);
    Xtrain = Z1(:,trainind)';
    Xtrain(isinf(Xtrain)) = 0;
    [COEFF,SCORE,latent,~,~,mu] = pca(Xtrain) ;

    if (plotflag>0)
        %figure; plot(log10(latent)); xlabel('Component'); ylabel('log_{10} Eigenvalue')

        h1=figure('Unit','normalized','OuterPosition',[0 0, 0.5 0.5]);
        subplot(2,2,1),plot(P.SEQ.w,mean(Xtrain)'); title('mean Z-spectrum');
        subplot(2,2,2),plot(P.SEQ.w,COEFF(:,1:8));   title('first eight eigenvectors');
        subplot(2,2,3),imagesc(COEFF); title('all eigenvectors');
%         saveas(h1,'PCA_eigenvectors');

%         SCORE_S=reshape(SCORE,size(Z,1),size(Z,2),size(Z,3),size(Z,4));
        SCORE_S = zeros(size(Z1));
        SCORE_S(:,trainind)=SCORE.';
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

    % Reconstruct every voxel Segment_3D asks for (maskind, which may be wider than
    % trainind) by projecting onto the basis fit from trainind above. When
    % trainMask==Segment_3D (the default), maskind==trainind and this reduces
    % exactly to the original single-mask behavior.
    Xapply = Z1(:,maskind)';
    Xapply(isinf(Xapply)) = 0;
    SCOREapply = (Xapply - mu) * COEFF; % same projection pca() itself uses for SCORE

    if numel(order)>1
        ZZ=SCOREapply(:,1)*COEFF(:,1)'*0;
        for ii=order(1:end);
            ZZ= ZZ+SCOREapply(:,ii)*COEFF(:,ii)';
        end;
    elseif numel(order)==1
         % do multiplication here
         ZZ = SCOREapply*COEFF';
    end

    ZZ = ZZ + repmat(mu,size(ZZ,1),1); % mittelwert wieder dazu

%     Z4pc=reshape(ZZ,size(Z,1),size(Z,2),size(Z,3),size(Z,4));
    Z4pc = zeros(size(Z1));
    Z4pc(:,maskind)=ZZ.';
    Z4pc = permute(Z4pc,[2 3 4 1]);
    
    
   
    

