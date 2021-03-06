library(Biobase)
library(GEOquery)
library(GEOmetadb)
library(limma)
library(jsonlite)
library(affy)
library(dplyr)

cargs<-commandArgs()
cargs<-cargs[(which(cargs=="--args")+1):length(cargs)]
nbargs=length(cargs)

cargs[[nbargs-13]]
cargs[nbargs-11]
cargs[[nbargs-2]]

load(cargs[[nbargs-13]])
targetFile=cargs[[nbargs-12]]
condition1Name=cargs[[nbargs-11]]
condition1=cargs[[nbargs-10]]
condition2Name=cargs[[nbargs-9]]
condition2=cargs[[nbargs-8]]
nbresult=cargs[[nbargs-7]]
result_export_eset=cargs[[nbargs-6]]
result=cargs[[nbargs-5]]
result.path=cargs[[nbargs-4]]
result.tabular=cargs[[nbargs-3]]
result.template=cargs[[nbargs-2]]

result.template
result.tabular

#file.copy(targetFile,"./targetFile.txt")

condition1_tmp <- strsplit(condition1,",")
condition1 <-unlist(condition1_tmp)

condition2_tmp <- strsplit(condition2,",")
condition2<-unlist(condition2_tmp)

conditions=c(condition1,condition2)

#nbresult=1000
dir.create(result.path, showWarnings = TRUE, recursive = FALSE)

targets <- read.table(targetFile,sep="\t")

eset=eset[,which(rownames(eset@phenoData@data) %in% conditions)]
#condition1Name=make.names(condition1Name)
#condition2Name=make.names(condition2Name)
#condition1Name=gsub("_","",condition1Name)
#condition2Name=gsub("_","",condition2Name)
#condition1Name
#condition2Name


eset@phenoData@data$source_name_ch1=""
eset@phenoData@data$source_name_ch1[which(rownames(eset@phenoData@data) %in% condition1)]=condition1Name
eset@phenoData@data$source_name_ch1[which(rownames(eset@phenoData@data) %in% condition2)]=condition2Name
#condition1Name
#condition2Name

condNames=paste0("G",as.numeric(as.character(pData(eset)["source_name_ch1"][,1])!=condition1Name))
#condNames=make.names(targets[,2])
#condNames=gsub("_","",condNames)

f <- as.factor(condNames)
f
#eset$description <- factors
design <- model.matrix(~ 0+f)
design

colnames(design) <- levels(f)
colnames(design)
fit <- lmFit(eset, design)
fit
#cont.matrix <- makeContrasts(C1=paste0(condition1Name,"-",condition2Name), levels=design)
cont.matrix <- makeContrasts(G0-G1, levels=design)
cont.matrix
fit2 <- contrasts.fit(fit, cont.matrix)
fit2 <- eBayes(fit2)
fit2
tT <- topTable(fit2, adjust="fdr", sort.by="B", number=nbresult)

#head(exprs(eset))

gpl <- annotation(eset)
if (substr(x = gpl,1,3)!="GPL"){
	#if the annotation info does not start with "GPL" we retrieve the correspondin GPL annotation
	mapping=read.csv("/galaxy-tools/transcriptomics/db/gplToBioc.csv",stringsAsFactors=FALSE)
	gpl=mapping[which(mapping$bioc_package==annotation(eset)),]$gpl
	gpl=gpl[1]
	
	annotation(eset)=gpl
	
	platf <- getGEO(gpl, AnnotGPL=TRUE)
	ncbifd <- data.frame(attr(dataTable(platf), "table"))
	
	fData(eset)["ID"]=row.names(fData(eset))
	fData(eset)=merge(x=fData(eset),y=ncbifd,all.x = TRUE, by = "ID")
	colnames(fData(eset))[4]="ENTREZ_GENE_ID"
	row.names(fData(eset))=fData(eset)[,"ID"]
	
	tT <- add_rownames(tT, "ID")
	
} else {
	
	gpl <- annotation(eset)
	platf <- getGEO(gpl, AnnotGPL=TRUE)
	ncbifd <- data.frame(attr(dataTable(platf), "table"))
	
	if (!("ID" %in% colnames(tT))){
		tT <- add_rownames(tT, "ID")}
	
}

tT <- merge(tT, ncbifd, by="ID")
tT <- tT[order(tT$P.Value), ] 
tT <- subset(tT, select=c("Platform_SPOTID","ID","adj.P.Val","P.Value","t","B","logFC","Gene.symbol","Gene.title","Gene.ID","Chromosome.annotation","GO.Function.ID"))
tT<-format(tT, digits=2, nsmall=2)
head(tT)
colnames(tT)=gsub(pattern = "\\.",replacement = "_",colnames(tT))
matrixtT=as.matrix(tT)
datajson=toJSON(matrixtT,pretty = TRUE)

htmlfile=readChar(result.template, file.info(result.template)$size)
htmlfile=gsub(x=htmlfile,pattern = "###DATAJSON###",replacement = datajson, fixed = TRUE)
dir.create(result.path, showWarnings = TRUE, recursive = FALSE)

boxplot="boxplot.png"
png(boxplot,width=800,height = 400)
par(mar=c(7,5,1,1))
boxplot(exprs(eset),las=2,outline=FALSE)
dev.off()
htmlfile=gsub(x=htmlfile,pattern = "###BOXPLOT###",replacement = boxplot, fixed = TRUE)
file.copy(boxplot,result.path)

histopvalue="histopvalue.png"

png(histopvalue,width=800,height = 400)
par(mfrow=c(1,2))
hist(fit2$F.p.value,nclass=100,main="Histogram of p-values", xlab="p-values",ylab="frequency")
volcanoplot(fit2,coef=1,highlight=10,main="Volcano plot")
htmlfile=gsub(x=htmlfile,pattern = "###HIST###",replacement = histopvalue, fixed = TRUE)
dev.off()
file.copy(histopvalue,result.path)

#write.table(tolower(c(condition1Name,condition2Name)),quote = FALSE,col.names = FALSE, row.names=FALSE,file=result_export_conditions)
saveConditions=c(condition1Name,condition2Name)
save(eset,saveConditions,file=result_export_eset)
write.table(x=tT[,-1],file=result.tabular,quote=FALSE,row.names=FALSE,col.names=TRUE,sep="\t")
write(htmlfile,result)

