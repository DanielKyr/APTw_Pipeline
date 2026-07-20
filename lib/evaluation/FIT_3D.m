function [popt, P]= FIT_3D(Z_stack,P,Segment,slices)
%[popt, P]= FIT_3D(Z_stack,P,Segment,StartValues)


mysize=size(Z_stack);

% if no Segment is given to function
if nargin < 3
    Segment = ones(mysize(1),mysize(2),mysize(3));
end

% make Segment 3D if Z_stack is 3D
if (ndims(Segment)==2 && mysize(3)>1)
    for ii=1:mysize(3)
        Segment(:,:,ii)=Segment(:,:,1);
    end
end

if nargin<4
    slices=1:mysize(3);
end;

% case of no explicit startvalues in function is dealt with in voxel loop
% further down


% allocation
mysize=size(Z_stack);
N_offsets=mysize(4); % number of points in the z-spec

Stack_single=double(Z_stack);

% this is only for initializing popt and getting the fitfunction
tmpzspec=zeros(N_offsets,1);
[P] = fitmodelfunc_NUM(tmpzspec,P); % extoptions is handled in here
popt=NaN(mysize(1),mysize(2),mysize(3),P.FIT.nparams);

if isfield(P.FIT,'PCI')
    if P.FIT.PCI == 1 % if param confidence intervals are to be calculated, saved later in P.FIT.PCIstack, P.FIT.R2stack
        pci=NaN(mysize(1),mysize(2),mysize(3),P.FIT.nparams,2); 
        R2 = NaN(mysize(1),mysize(2),mysize(3),1); 
    end
else
    P.FIT.PCI = 0;
end

if ( exist('StartValues','var')>0 && ~(islogical(StartValues)) ) %% this is now handled in fitmodelfunc_NUM 
        P.FIT.start_fit = StartValues;
end

if ~exist('P.EVAL.neural_lookup','var')  
    P.EVAL.neural_lookup=0;
end

% create lookuptable for WASABI fit here
if (strcmp(P.FIT.fitfunc,'WASABIFIT') || strcmp(P.FIT.fitfunc,'WASABIFIT_2') || strcmp(P.FIT.fitfunc,'WASABIFIT_2abs') )
%      [WASABI_bib, bib_entries] = lookuptable_WASABI(P); % can maybe be removed in the future
%      LOOKUP{1}=WASABI_bib;
%      LOOKUP{2}=bib_entries;
    if P.EVAL.neural_lookup==0
          [wbib, bib_entries] =WASABI_create_bib(P);
    end;

end

parflag=1;
try 
    license('test','Distrib_Computing_Toolbox')
    Composite();
catch
    parflag=0;
end
    


if ( parflag )
    
 
    % Spread Matritzes on labs
    Stack_c = Composite();  % One element per lab in the pool
    tmpzspec_c=Composite();
    popt_c = Composite();
    Segment_c = Composite();
    P_c = Composite();
    
    if P.FIT.PCI == 1
        popt_c = Composite();
        pci_c = Composite();
        R2_c = Composite();
    end
    
    if isfield(P.FIT, 'p0_stack') && isfield(P.FIT, 'lb_stack') && isfield(P.FIT, 'ub_stack')
        p0_stack_c = Composite();
        lb_stack_c = Composite();
        ub_stack_c = Composite();
    end
    
    npools=size(Stack_c,2); %% number matlabpools
    np=mysize(2)/npools;
    %InterVals
    IV = @(i) 1+fix(np*(i-1)):fix(np*(i)); 
    
    for ii = 1:length(Stack_c)
        
        Stack_c{ii} = Stack_single(:,IV(ii),:,:);
        
        Segment_c{ii}=Segment(:,IV(ii),:);
        tmpzspec_c{ii}=zeros(mysize(4),1);
        P_c{ii}=P;
        popt_c{ii} = NaN(mysize(1),numel(IV(ii)),mysize(3),P.FIT.nparams);
        if P.FIT.PCI == 1
            popt_c{ii} = NaN(mysize(1),numel(IV(ii)),mysize(3),P.FIT.nparams);
            pci_c{ii} = NaN(mysize(1),numel(IV(ii)),mysize(3),P.FIT.nparams,2);
            R2_c{ii} = NaN(mysize(1),numel(IV(ii)),mysize(3),1);
       
        end
        
        if isfield(P.FIT, 'p0_stack') && isfield(P.FIT, 'lb_stack') && isfield(P.FIT, 'ub_stack')
            p0_stack_c{ii} = P.FIT.p0_stack(:,IV(ii),:,:);
            lb_stack_c{ii} = P.FIT.lb_stack(:,IV(ii),:,:);
            ub_stack_c{ii} = P.FIT.ub_stack(:,IV(ii),:,:);
        end
    end
    
    % iteration on partial matritzes
    
    spmd
        
          for k=slices %slice
            for i=1:mysize(1)
                %tic
