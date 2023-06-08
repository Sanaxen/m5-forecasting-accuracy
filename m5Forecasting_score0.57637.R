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

#ユーティリティー関数
freeram <- function(...) invisible(gc(...))

#1913日間(訓練データ)の売り上げ情報(製品および店舗ごとの日次販売台数データ)
#製品および店舗ごとの過去の日次販売台数データが??含まれています。
#
#item_id: 商品の ID。
#dept_id: 製品が属する部門の ID。
#cat_id: 商品が属するカテゴリの ID。
#store_id: 商品が販売されているストアの ID。
#state_id: 店舗がある州。
#d_1, d_2, …, d_i, … d_1941: 2011 年 1 月 29 日から始まる i 日目に販売されたユニット数。

#2011/01/29 to 2016/04/24
#train <- fread("./m5-forecasting-accuracy/sales_train_validation.csv", na.strings=c("", "NULL"), header = TRUE, stringsAsFactors = TRUE)

#締め切りの1か月前に配布された
#2011/01/29 to 2016/05/22
train <- fread("./m5-forecasting-accuracy/sales_train_evaluation.csv", na.strings=c("", "NULL"), header = TRUE, stringsAsFactors = TRUE)


#2011/01/29 ~ 2016/06/19 までの1969日間のカレンダー情報
#商品の販売日に関する情報が含まれています。
#
#date: 「ymd」形式の日付。
#wm_yr_wk: 日付が属する週の ID。
#weekday: 曜日のタイプ (土曜日、日曜日、…、金曜日)。
#wday: 土曜日から始まる平日の ID。
#month: 日付の月。
#year: 日付の年。
#event_name_1: 日付にイベントが含まれる場合、このイベントの名前。
#event_type_1: 日付にイベントが含まれる場合、このイベントのタイプ。
#event_name_2: 日付に 2 番目のイベントが含まれる場合、このイベントの名前。
#event_type_2: 日付に 2 番目のイベントが含まれる場合、このイベントのタイプ。
#snap_CA、snap_TX、およびsnap_WI: CA、TX、またはWIのストアが調査日にSNAP購入を許可するかどうかを示すバイナリ変数(0または1)。1 は、SNAP 購入が許可されていることを示します。

calendar <- fread("./m5-forecasting-accuracy/calendar.csv", na.strings=c("", "NULL"), header = TRUE, stringsAsFactors = TRUE)

#店別、商品別、週別の商品売価
#店舗ごとの販売商品の価格と日付に関する情報が含まれています。
#
#store_id: 商品が販売されているストアの ID。
#item_id: 商品の ID。
#wm_yr_wk: 週の ID。
#Sell_price: 特定の週/店舗の商品の価格。価格は 1 週間あたり (7 日間の平均) です。
#            利用できない場合、これは、調査した週に製品が販売されなかったことを意味します。
#            価格は週単位では一定ですが、時間の経過とともに変化する可能性があることに注意してください 
#            (トレーニング セットとテスト セットの両方)。

prices <- fread("./m5-forecasting-accuracy/sell_prices.csv", na.strings=c("", "NULL"), header = TRUE, stringsAsFactors = TRUE)

#提出用d_1941
#stage1: d_1914(2016/04/25) ~ d_1941(2016/05/22)
#stage2: d_1942(2016/05/23) ~ d_1969(2016/06/19)
submission = fread('./m5-forecasting-accuracy/sample_submission.csv')


stage2_date <- seq(as.Date("2016-05-23"), as.Date("2016-06-19"), by = "day")

#stage2予測用の28日分を追加
tmp <- train
for (n in 1:28) {
  column_name = sprintf('d_%d',1941+n, sep = "")
  tmp = tmp %>% mutate(!!column_name := 0)
}
head(tmp)
str(tmp)
train <- tmp

rm(tmp)
freeram()

prices[, c('sell_price')] <- sapply(prices[, c('sell_price')], as.numeric)
calendar$date <- as.Date(calendar$date)
freeram()


