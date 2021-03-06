#simulate genotype-phenotype data

# 2nd July 2018 - Paul T
#edit - June2019 - Paul T
#edit - July2019 - Paul T

#-------------------------------------------------------------------------#

#Aim: start by using GSCA approach and see if it captures the associations

#-------------------------------------------------------------------------#
require(doBy)
library(tidyr)
require(tidyverse)
require(MASS)
require(stats)
library(doSNOW)
library(foreach)
library(ASGSCA)
library(matrixcalc)

#-------------------------------------------------------------------------#

options(scipen = 999) #turn off scientific notation


#-------------------------------------------------------------------------#

gsca_sim_multigene3<-function(nsnp,nsnpeff,ngenes=1,nsub=120,ncases=100000,gpcorr=0.1,n2sim=3,plotter=TRUE,cb=cb,cluster=cluster,phenCorr=phenCorr)
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
  
  mymean<-rep(0,h) #vector of means to use in mvrnorm function
  mycorr<-0 #default is uncorrelated
  mycov2<-matrix(mycorr,nrow=h,ncol=h) #cov matrix for mvrnorm
  
  diag(mycov2)<-rep(1,h) #ones on diagonal of cov matrix
  
  MyRandCorrMat<-function(h=nsnp)
  {
    #R <- matrix(rbeta(h^2,2,2.5), ncol=h) 
    R <- matrix(rbeta(h^2,.23,1.23), ncol=h) 
    R <- (R * lower.tri(R)) + t(R * lower.tri(R)) 
    diag(R) <- 1
    return(R)
  }
  
  mycov2 <- MyRandCorrMat(nsnp)
  
  
  #-------------------------------------------------------------------------#
  
  mycov_PT<-matrix(mycorr,nrow=nsnp+n2sim,ncol=nsnp+n2sim)
  mycov_PT[1:nsnp,1:nsnp]<-mycov2
  m<-diag(n2sim)
  pheno_mat<-m[lower.tri(m)|upper.tri(m)]<-phenCorr
  mycov_PT[(nsnp+1):(nsnp+n2sim),(nsnp+1):(nsnp+n2sim)]<-pheno_mat
  
  #-------------------------------------------------------------------------#
  for(j in (nsnp+1):(nsnp+n2sim))
  {
    if(!nsnpeff==0){
      if(cluster==0){snpeff_pos<-sample(1:nsnp,nsnpeff,replace=F)} else {snpeff_pos<-c((nsnp-(nsnpeff-1)):nsnp)}
      
      mycov_PT[snpeff_pos,j] <- gpcov#*ifelse(rbinom(1,1,c(0.5,0.5))==1,-1,1)
      mycov_PT[j,snpeff_pos] <- t(mycov_PT[snpeff_pos,j])
    }
  }
  mycov<-mycov_PT
  
  #-------------------------------------------------------------------------#
  
  for(i in 1:nsnp)
  {
    for(j in 1:nsnp)
    {
      mycov[i,j] <- ifelse(rbinom(1,1,prob=0.5)==1,mycov[i,j],(-1*mycov[i,j]))
    }
  }
  
  for(i in (nsnp+1):(nsnp+n2sim))
  {
    for(j in 1:nsnp)
    {
      mycov[i,j] <- ifelse(rbinom(1,1,prob=0.5)==1,mycov[i,j],(-1*mycov[i,j]))
      mycov[j,i] <- ifelse(rbinom(1,1,prob=0.5)==1,mycov[j,i],(-1*mycov[j,i]))
    }
  }

  
  mycov[upper.tri(mycov)] <- t(mycov)[upper.tri(mycov)]
  
  diag(mycov)<-rep(1,dim(mycov)[1])
  
  #-------------------------------------------------------------------------#
  
  #then set diagonal values to 1 for all
  #diag(mycov)<-rep(1,n2sim)
  if(matrixcalc::is.positive.definite(mycov)==FALSE)
  {mycov<-Matrix::nearPD(mycov,keepDiag=TRUE)$mat}
  
  mymean<-rep(0,dim(mycov)[1])
  mydata=mvrnorm(n = ncases, mymean, mycov)
  
  mydata<-as.data.frame(mydata)
  
  colnames(mydata)[1:nsnp]<-snpnames
  colnames(mydata)[(nsnp+1):(nsnp+3)]<-c('NwdRepPheno','LangPheno','NeurodevPheno')
  
  #-------------------------------------------------------------------------#
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
  
  
  #----------------------------------------------------------------------#
  if(plotter==TRUE){
    library(tidyr)
    
    cor.data<-as.matrix(myr)
    cor.data[lower.tri(cor.data)] <- NA
    
    cor_tri_N <- as.data.frame(cor.data) %>% 
      mutate(Var1 = factor(row.names(.), levels=row.names(.))) %>% 
      gather(key = Var2, value = value, -Var1, na.rm = TRUE, factor_key = TRUE) 
    
    
    g1<-ggplot(data = cor_tri_N, aes(Var2, Var1, fill = value)) + 
      geom_tile()+scale_fill_gradient2(low = "blue",mid="white", high = "red")+theme_bw()+ theme(axis.text.x = element_text(angle = 90, hjust = 1),panel.grid.major = element_blank(), panel.grid.minor = element_blank(),axis.title = element_blank(),legend.title=element_blank(),text=element_text(size=14))+geom_hline(yintercept = (nsnp+0.5),colour="grey")+geom_vline(xintercept = (nsnp+0.5),colour="grey")
    
    print(g1)
    ggsave(paste0("/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/July2019/Corr_plots/plot_Random_LD_pheno_PT_random_pattern_SNPs",cb,".pdf"))
    
  }
 #stop() 
  #----------------------------------------------------------------------#
  # For each of nrun runs take a sample and analyse
  #----------------------------------------------------------------------#
  nrun <- 100 #N runs to simulate
  
  mybigdata<-mydata
  
  ###########################################################################
  # Parallel processed loop
  ###########################################################################
  
  cl <- makeSOCKcluster(4)
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
 
  
  #write.table(myfitsummaryPT, paste0("/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/May 2019/simulations_results/simulation_June2019_const_LD_pheno_PT_",cb,"_results.csv"), sep=",",row.names=FALSE) 
  
  
  if(ngenes==1){gene_power<-length(which(myfitsummaryPT[,2]<.05))} else{gene_power<-apply(myfitsummaryPT[,(ngenes+1):(ngenes*2)],2,function(x2) length(which(x2<.05)))}
  
  gene_power2<-rep(NA,4)
  gene_power2[1:length(gene_power)]<-(gene_power/nrun)
  
  model_out_summary2<-c(nsnp,nsnpeff,ngenes,combos[cb,6],gene_power2,nrun,combos[cb,5],combos[cb,4],phenCorr)
  
  write.table(t(model_out_summary2), file = paste0("/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/July2019/simulations_results/Random_LD_pheno_random_pattern_negatives_01.csv"), sep = ",", append = TRUE, quote = FALSE, col.names = FALSE, row.names = FALSE)
  
  
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


