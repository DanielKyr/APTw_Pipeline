function [wbib, bib_entries] =WASABI_create_bib(P)

B1_bib=[0.6:0.05:1.4]*P.SEQ.B1;
B0_bib=[-0.5:0.05:1.2];
c_bib=[0.6:0.1:1];
af_bib=[1.3:0.1:2];
[B1,B0,c,af] = ndgrid(B1_bib,B0_bib,c_bib,af_bib);

bib_entries=[ B1(:) B0(:) c(:) af(:)];
wbib=zeros(numel(B1),numel(P.SEQ.w));
for ii=1:numel(B1)
    
    if strcmp(P.FIT.fitfunc,'WASABIFIT_2abs')
        wbib(ii,:)= WASABIFIT_2abs([ B1(ii) B0(ii) c(ii) af(ii)], P.SEQ.w,[P.SEQ.FREQ P.SEQ.tp 1]);
    else
        wbib(ii,:)= WASABIFIT_2([ B1(ii) B0(ii) c(ii) af(ii)], P.SEQ.w,[P.SEQ.FREQ P.SEQ.tp 1]);
    end;
    
end;


