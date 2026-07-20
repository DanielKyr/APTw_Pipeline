function x = WASABIFIT_2abs(p,w,PV)
freq=PV(1);
t_p=PV(2)*10^-6;
     
      B1=p(1);
      offset=p(2);
      c=p(3);
      af=p(4); %adjustment factor
      
     x=abs(c-af.*sin(atan((B1./((freq./gamma_)))./(w-offset))).^2.*sin(sqrt((B1./((freq./gamma_))).^2+(w-offset).^2).*freq.*(2.*pi).*t_p./2).^2);