%                 fprintf('Labindex: %d,slice %d,  Zeile: %d von %d , Spalten: %d\n',labindex,k,i,mysize(1),numel(IV(labindex)));
               
                for j=1:numel(IV(labindex))
                                     
                    if (Segment_c(i,j,k)==1)
                        tmpzspec_c(:,1)=squeeze(Stack_c(i,j,k,:));
                        
                        if isfield(P.FIT, 'p0_stack') && isfield(P.FIT, 'lb_stack') && isfield(P.FIT, 'ub_stack')
                            P_c.FIT.start_fit = squeeze(p0_stack_c(i,j,k,:))';
                            P_c.FIT.lower_limit_fit = squeeze(lb_stack_c(i,j,k,:))';
                            P_c.FIT.upper_limit_fit = squeeze(ub_stack_c(i,j,k,:))';
                        
                        end
                        
%                         in case data dependent startvalues/boundaries are chosen
%                         [P_c] = fitmodelfunc_NUM(tmpzspec,P_c);
                        
%                                 P_c.FIT.start_fit = StartValues;    
                        
                        
                        % perform lookup in lookuptable, here startvalues and
                        % bounds are overwritten in P
                        if (strcmp(P.FIT.fitfunc,'WASABIFIT') || strcmp(P.FIT.fitfunc,'WASABIFIT_2')|| strcmp(P.FIT.fitfunc,'WASABIFIT_2abs') )
