#simulate genotype-phenotype data

# 2nd July 2018 - Paul T


#simulate data for analysis with 200 SNPs with some linkage disequibrium, and 3 correlated phenotyes
#simulate 3 situations
# 1. no relationship between geno and pheno
# 2. strong relationship (r = .5) for small N SNPs with pheno
# 3. weak relationship (r = .1) for large N SNPs with pheno

#Aim: start by using GSCA approach and see if it captures the associations

require(doBy)
library(tidyr)
require(tidyverse)
require(MASS)
require(stats)
library(doSNOW)
library(foreach)
library(ASGSCA)
library(matrixcalc)
library(data.table)

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
didat<-read.table('/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/SLICmergedPROcounttest.txt',header=TRUE,stringsAsFactors=FALSE)
#Gene 1 - rs10255943 to rs2396765 (13 SNPs) foxp2
#Gene 2 - rs10271363 to rs17170742, 23 SNPs cntnap2
#Gene 3 - rs16957277 to rs16957385, 7 SNPs (edited)
#Gene 4 - rs11149652 to rs4782962, 18 SNPs atp2c2
#didat<-didat[,3:length(didat)] #strip off first 2 columns
#didat<-didat[c(1:52,54:71,73:75,77:135),] #remove those with no phenotype data


#for SNPs replace missing data with 1
#didat[is.na(didat)]<-1 #just to get this to run I have replaced NA with 1

#now read in 2nd dataset with more SNPs
didat2<-read.table('/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/GSCA_SLIC_paul.txt',header=TRUE,stringsAsFactors=FALSE)

myrow<-intersect(didat$ID,didat2$IND )

alldat<-dplyr::filter(didat,ID%in%myrow)
alldat2<-dplyr::filter(didat2,IND%in%myrow)
#checked visually these are in the same order, so can combine with cbind

alldat<-cbind(alldat[3:63],alldat2[5:292])

#######################################################################
refdat<-data.frame(SNP=colnames(alldat2[5:292]),gene=rep(NA,288))


refdat$gene[1:99]<-"foxp2"
refdat$gene[100:185]<-"cntnap2"
refdat$gene[186:221]="ubr1"
refdat$gene[222:288]="atp2c2"
########################################################################

bigtab<-cor(alldat,use='pairwise.complete.obs')

#write.table(bigtab, "corrtab.csv", sep=",") 

options(scipen = 999) #turn off scientific notation

