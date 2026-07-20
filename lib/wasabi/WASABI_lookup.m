function [P]=WASABI_lookup(wbib,bib_entries,Z,P)    


% SKP=wbib*Z(:);
% idx=find(SKP==max(max(max(max(SKP)))));
% [B1(idx) B0(idx) c(idx) af(idx)]

SSE=sum((wbib-repmat(Z(:),1,size(wbib,1))').^2,2);
idx=find(SSE==min(min(min(min(SSE)))),1);

% figure, plot(SKP); hold on
%plot(idx,max(max(max(SKP))),'o');
% figure, plot(SSE); hold on;
 
p0 = bib_entries(idx,:);
lb=p0-0.5;
ub=p0+0.5;
lb(1)=p0(1)*0.2;
ub(1)=p0(1)*2.5;

P.FIT.lower_limit_fit = lb;
P.FIT.upper_limit_fit = ub;
P.FIT.start_fit = p0;