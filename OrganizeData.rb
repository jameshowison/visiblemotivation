#!/usr/bin/ruby

require 'rubygems'
#gem 'dbi'
#gem 'dbd-mysql'
require 'dbi'
require 'mysql'
require 'logger'
#require 'dbd-mysql'

min1 = 60
min10 = 60 * 10
min30 = min1 * 30
hour = min1 * 60
two_hour = hour * 2
day =  hour * 24
approxmonth = day * 30
approxyear = day * 365

is_test = false
# window for last edit to be on watchlist
# if this is set to zero then anyone editing prior
# to curr_period_no is on watchlist.
watch_list_window_size = 6 * approxmonth

# puts in rows for all page/person/periods
# even if all values are zero.
# works by creating complete sequence of periods for each page
# min .. max
add_all_zeros = true

if (is_test) then
  durations = [10]
  table = "test_data"
else 
  #durations = [min1, min10, min30, hour, two_hour, day]
  durations = [min30, hour, two_hour]
  table = "oregon_edits"
end

dbh = DBI.connect('DBI:Mysql:test_wikipedia:localhost', 'test_wikipedia', 'test')

file = open('OrganizeDataLog.txt', File::WRONLY | File::APPEND | File::CREAT)
file.sync = true
logger = Logger.new(file)
logger.level = Logger::DEBUG
logger.warn("")
logger.warn("Starting")
logger.warn("watch_list_window_size: #{watch_list_window_size}")

durations.each do |duration|

logger.warn("Starting duration:#{duration}")

# dbh.do("DROP TABLE IF EXISTS page_period_counts_#{duration}")
# dbh.do("DROP TABLE IF EXISTS page_period_counts_#{duration}_totals")
# dbh.do("DROP TABLE IF EXISTS period_counts_totals_#{duration}")
# 
# # This creates a new table as a result of counting up the edits
# sth = dbh.prepare(
#      "CREATE TABLE page_period_counts_#{duration}
#       SELECT page_title_hash, rev_user_text, 
#              CEILING(rev_datetime / ?) AS period_no, COUNT(*) as own_edits 
#       FROM #{table} 
#       GROUP BY page_title_hash, rev_user_text, period_no")
# 
# sth.execute(duration)
# 
# dbh.do("ALTER TABLE page_period_counts_#{duration} CHANGE period_no period_no INTEGER UNSIGNED")
# dbh.do("ALTER TABLE page_period_counts_#{duration} CHANGE own_edits own_edits INTEGER UNSIGNED")
# dbh.do("ALTER TABLE page_period_counts_#{duration} CHANGE rev_user_text rev_user_text VARCHAR(128)")
# 
# dbh.do("ALTER TABLE page_period_counts_#{duration} ADD PRIMARY KEY (page_title_hash,period_no,rev_user_text(128))")
# 
# # Create new lookup table for page/period totals
# dbh.do("CREATE TABLE page_period_counts_#{duration}_totals
#       SELECT page_title_hash, period_no, SUM(own_edits) as period_page_total
#       FROM page_period_counts_#{duration}
#       GROUP BY page_title_hash, period_no")
#       
# dbh.do("ALTER TABLE page_period_counts_#{duration}_totals CHANGE period_page_total period_page_total INTEGER UNSIGNED")
# 
# dbh.do("ALTER TABLE page_period_counts_#{duration}_totals ADD PRIMARY KEY (page_title_hash,period_no)")
# 
# dbh.do("ALTER TABLE page_period_counts_#{duration} ADD COLUMN lag_1_other_edits INTEGER UNSIGNED NOT NULL DEFAULT 0")
# dbh.do("ALTER TABLE page_period_counts_#{duration} ADD COLUMN lag_1_own_edits INTEGER UNSIGNED NOT NULL DEFAULT 0")
# 
# dbh.do("ALTER TABLE page_period_counts_#{duration} ADD COLUMN watch_list_size INTEGER UNSIGNED")

sth = dbh.prepare("SELECT DISTINCT page_title_hash FROM page_period_counts_#{duration}")
sth.execute
pages = sth.fetch_all.flatten!
sth.finish