gsca_sim_multigene3<-function(nsnp,nsnpeff,ngenes=1,nsub=120,ncases=100000,gpcorr=0.4,n2sim=3,plotter=TRUE,cb=cb,cluster=cluster,phenCorr=phenCorr)
{
  gene_break<-floor(nsnp/ngenes)
  
  #set the correlation 
  gpcov<-gpcorr
  
  snpnames<-paste0('snp', 1:nsnp)
  maf<-runif(nsnp,.25,.5) #minor allele freq set to value from .25 to .5
  
  #Setup a dataframe to hold to population simulated data.
  mydata<-data.frame(matrix(nrow=ncases,ncol=(3+sum(nsnp))))
  
  
  myfilenames <- c('DatasetRand_N',
                   paste0('DatasetUncorr_',nsnpeff,'SNP_',10*gpcorr),
                   'Dataset4Block_N',
                   paste0('Dataset',ngenes,'Block_',nsnpeff,'SNP_',10*gpcorr))
  thisfile<-4 #User specified: Indicates which type of correlation structure in datafile (could use loop here)
  mydatafile<- myfilenames[thisfile]
  
  #SNP values are 0, 1 or 2, but we start with random normal numbers
  
  #-----------------------------------------------------------------
  #simulate the SNPS as correlated zscores, correlation is mycorr
  #-----------------------------------------------------------------
  #Where there is correlation, assume correlation depends on how close SNPs are, 
  #achieved by making size of correlation proportional to distance
  # (where sequence order is proxy for distance)
  
  h <-nsnp
  LDbase<-0
  
  mymean<-rep(0,h) #vector of means to use in mvrnorm function
  mycorr<-0 #default is uncorrelated
  mycov2<-matrix(mycorr,nrow=h,ncol=h) #cov matrix for mvrnorm
  
  diag(mycov2)<-rep(1,h) #ones on diagonal of cov matrix
  if(thisfile>2){ #only add correlation for conditions where thisfile is 3 or 4
    thisr<-mycov2<-cor(alldat[,sample(1:dim(all.data)[2],h)],use='pairwise.complete.obs')
  }
  
  #################################################
  
  mycov_PT<-matrix(mycorr,nrow=nsnp+n2sim,ncol=nsnp+n2sim)
  mycov_PT[1:nsnp,1:nsnp]<-mycov2
  m<-diag(n2sim)
  pheno_mat<-m[lower.tri(m)|upper.tri(m)]<-0.75
  mycov_PT[(nsnp+1):(nsnp+n2sim),(nsnp+1):(nsnp+n2sim)]<-pheno_mat
  
  #snpeff_pos<-sample(1:nsnp,nsnpeff,replace=F)
  
  if(!nsnpeff==0){
    if(cluster==0){snpeff_pos<-sample(1:nsnp,nsnpeff,replace=F)} else {snpeff_pos<-c((nsnp-(nsnpeff-1)):nsnp)}
    
    mycov_PT[snpeff_pos,(nsnp+1):(nsnp+n2sim)] <- gpcov
    mycov_PT[(nsnp+1):(nsnp+n2sim),snpeff_pos] <- t(mycov_PT[snpeff_pos,(nsnp+1):(nsnp+n2sim)])
  }
  
  mycov<-mycov_PT
  diag(mycov)<-rep(1,dim(mycov)[1])
  #################################################
  
  #then set diagonal values to 1 for all
  #diag(mycov)<-rep(1,n2sim)
  if(matrixcalc::is.positive.definite(mycov)==FALSE)
  {mycov<-Matrix::nearPD(mycov,keepDiag=TRUE)$mat}
  
  
  
  mymean<-rep(0,dim(mycov)[1])
  mydata=mvrnorm(n = ncases, mymean, mycov)
  
  mydata<-as.data.frame(mydata)
  
  colnames(mydata)[1:nsnp]<-snpnames
  colnames(mydata)[(nsnp+1):(nsnp+3)]<-c('NwdRepPheno','LangPheno','NeurodevPheno')
  
  
  
  #-------------------------------------------------------------------------
  #Convert gene scores to integers: 0-2 for autosomal
  
  firstcol<-1
  lastcol<-nsnp
  p<-c(0,0,0) #initialise a vector to hold p values for different N alleles
  for (i in 1:nsnp){
    p[1]<-(1-maf[i])^2
    p[2]<-2*(1-maf[i])*maf[i]
    p[3]<-maf[i]^2
    
    #now use p-values to assign z-score cutoffs that convert to 0,1,2 or 3 minor alleles
    temp<-mydata[,i]
    w<-which(temp<qnorm(p[1]))
    mydata[w,i]<-0
    w<-which(temp>qnorm(p[1]))
    mydata[w,i]<-1
    w<-which(temp>qnorm(p[2]+p[1]))
    mydata[w,i]<-2
    
  }
  
  myr<-cor(mydata) #to check you have desired correlation structure, View(myr)
  
  
  #----------------------------------------------------------------------
  if(plotter==TRUE){
    library(tidyr)
    
    cor.data<-as.matrix(abs(myr))
    cor.data[lower.tri(cor.data)] <- NA
    
    cor_tri_N <- as.data.frame(cor.data) %>% 
      mutate(Var1 = factor(row.names(.), levels=row.names(.))) %>% 
      gather(key = Var2, value = value, -Var1, na.rm = TRUE, factor_key = TRUE) 
    
    g1<-ggplot(data = cor_tri_N, aes(Var2, Var1, fill = value)) + 
      geom_tile()+scale_fill_gradient(low = "white", high = "red")+theme_bw()+ theme(axis.text.x = element_text(angle = 90, hjust = 1),panel.grid.major = element_blank(), panel.grid.minor = element_blank(),axis.title = element_blank(),legend.title=element_blank(),text=element_text(size=14))
    
    print(g1)
    ggsave(paste0("/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/May 2019/simulations_results/plots/plot_SLIC_corr_",cb,".pdf"))
    
  }
  
  
  
  #----------------------------------------------------------------------
  # For each of nrun runs take a sample and analyse
  #----------------------------------------------------------------------
  nrun <- 500 #N runs to simulate
  
  mybigdata<-mydata
  
  
  
  ###########################################################################
  # Parallel processed loop
  ###########################################################################
  
  cl <- makeSOCKcluster(6)
  registerDoSNOW(cl)
  pb <- txtProgressBar(max=100, style=3)
  progress <- function(n) setTxtProgressBar(pb, n)
  opts <- list(progress=progress)
  
  
  myfitsummaryPT<-foreach (myn=1:nrun, .combine=rbind, .options.snow=opts,.packages = "ASGSCA") %dopar% {
    #if(myn%%10==0){print(myn)} #show progress on screen
    #read in data for required sample size
    myrows<-sample(ncases,nsub) 
    mysample<-mybigdata[myrows,]
    
    #use ASCSCA to analyse
    
    ObservedVar=colnames(mysample)[1:(nsnp+n2sim)]
    
    
    LatentVar=c(paste0("gene",1:ngenes),"Neurodev")
    
    
    #W0 is I x L matrix where rows are genotypes and traits, columns are genes and latent phenotype
    W0=matrix(rep(0,length(LatentVar)*(n2sim+nsnp)),nrow=n2sim+nsnp,ncol=length(LatentVar), dimnames=list(ObservedVar,LatentVar))
    
    
    if(ngenes==1){W0[1:nsnp,1] = 1}
    
    ind<-1:ngenes*gene_break
    #placer=ifelse(length(ind)<2,NA,c(1:ind[1],seq((ind[i-1]+1):ind[2],(ind[2]+1):ind[3],(ind[3]+1):ind[4]))
    
    for(w in 1:ngenes)
    {
      if(w==1){W0[1:ind[1],w] = 1}
      else{W0[(ind[w-1]+1):ind[w],w] = 1}
    }
    W0[(nsnp+1):(nsnp+3),(ngenes+1)]=1
    
    
    #B0 is L x L matrix with 0s and 1s, where 1 indicates arrow from latent geno in row to latent phenotype in column
    B0=matrix(rep(0,(ngenes+1)*(ngenes+1)),nrow=(ngenes+1),ncol=(ngenes+1), dimnames=list(LatentVar,LatentVar))
    B0[1:ngenes,(ngenes+1)]=1
    
    # GSCA(mysample,W0, B0,latent.names=LatentVar, estim=TRUE,path.test=FALSE,path=NULL,nperm=1000)
    # for quick scrutiny of weights use this -but for pvalues need slow version using path.test
    
    mynperm=100 #probably need more than this but to test prog use 100 for speed
    myfit<-GSCA(mysample,W0, B0,latent.names=LatentVar, estim=TRUE,path.test=TRUE,path=NULL,nperm=mynperm)
    
    c(myfit$Path[1:ngenes,ngenes+1],myfit$pvalues[1:ngenes,ngenes+1])
  }
  close(pb)
  closeAllConnections()
  #stopCluster(cl)
  
  myfitsummaryPT<-as.data.table(myfitsummaryPT)
  
  #data.table::fwrite(myfitsummaryPT, paste0("/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/May 2019/simulations_results/simulation_SLIC_LD_",cb,"_results.csv"), quote=FALSE, sep=",",row.names=FALSE)
  
  #write.table(myfitsummaryPT, paste0("/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/May 2019/simulations_results/simulation_SLIC_corrs500_",cb,"_results.csv"), sep=",",row.names=FALSE) 
  
  
  if(ngenes==1){gene_power<-length(which(myfitsummaryPT[,2]<.05))} else{gene_power<-apply(myfitsummaryPT[,(ngenes+1):(ngenes*2)],2,function(x2) length(which(x2<.05)))}
  
  gene_power2<-rep(NA,4)
  gene_power2[1:length(gene_power)]<-gene_power/nrun
  
  model_out_summary2<-c(nsnp,nsnpeff,ngenes,combos[cb,6],gene_power2,nrun,combos[cb,5],combos[cb,4],phenCorr)
  
  data.table::fwrite(as.data.table(t(model_out_summary2)), paste0("/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/May 2019/simulations_results/PT_simulation_results_June2019_SLIC_LD.csv"), quote=FALSE, sep=",",row.names=FALSE, col.names = FALSE)
  
  #write.table(t(model_out_summary2), file = paste0("/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/May 2019/simulations_results/PT_simulation_results_May2019_SLIC_corrs500.csv"), sep = ",", append = TRUE, quote = FALSE, col.names = FALSE, row.names = FALSE)
  
  return(model_out_summary2)
}