calendar$date<-as.Date(calendar$date)
calendar$event_type_1<- as.character(calendar$event_type_1)
calendar$event_type_2<- as.character(calendar$event_type_2)
calendar$event_name_1<- as.character(calendar$event_name_1)
calendar$event_name_2<- as.character(calendar$event_name_2)

calendar <- calendar %>%
            mutate(event_type_1 = replace(event_type_1, is.na(event_type_1), "None"))%>%
            mutate(event_type_2 = replace(event_type_2, is.na(event_type_2), "None"))%>%
            mutate(event_name_1 = replace(event_name_1, is.na(event_name_1), "None"))%>%
            mutate(event_name_2 = replace(event_name_2, is.na(event_name_2), "None"))

## Reverting class of the event_type_1 into factor
calendar$event_type_1 <- as.factor(calendar$event_type_1)
calendar$event_type_2 <- as.factor(calendar$event_type_2)
calendar$event_name_1 <- as.factor(calendar$event_name_1)
calendar$event_name_2 <- as.factor(calendar$event_name_2)
freeram()


head(calendar,10)


train <- reshape2::melt(train,id.vars = c("id", "item_id", "dept_id", "cat_id", "store_id", "state_id"),
                 variable.name = "day", 
                 value.name = "Unit_Sales") 
freeram()

data <- left_join(train, calendar,
                   by = c("day" = "d"))
rm(train)
rm(calendar)
freeram()
#write.csv(data,'m5-forecasting-accuracy_dataset_stage2.csv',row.names=FALSE)

freeram()

data <- data %>%
            left_join(prices, 
                      by = c("store_id" = "store_id",
                             "item_id" = "item_id",
                             "wm_yr_wk" = "wm_yr_wk"))



if ( T )
{
	data <- data %>%
	            group_by(id) %>%
	            mutate(
	                   week1 = dplyr::lag(Unit_Sales, n = 7),
	                   week2 = dplyr::lag(Unit_Sales, n = 14),
	                   month1 = dplyr::lag(Unit_Sales, n = 28),
	                   month2 = dplyr::lag(Unit_Sales, n = 60),

	                   week_roll_mean=roll_meanr(week1,7),
	                   week_roll_sd=roll_sdr(week1,7),

	                   month1_roll_mean=roll_meanr(month1,28),
	                   month1_roll_sd=roll_sdr(month1,28),

	                   month2_roll_mean=roll_meanr(month2,60),
	                   month2_roll_sd=roll_sdr(month2,60),

	                   month1_roll_min=roll_maxr(month1,28),
	                   month1_roll_max=roll_maxr(month1,28),
	                   month2_roll_min=roll_maxr(month2,60),
	                   month2_roll_max=roll_maxr(month2,60)) %>%
	 ungroup()
}
freeram()

data[is.na(data)] <- 0

category<-c('id','item_id','dept_id','cat_id','store_id','state_id',
            'day','weekday', 'event_name_1', 'event_name_2', 'event_type_1', 'event_type_2')

rm(prices)
freeram()
# ====================================================================================================




data[,category]<-data[,category]%>%mutate_if(is.character,as.factor)


train_data <- data %>%
                    filter(date <= as.Date('2016-04-24')) %>%
                    select(-Unit_Sales)

train_labels <- data %>%
                    filter(date <= as.Date('2016-04-24')) %>%
                    select(Unit_Sales)

test_data <- data %>%
                    filter(date > as.Date('2016-04-24') &
                           (date <= as.Date('2016-05-22'))) %>%
                    select(-Unit_Sales)

test_labels <- data %>%
                    filter((date > as.Date('2016-04-24')) &
                           (date <= as.Date('2016-05-22'))) %>%
                    select(Unit_Sales)
unique(test_data$date)
length(unique(test_data$date))


stage1 = data %>% filter(date > as.Date('2016-04-24')  &
                           (date <= as.Date('2016-05-22')))         
stage1$id <- gsub("evaluation", "validation", stage1$id)