%                                 [P_c]=perform_lookup(LOOKUP,tmpzspec_c,P_c);
%                                 
                                if P.EVAL.neural_lookup
                                    [P_c]=WASABI_lookup_deep(tmpzspec_c,P_c);   
                                else
                                    %[P_c]=perform_lookup(LOOKUP, tmpzspec_c, P_c);%AL
                                    [P_c]=WASABI_lookup(wbib,bib_entries,tmpzspec_c,P_c); 
                                end;
                        elseif P.EVAL.neural_lookup==1
                            % set initial conditions using NN
                            [P_c] = p0_lookup_NN(tmpzspec_c,P_c);
                        end
   
                        
                        if P.FIT.PCI == 1
                            % output of levmar_fit: [popt, ret, covar, info, pci, R2
                     
                            [popt_c(i,j,k,:), ~, ~, ~, pci_c(i,j,k,:,:), R2_c(i,j,k,:)]= levmar_fit(tmpzspec_c,P_c);
                        else
                            [popt_c(i,j,k,:), ~, ~, ~, ~, ~]= levmar_fit(tmpzspec_c,P_c);
                        end

                    end;
                    
                end; % end y-axis loop (j)
                
                
            end % end x-axis loop (i)

        end  % end for slice loop (k)
    
    end % end spmd
    
    
    % reallocation labs to local
    
    Stack_single = cat(2, Stack_c{:});
           
    popt = cat(2,popt_c{:});
    if P.FIT.PCI == 1
        pci = cat(2,pci_c{:});
        R2 = cat(2,R2_c{:});
    end
        
else  %not parallel
    
       
    pixeltofit = numel(Segment(Segment==1));
    pixelcounter = 1;
    hh = waitbar(0);
    
    
    for k=slices %slice
        
        str = sprintf('Fitting slice number %d out of %d', k, mysize(3));
        
        for i=1:mysize(1)
            
            for j=1:mysize(2)
                                
                if Segment(i,j,k) == 1
                    
                    waitbar(pixelcounter/pixeltofit,hh,str);
                    pixelcounter = pixelcounter + 1;
                    
                    % 1 D data
                    tmpzspec(:,1) = squeeze(Stack_single(i,j,k,:));
                    
                    % get startvalues and bounds (important that this is here
                    % since startvalues depend on values in data (tmpzspec)
                    % sometimes
                    
                    [P] = fitmodelfunc_NUM(tmpzspec,P);
            
                    if ( exist('StartValues','var')>0 && ~(islogical(StartValues)) )
                        % case of normal startvalue vector
                        if ndims(StartValues)==1 
                            P.FIT.start_fit = StartValues;
                         % case of B1map guess (if ever necesairy again)
                        elseif ndims(StartValues)==2
                            P.FIT.start_fit = StartValues(i,j);
                        end 
                    end
                    
                    % perform lookup in lookuptable, here startvalues and
                    % bounds are overwritten in P
                    if (strcmp(P.FIT.fitfunc,'WASABIFIT') || strcmp(P.FIT.fitfunc,'WASABIFIT_2') || strcmp(P.FIT.fitfunc,'WASABIFIT_2abs')  )
                        % [P]=perform_lookup(LOOKUP,tmpzspec,P);
                        % [P]=WASABI_lookup(wbib,bib_entries,tmpzspec,P);
                        if P.EVAL.neural_lookup
                            [P]=WASABI_lookup_deep(tmpzspec,P);
                        else
                            [P]=WASABI_lookup(wbib,bib_entries,tmpzspec,P);
                        end;
                    elseif (strcmp(P.FIT.fitfunc,'T1recovery_biex') && ~(islogical(StartValues)) )
                        P.FIT.lower_limit_fit(1:3) = StartValues(i,j,k,:);
                        P.FIT.upper_limit_fit(1:3) = StartValues(i,j,k,:);
                        P.FIT.start_fit=p0;
                        P.FIT.start_fit(1:3) = StartValues(i,j,k,:);
                    elseif P.EVAL.neural_lookup==1
                            % set initial conditions using NN
                        [P] = p0_lookup_NN(tmpzspec,P);
                    end
                    
                    if isfield(P.FIT, 'p0_stack') && isfield(P.FIT, 'lb_stack') && isfield(P.FIT, 'ub_stack')
                            P.FIT.start_fit = squeeze(P.FIT.p0_stack(i,j,k,:))';
                            P.FIT.lower_limit_fit = squeeze(P.FIT.lb_stack(i,j,k,:))';
                            P.FIT.upper_limit_fit = squeeze(P.FIT.ub_stack(i,j,k,:))';
                    end
                    
                    % all information about startvalues/bounds is saved in
                    % P struct
                    if P.FIT.PCI == 1
                        % output of levmar_fit: [popt, ret, covar, info, pci, R2
                        [popt(i,j,k,:), ~, ~, ~, pci(i,j,k,:,:), R2(i,j,k,:)]= levmar_fit(tmpzspec,P);
                    else
                        [popt(i,j,k,:), ~, ~, ~, ~, ~] = levmar_fit(tmpzspec,P);
                    end
                                         
                end
                
            end
            
        end
           
    end
    
    close(hh);
    
end

if P.FIT.PCI == 1 % FG: save PCI and R2 results in P struct
                    % tried to avoid more/new outputs of FIT_3D in order to
                    % let it still work with old function call interface
    P.FIT.PCIstack = pci;
    P.FIT.R2stack = R2;
end
