#https://www.kaggle.com/competitions/m5-forecasting-accuracy/
#5,558 teams
org_libpath <- .libPaths()

curdir <- getwd()
install_libpath <- paste(curdir, "/lib", sep="")

.libPaths( c(install_libpath, org_libpath))

#install.packages("sqldf", repo="http://cran.r-project.org", lib=install_libpath) 
#install.packages("splitstackshape", repo="http://cran.r-project.org", lib=install_libpath) 
#install.packages("skimr", repo="http://cran.r-project.org", lib=install_libpath) 
#install.packages("RcppRoll", repo="http://cran.r-project.org", lib=install_libpath) 
#install.packages("timetk", repo="http://cran.r-project.org", lib=install_libpath) 
#install.packages("ggthemes", repo="http://cran.r-project.org", lib=install_libpath) 
#install.packages("dplyr", repo="http://cran.r-project.org", lib=install_libpath) 

suppressMessages({
    library(data.table)
    library(RcppRoll)
#    library(lightgbm)
    library(dplyr)
    library(lubridate)
    library(reshape2)
    library(Matrix)
    library(xgboost)
    library(tidyverse)
    library(scales)
    library(skimr)
    library(tibble)
    library(tidyr) 
    library(stringr)  
    library(ggthemes)
    library(ggpubr)
    library(timetk)
})

#https://github.com/kuto5046/kaggle-M5-accuracy
#ユーティリティー関数
freeram <- function(...) invisible(gc(...))

submission = fread('submission_.csv')
submission <- as.data.frame(submission)
submission[30491:nrow(submission),2:ncol(submission)]<-submission[30491:nrow(submission),2:ncol(submission)]*0.995


write.csv(submission,'submission.csv',row.names=FALSE)
