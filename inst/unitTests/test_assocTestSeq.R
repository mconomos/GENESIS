library(SeqVarTools)
library(Biobase)
library(SNPRelate)
library(logistf)

.testObject <- function(){
    gdsfmt::showfile.gds(closeall=TRUE, verbose=FALSE)
    
    gdsfile <- seqExampleFileName("gds")
    gds.seq <- seqOpen(gdsfile)
    
    data(pedigree)
    pedigree <- pedigree[match(seqGetData(gds.seq, "sample.id"), pedigree$sample.id),]
    pedigree$outcome <- rnorm(nrow(pedigree))
    pedigree$status <- rbinom(nrow(pedigree), 1, 0.4)
    
    SeqVarData(gds.seq, sampleData=AnnotatedDataFrame(pedigree))
}

.testKing <- function(gds){
    ibd <- snpgdsIBDKING(gds, verbose=FALSE)
    kc <- ibd$kinship
    rownames(kc) <- ibd$sample.id
    colnames(kc) <- ibd$sample.id
    kc
}

.testGRM <- function(seqData, ...){
    kinship <- .testKing(seqData)
    mypcair <- pcair(seqData, kinMat=kinship, divMat=kinship, verbose=FALSE, ...)
    mypcrel <- pcrelate(seqData, pcMat=mypcair$vectors[,1:2], training.set=mypcair$unrels, verbose=FALSE, ...)
    pcrelateMakeGRM(mypcrel)
}

.testNullModel <- function(seqData, type="mixed", binary=FALSE, ...){
    scanData <- sampleData(seqData)
    if (binary) {
        outcome <- "status"
        family <- binomial
    } else {
        outcome <- "outcome"
        family <- gaussian
    }

    if (type == "mixed") {
        grm <- .testGRM(seqData, ...)
        fitNullMM(scanData, outcome=outcome, covars="sex", covMatList=grm, family=family, verbose=FALSE, ...)
    } else {
        fitNullReg(scanData, outcome=outcome, covars="sex", family=family, verbose=FALSE, ...)
    }
}

.testBurden <- function(seqData) {
    rowSums(altDosage(seqData), na.rm=TRUE)
}


test_projection_mm <- function(){
    seqData <- .testObject()

    nullmod <- .testNullModel(seqData, type="mixed")
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test="Score")
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test="Wald")
    proj <- GENESIS:::.calculateProjection(nullmod, test="SKAT", burden.test=NULL)

    seqClose(seqData)
}

test_projection_reg <- function(){
    seqData <- .testObject()

    nullmod <- .testNullModel(seqData, type="reg")
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test="Score")
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test="Wald")
    proj <- GENESIS:::.calculateProjection(nullmod, test="SKAT", burden.test="")

    seqClose(seqData)
}

test_projection_logistic <- function(){
    seqData <- .testObject()

    nullmod <- .testNullModel(seqData, type="reg", binary=TRUE)
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test="Score")
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test="Wald")
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test="Firth")
    proj <- GENESIS:::.calculateProjection(nullmod, test="SKAT", burden.test="")

    seqClose(seqData)
}

# fails unpredictably
## test_projection_gmmat <- function(){
##     seqData <- .testObject()

##     nullmod <- .testNullModel(seqData, type="mixed", binary=TRUE)
##     proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test="Score")
##     proj <- GENESIS:::.calculateProjection(nullmod, test="SKAT", burden.test="")

##     seqClose(seqData)
## }

test_burden_score <- function(){
    seqData <- .testObject()
    burden <- .testBurden(seqData)

    burden.test <- "Score"
    nullmod <- .testNullModel(seqData, type="reg")
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test=burden.test)
    bt <- GENESIS:::.runBurdenTest(burden, proj, burden.test=burden.test)

    seqClose(seqData)
}

test_burden_wald <- function(){
    seqData <- .testObject()
    burden <- .testBurden(seqData)

    burden.test <- "Wald"
    nullmod <- .testNullModel(seqData, type="reg")
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test=burden.test)
    bt <- GENESIS:::.runBurdenTest(burden, proj, burden.test=burden.test)

    dat <- cbind(pData(sampleData(seqData)), burden)
    mod <- lm("outcome ~ sex + burden", data=dat)
    chk <- coef(summary(mod))["burden", c("Estimate", "Std. Error")]
    checkEquals(chk, bt[c("Est", "SE")], checkNames=FALSE)

    seqClose(seqData)
}

test_burden_wald_bin <- function(){
    seqData <- .testObject()
    burden <- .testBurden(seqData)

    burden.test <- "Wald"
    nullmod <- .testNullModel(seqData, type="reg", binary=TRUE)
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test=burden.test)
    bt <- GENESIS:::.runBurdenTest(burden, proj, burden.test=burden.test)

    dat <- cbind(pData(sampleData(seqData)), burden)
    mod <- glm("status ~ sex + burden", data=dat, family=binomial)
    chk <- coef(summary(mod))["burden", c("Estimate", "Std. Error")]
    checkEquals(chk, bt[c("Est", "SE")], checkNames=FALSE)

    seqClose(seqData)
}

test_burden_firth <- function(){
    seqData <- .testObject()
    burden <- .testBurden(seqData)

    burden.test <- "Firth"
    nullmod <- .testNullModel(seqData, type="reg", binary=TRUE)
    proj <- GENESIS:::.calculateProjection(nullmod, test="Burden", burden.test=burden.test)
    bt <- GENESIS:::.runBurdenTest(burden, proj, burden.test=burden.test)

    dat <- cbind(pData(sampleData(seqData)), burden)
    mod <- logistf(as.formula("status ~ sex + burden"), data=dat)
    checkEquals(coef(mod)["burden"], bt["Est"], checkNames=FALSE)
    
    seqClose(seqData)
}