stage1_data =  stage1 %>% filter(date > as.Date('2016-04-24')) %>% select(-Unit_Sales)
stage1_labels =  stage1 %>% filter(date > as.Date('2016-04-24')) %>% select(Unit_Sales)
unique(stage1_data$date)
length(unique(stage1_data$date))

stage2 = data %>% filter(date > as.Date('2016-05-22'))          
stage2$id <- gsub("validation", "evaluation", stage2$id)

stage2_data =  stage2 %>% filter(date > as.Date('2016-05-22')) %>% select(-Unit_Sales)
stage2_labels =  stage2 %>% filter(date > as.Date('2016-05-22')) %>% select(Unit_Sales)

unique(stage2_data$date)
length(unique(stage2_data$date))

rm(data)
freeram()


head(train_data)
train_data  = as.data.frame(train_data)
train_labels= as.data.frame(train_labels)
test_data   = as.data.frame(test_data)
test_labels = as.data.frame(test_labels)

stage1_data = as.data.frame(stage1_data)
stage1_labels=as.data.frame(stage1_labels)
stage2_data = as.data.frame(stage2_data)
stage2_labels=as.data.frame(stage2_labels)

freeram()

use_features = c(
    "item_id",
    "dept_id",
    "cat_id",
    "store_id",
    "state_id",
    "day",
    "weekday",
    "month",
    "year",
    "event_name_1",
    "event_type_1",
    "event_name_2",
    "event_type_2",
    "snap_CA",
    "snap_TX",
    "snap_WI",
    "sell_price" ,
#    "week1",
#    "week2",
#    "week_roll_mean",
#    "week_roll_sd",
    "month1",
    "month2",
    "month1_roll_mean",
    "month1_roll_sd",
    "month2_roll_mean",
    "month2_roll_sd"#,
    #"month1_roll_min",
    #"month1_roll_max"#,
    #"month2_roll_min",
    #"month2_roll_max"
    )

train_set_xgb = xgb.DMatrix(data = data.matrix(train_data[,use_features]), label = data.matrix(train_labels))
test_set_xgb = xgb.DMatrix(data = data.matrix(test_data[,use_features]), label = data.matrix(test_labels))

use_GPU = F
eta = 0.02
min_child_weight = 1
gamma = 0
max_depth=7
if ( use_GPU )
{
	params <- list(booster = "gbtree",
                   min_child_weight = min_child_weight,
	               #tree_method='hist',
	               #tree_method='auto',
	               tree_method='gpu_hist', gpu_id=0,task_type = "GPU",
	               objective = "reg:tweedie"
	               ,eta=eta, gamma=gamma, max_depth=max_depth)
}else
{
	params <- list(booster = "gbtree",
                   min_child_weight = min_child_weight,
	               tree_method='hist',
	               #tree_method='auto',
#                  tree_method='gpu_hist', gpu_id=0,task_type = "GPU",
	               objective = "reg:tweedie"
	               ,eta=eta, gamma=gamma, max_depth=max_depth)
}

freeram()

nrounds = 1500

#[3160]  train-rmse:2.291926     eval-rmse:2.209713
#Stopping. Best iteration:
#[2160]  train-rmse:2.331883     eval-rmse:2.192606 score 0.58798
#[2109]  train-rmse:2.279307     eval-rmse:2.202744
#Stopping. Best iteration:
#[1109]  train-rmse:2.358817     eval-rmse:2.199393 eta=0.02 score 0.58285
#
#[5601]  train-rmse:2.244917     eval-rmse:2.192229 eta = 0.01 score 0.5892
#Stopping. Best iteration:
#[4601]  train-rmse:2.266502     eval-rmse:2.191481
#
#[5315]  train-rmse:2.235507     eval-rmse:2.216882 score 0.59148
#Stopping. Best iteration:
#[2315]  train-rmse:2.317856     eval-rmse:2.188798
#
#[4983]  train-rmse:2.177230     eval-rmse:2.231844 score 0.57905
#Stopping. Best iteration:
#[1983]  train-rmse:2.281444     eval-rmse:2.188189
#
#[3983]  train-rmse:2.201262     eval-rmse:2.228904 score 0.57905
#Stopping. Best iteration:
#[1983]  train-rmse:2.281444     eval-rmse:2.188189
#
#[4482]  train-rmse:2.258301     eval-rmse:2.211731 score 0.57637
#Stopping. Best iteration:
#[2482]  train-rmse:2.318164     eval-rmse:2.193691

