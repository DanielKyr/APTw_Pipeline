function [popt, ret, covar, info, pci, R2]=levmar_fit(M,P)

lb = P.FIT.lower_limit_fit;
ub = P.FIT.upper_limit_fit;
p0 = P.FIT.start_fit;

if isfield(P.FIT,'exclude')
    P.SEQ.w(P.FIT.exclude)=[];
    M(P.FIT.exclude)=[];
end;
    
PV= [P.SEQ.FREQ P.SEQ.tp P.SEQ.B1];

if ispc && exist('levmar','file')==3 && (P.FIT.PCI ~= 1) % FG: levmar does not allow for calculation of confidence intervals?!
    [ret, popt, info, covar] = levmar(P.FIT.fitfunc, p0, M, P.FIT.nIter, P.FIT.options, 'bc', lb, ub, P.SEQ.w, PV);
    pci = [NaN NaN]; R2=NaN;

elseif license('test', 'optimization_toolbox')
    [ret, popt, info, covar, pci, R2] = matlabfit(P.FIT.fitfunc, p0, M, P.FIT.nIter, P.FIT.options, 'bc', lb, ub, P.SEQ.w, PV, P.FIT.PCI);
else
    error('You dont have a mex file or the optimization toolbox');
end;
    
if ret==-1    
    popt=p0*0;
end;










