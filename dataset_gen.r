#https://www.kaggle.com/competitions/m5-forecasting-accuracy/
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
#head(tmp)
#str(tmp)
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


#head(calendar,10)


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



data <- data %>%
            left_join(prices, 
                      by = c("store_id" = "store_id",
                             "item_id" = "item_id",
                             "wm_yr_wk" = "wm_yr_wk"))

#rm(prices)
#freeram()

if ( T )
{
	data <- data %>%
	            group_by(id) %>%
	            mutate(
	                   month1 = dplyr::lag(Unit_Sales, n = 28),
	                   month2 = dplyr::lag(Unit_Sales, n = 60),
	                   month1_roll_mean=roll_meanr(month1,28),
	                   month1_roll_sd=roll_sdr(month1,28),

	                   two_month2_roll_mean=roll_meanr(month2,60),
	                   two_month2_roll_sd=roll_sdr(month2,60)) %>%
	 ungroup()
}
freeram()
data[is.na(data)] <- 0

train_data <- data %>% filter(date <= as.Date('2016-04-24')) 
test_data <- data %>%  filter(date > as.Date('2016-04-24') & (date <= as.Date('2016-05-22')))
stage2 = data %>% filter(date > as.Date('2016-05-22'))          
stage2$id <- gsub("validation", "evaluation", stage2$id)


write.csv(train_data,'m5-forecasting-accuracy_dataset_train_(2011-01-29--2016-04-24).csv',row.names=FALSE)
write.csv(test_data,'m5-forecasting-accuracy_dataset_test_(2016-04-25--2016-05-22).csv',row.names=FALSE)
write.csv(stage2,'m5-forecasting-accuracy_dataset_stage2_(2016-05-23--2016-06-19).csv',row.names=FALSE)

concat <- rbind(train_data, test_data)
write.csv(concat,'m5-forecasting-accuracy_dataset_concat(2011-01-29--2016-05-22).csv',row.names=FALSE)

quit()

#write.csv(data,'m5-forecasting-accuracy_dataset2.csv',row.names=FALSE)

#店舗毎にファイルを分割
IDs = unique(data$store_id)
for ( ID in 1:length(IDs))
{
	z <- data %>% filter(store_id == IDs[ID] )

	if ( is.null(z)) next
	if ( nrow(z) == 0 )next

	zz <- submission %>% filter(id == z$id[1])
	if ( is.null(zz)) next
	if ( nrow(z) == 0 )next

	write.csv(z,sprintf('dataset_store_id/m5-forecasting-accuracy_dataset_%s.csv', IDs[ID]),row.names=FALSE)
	rm(z)
	freeram()
	print(sprintf("%d/%d", ID, length(IDs)))
	flush.console()
}

quit()

#ID毎にファイルを分割
IDs = unique(data$id)
for ( ID in 1:length(IDs))
{
	z <- data %>% filter(id == IDs[ID] )

	if ( is.null(z)) next
	if ( nrow(z) == 0 )next

	zz <- submission %>% filter(id == z$id[1])
	if ( is.null(zz)) next
	if ( nrow(z) == 0 )next

	write.csv(z,sprintf('dataset/m5-forecasting-accuracy_dataset_%s.csv', IDs[ID]),row.names=FALSE)
	rm(z)
	freeram()
	print(sprintf("%d/%d", ID, length(IDs)))
	flush.console()
}