combos <- expand.grid(nsnpeff=c(0, 5, 10), nsnp=c(20, 40), ngenes=1, nsub=100,cluster=0, gpcorr=c(0.1,0.15,0.2),phenocorr=c(0,0.5,0.75))

for(cb in 1:length(combos[,1]))
{
  print(paste0("combo",cb))
  gsca_sim_multigene3(nsnp=combos[cb,2],nsnpeff=combos[cb,1],ngenes=combos[cb,3],nsub=combos[cb,4],ncases=10000,gpcorr=combos[cb,6],n2sim=3,plotter = TRUE,cb=cb,cluster=combos[cb,5],phenCorr = combos[cb,7])
  
}

write.csv(combos,"/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/July2019/simulations_results/combos.csv")

#------------------------------------------------------------------------------------------------------------------------------------------#
#Random LD, random allocation phenotype correlation, and allocation is allowed to be negative and different for each phenotype association.

mypath <- "/Users/paulthompson/Dropbox/project SCT analysis/GSCA validation/July2019/simulations_results/"

file.name <- "Random_LD_pheno_random_pattern_negatives_01.csv"

bigname <- paste0(mypath,file.name)


#Filenames specified here. We can just bolt these together, but we need to separate them according to LDbase value.
bigsummary<-read_csv(bigname)

#bigsummary$condition<-paste0("LD=",bigsummary$LD,", PhenCorr=",bigsummary$PhenoCorr)


my_summary_new<-function(bigsummary=bigsummary)
{
  by_N_neff_nsub <- bigsummary %>% group_by(nsub,cluster,Ngenes,Nsnp,Nsnpeff,effsize,PhenoCorr)
  #this means that when summarising, will group by these columns
  groupedsummary_new<-by_N_neff_nsub %>% summarise(power = mean(power))
  #groupedsummary_new$cond2<-c(1,2,1,2,3,4,3,4,5,6,5,6,7,8,7,8,9,10,9,10,
  #                        11,12,11,12,13,14,13,14,15,16,15,16,17,18,17,18,
  #                        19,20,19,20,21,22,21,22,23,24,23,24)
  groupedsummary_new$Nsnpeffplot<-groupedsummary_new$Nsnpeff+groupedsummary_new$Ngenes/100-.02
  groupedsummary_new$Nsnpfac<-as.factor(groupedsummary_new$Nsnp)
  groupedsummary_new$Ngenes<-as.factor(groupedsummary_new$Ngenes)
  groupedsummary_new$nsub<-as.factor(groupedsummary_new$nsub)
  groupedsummary_new$PhenoCorr<-as.factor(groupedsummary_new$PhenoCorr)
  groupedsummary_new$effsize<-as.factor(groupedsummary_new$effsize)
  levels(groupedsummary_new$effsize)<-c("r = .1","r = .15","r = .2")
  levels(groupedsummary_new$Nsnpfac)<-c("20 SNPs","40 SNPs")
  groupedsummary_new$power<-100*groupedsummary_new$power
  return(groupedsummary_new)
}

groupedsummary_new <- my_summary_new(bigsummary)

# The palette with black:
cbbPalette <- c("#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00")

# To use for line and point colors, add

tiff(paste0(mypath,"Random_LD_pheno_random_pattern_negatives_01_plot.tiff"),width=2400,height=2000,res = 400)
ggplot(groupedsummary_new,aes(x=Nsnpeffplot,y=power,colour=PhenoCorr))+geom_point()+geom_line()+facet_grid(Nsnpfac~effsize)+theme_bw()+theme(legend.position = "bottom")+ guides(colour = guide_legend(nrow = 1))+scale_colour_manual(values=cbbPalette)+ guides(colour=guide_legend(title="Phenotype intercorrelation"))+ylab("Power")+xlab("Number of SNPs with an effect")
dev.off()

#--------------------------------------------------------------------------------------------------#