pages.each do |curr_page|
 # p curr_page
 periods = if (add_all_zeros) then
  query_str = "SELECT MIN(period_no), MAX(period_no) FROM page_period_counts_#{duration} WHERE page_title_hash = ?"
  sth = dbh.prepare(query_str)
  sth.execute(curr_page)
  minmax = sth.fetch_all.flatten!
  (minmax.first .. minmax.last).to_a
 else 
   query_str = "SELECT DISTINCT period_no FROM page_period_counts_#{duration} WHERE page_title_hash = ?"
  query_str + " ORDER BY period_no" if watch_list_window_size == 0
  sth = dbh.prepare(query_str)
  sth.execute(curr_page)
  sth.fetch_all.flatten!
 end
 
  watch_list = []
  
  periods.each do |curr_period|
  #  p curr_period
    if (watch_list_window_size == 0) then
      sth = dbh.prepare("SELECT rev_user_text FROM page_period_counts_#{duration}
      WHERE page_title_hash = ? AND period_no = ?")
      sth.execute(curr_page,curr_period)
      curr_devs = sth.fetch_all
      sth.finish
      # working in order, build up history of editors
      watch_list.push(curr_devs) 
    else
      # calculate earliest period_no for watchlist
      earliest_period = curr_period - (watch_list_window_size / duration)
      sth = dbh.prepare("SELECT rev_user_text FROM page_period_counts_#{duration}
      WHERE page_title_hash = ? AND period_no BETWEEN ? AND ?")
      sth.execute(curr_page,earliest_period,curr_period)
      watch_list = sth.fetch_all
      sth.finish
    end

    watch_list.flatten!.uniq!
    
    watch_list.each do |curr_dev| 
   #   p curr_dev
      sth = dbh.prepare("SELECT own_edits FROM page_period_counts_#{duration}
      WHERE page_title_hash = ? AND period_no = ? AND rev_user_text= ?")
      sth.execute(curr_page,curr_period,curr_dev)
      period_edits = sth.fetch_all.flatten.first
      sth.finish
     # 5311
      # if it was null set it to 0, otherwise leave it alone
      period_edits ||= 0
      
      # Get details on lag period for page/period
      lag_period = curr_period - 1
      
      sth = dbh.prepare("SELECT own_edits FROM page_period_counts_#{duration}
      WHERE page_title_hash = ? AND period_no = ? AND rev_user_text= ?")
      sth.execute(curr_page,lag_period,curr_dev)
      lag_own_edits = sth.fetch_all.flatten.first
      sth.finish
      
      lag_own_edits ||= 0
      
      # get total value to calculate other_1_lag
      sth = dbh.prepare("SELECT period_page_total 
      FROM page_period_counts_#{duration}_totals
      WHERE page_title_hash = ? AND period_no = ?")
      sth.execute(curr_page,lag_period)
      lag_period_total = sth.fetch_all.flatten.first # comes as Big Integer
      
      lag_other_edits = 
         if lag_period_total then lag_period_total - lag_own_edits else 0 end      
       
       # push variables back into the DB
       dbh.do("INSERT INTO page_period_counts_#{duration}
       (page_title_hash,period_no,rev_user_text,own_edits,
       lag_1_own_edits,lag_1_other_edits,watch_list_size) 
       VALUE (?,?,?,?,?,?,?) 
       ON DUPLICATE KEY 
       UPDATE lag_1_own_edits= ?, lag_1_other_edits= ?, watch_list_size= ?",
       curr_page,curr_period,curr_dev, #keys
       period_edits,lag_own_edits,lag_other_edits, watch_list.length,#values
       lag_own_edits,lag_other_edits,watch_list.length) #update
    end #watch_list dev
     curr_period_index = periods.index(curr_period)
      if curr_period_index % 50 == 0 then
        logger.debug("#{curr_period_index+1} of #{periods.length} periods complete")
      end
  end # period
  curr_page_index = pages.index(curr_page)
  if curr_page_index % 10 == 0 then
    logger.info("#{curr_page_index+1} of #{pages.length} pages complete")
  end
end #page

# add all period totals
# get wikipedia wide totals
dbh.do("CREATE TABLE period_counts_totals_#{duration}
      SELECT period_no, SUM(own_edits) as period_total
      FROM page_period_counts_#{duration}
      GROUP BY period_no")
      
dbh.do("ALTER TABLE period_counts_totals_#{duration} CHANGE period_total period_total INTEGER UNSIGNED")

dbh.do("ALTER TABLE period_counts_totals_#{duration} ADD PRIMARY KEY (period_no)")

dbh.do("ALTER TABLE page_period_counts_#{duration} ADD COLUMN all_wiki_period_total INTEGER UNSIGNED NOT NULL DEFAULT 0")

dbh.do("UPDATE period_counts_totals_#{duration} as a,page_period_counts_#{duration} as b SET b.all_wiki_period_total = a.period_total WHERE b.period_no = a.period_no")

end

dbh.disconnect
logger.warn("Finished")
logger.close