num_iterations = 10000

#xgb_cv <- xgb.cv(data = train_set_xgb
#                  , param = params,
#                  , maximize = FALSE, evaluation = "rmse", nrounds = nrounds
#                  , nthreads = 2, nfold = 5, early_stopping_round = 60)
#num_iterations = xgb_cv$best_iteration

#xgb.DMatrix.save(train_set_xgb, "train_set_xgb")
#xgb.DMatrix.save(test_set_xgb, "test_set_xgb")
#train_set_xgb <- xgb.DMatrix("train_set_xgb")
#test_set_xgb <- xgb.DMatrix("test_set_xgb")

model_xgb <- xgb.train(data = train_set_xgb,
                              , param = params
                               , maximize = FALSE, eval.metric = 'rmse', nrounds = num_iterations
                               ,watchlist = list(train = train_set_xgb, eval = test_set_xgb)
                               , early_stopping_round = 2000
                               )

saveRDS(model_xgb, file = "model_xgb")
#model_xgb <- readRDS("model_xgb")

freeram()
importance <- xgb.importance(feature_names = colnames(train_set_xgb), model = model_xgb)
importancePlt<-xgb.plot.importance(importance_matrix = importance)
#importancePlt
#ggsave(file = "importance.png", plot = g19, dpi = 100, width = 6.4, height = 4.8)

test_pred = predict(model_xgb,test_set_xgb)


#x <- stage1_data
#y <- stage1_labels
x <- stage2_data
y <- stage2_labels
xgb = xgb.DMatrix(data = data.matrix(x[,use_features]), label = data.matrix(y))
#xgb.DMatrix.save(xgb, "xgb")
#xgb <- xgb.DMatrix("xgb")

y_pred = predict(model_xgb,xgb)

#stage2
stage2[,'Unit_Sales'] = y_pred
predictions = stage2[,c('id', 'date', 'Unit_Sales')]
predictions = reshape2::dcast(predictions, id~date, value.var = 'Unit_Sales')
colnames(predictions) = c('id',paste('F',1:28,sep=""))

unique(stage2[,c('id', 'date', 'Unit_Sales')]$date)
#length(unique(stage2[,c('id', 'date', 'Unit_Sales')]$date))

#stage1
#stage1[,'Unit_Sales'] = y_pred
predictions_stg1 = stage1[,c('id', 'date', 'Unit_Sales')]
predictions_stg1 = reshape2::dcast(predictions_stg1, id~date, value.var = 'Unit_Sales')
colnames(predictions_stg1) = c('id',paste('F',1:28,sep=""))

predictions_stg1 <- predictions_stg1 %>% select(c('id', 'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 
									'F8', 'F9', 'F10', 'F11', 'F12',
									'F13', 'F14', 'F15', 'F16', 'F17',
									'F18', 'F19', 'F20', 'F21', 'F22',
									'F23', 'F24', 'F25', 'F26', 'F27','F28'))

#predictions$id <- gsub("evaluation", "validation", predictions$id)
print(nrow(predictions_stg1))
predictions_stg1[is.na(predictions_stg1)] <- 0
unique(stage1[,c('id', 'date', 'Unit_Sales')]$date)
#length(unique(stage2[,c('id', 'date', 'Unit_Sales')]$date))

#n = nrow(submission) - nrow(predictions)

stage1_submission <- predictions_stg1
stage2_submission <- rbind(stage1_submission, predictions)

print(nrow(stage1_submission))
print(nrow(submission))
#write.csv(stage1_submission,'submission.csv',row.names=FALSE)
write.csv(stage2_submission,'submission.csv',row.names=FALSE)

#q()