#We will simulate large datasets for 3 correlated phenotypes and 200 SNPs 
#We can then sample from the saved data when running simulations.


#----------------------------------------------------------------------------
# User specifies how many SNPs have effect on phenotype and how big an effect here
# These values are ignored if thisfile is 1 or 3 (no effect)
#nsnpeff<-5 #N snps exerting effect on phenotype
#gpcorr<-gpcov<-.4 # effect size correlation
#n2sim<-3 #N phenotypes
#ngenes<-1 # N genes
#nsub<-120 #N subjects - set to resemble our study
#----------------------------------------------------------------------------


combos<-expand.grid(nsnpeff=c(0,5,10),nsnp=c(20,40),ngenes=c(1),nsub=c(100),cluster=c(0),gpcorr=c(0.1,0.2,0.4),phenCorr=c(0,0.5,0.75))

for(cb in 1:length(combos[,1]))
{
  print(paste0("combo",cb))
  gsca_sim_multigene3(nsnp=combos[cb,2],nsnpeff=combos[cb,1],ngenes=combos[cb,3],nsub=combos[cb,4],ncases=10000,gpcorr=combos[cb,6],n2sim=3,plotter = TRUE,cb=cb,cluster=combos[cb,5],phenCorr = combos[cb,7])
  
}

#save.image()
#savehistory()

write.csv(combos,"/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/May 2019/simulations_results/combos.csv")




