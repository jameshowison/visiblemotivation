#library(ggplot2)
library(RMySQL)
library(foreach)

#setwd("/Users/james/Documents/University/CMU/Projects/VisibleWorkMotivation/RegressionVersion")

# get the data
#config <- read.csv("/Users/james/Documents/University/CMU/Projects/VisibleWorkMotivation/RegressionVersion/VisibleMotivationRegression-userpass",stringsAsFactors=FALSE)
config <- read.csv("VisibleMotivationRegression-userpass",stringsAsFactors=FALSE)

# chose database connection
login <- config[2,]

conn <- dbConnect(MySQL(),user=login$username,password=login$password,dbname=login$database,host=login$host)

min1 = 60
min10 = 60 * 10
min30 = min1 * 30
hour = min1 * 60
two_hour = hour * 2
day =  hour * 24
approxmonth = day * 30
approxyear = day * 365

#durations <- c(min1, min10, min30, hour, two_hour, day)

#durations <- c(min10,min30)

durations <- c(day)

#all_counts <- data.frame()

discard <- foreach(duration = durations) %do% {

  print(paste(sep="","********Doing Duration: ",duration))
#  own_edits, lag_1_other_edits, lag_1_own_edits, all_wiki_period_total
  # excluding situations in which there's only one person on the watch_list and no other_edits (ie there's only one editor in the last six months!)
  period_counts <- dbGetQuery(conn,paste(sep="","SELECT *
      FROM page_period_counts_",duration))#," WHERE watch_list_size > 1"))
  # 72195
  
  data_summary <- summary(period_counts)
  print(data_summary)
  # dicotomize active vs inactive
  # so we're having self_active lag_1_self_active lag_1_other_active
  period_counts$self_active <- ifelse(period_counts$own_edits > 0, 1, 0)
  period_counts$lag_1_self_active <- ifelse(period_counts$lag_1_own_edits > 0, 1, 0)
  period_counts$lag_1_other_active <- ifelse(period_counts$lag_1_other_edits > 0, 1, 0)
  
  
  mylogit <- glm(self_active~lag_1_self_active + lag_1_other_active + all_wiki_period_total,data=period_counts, family=binomial(link="logit"), na.action=na.pass)

  print(summary(mylogit))

  # odds ratio (one unit increase)
  print(exp(mylogit$coefficients))
  
#  all_counts <- rbind(all_counts,period_counts)
 # period_countsM <- melt(period_counts,id=1:3)  
 # plot(corr(period_counts))
  
  #convert to 'long' format, makes ggplot easier
  # period_counts_m <- melt(period_counts,id=1:3)
  # p <- ggplot(period_counts_m,aes(x=value))
  # p + geom_histogram(binwidth=1) + facet_grid(.~variable)
  # p + geom_histogram(binwidth=1) + scale_y_log10() + facet_grid(.~variable)
  #   
  # # run the regression
  # model <- lm(own_edits ~ lag_1_other_edits + lag_1_own_edits + all_wiki_period_total,period_counts)
  # print(summary(model))
  # 
  # period_counts_m <- melt(period_counts,id=1:3)
  # p <- ggplot(period_counts_m,aes(x=value))
  # #p + geom_histogram(binwidth=1) + facet_grid(.~variable)
  # p <- p + geom_histogram(binwidth=1) + scale_y_log10() + facet_grid(.~variable,scales="free_x")
  # print(p)

}

