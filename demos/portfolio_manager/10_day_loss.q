--Access the data in cassandra
DROP TABLE IF EXISTS Portfolios;
create external table Portfolios(row_key string, column_name string, value string)
STORED BY 'org.apache.hadoop.hive.cassandra.CassandraStorageHandler'
WITH SERDEPROPERTIES ("cassandra.columns.mapping" = ":key,:column,:value",
  "cassandra.ks.name" = "PortfolioDemo",
  "cassandra.ks.repfactor" = "1",
  "cassandra.ks.strategy" = "org.apache.cassandra.locator.SimpleStrategy",
  "cassandra.cf.name" = "Portfolios" ,
  "cassandra.host" = "127.0.0.1" ,
  "cassandra.port" = "9160",
  "cassandra.partitioner" = "org.apache.cassandra.dht.RandomPartitioner")
TBLPROPERTIES (
  "cassandra.input.split.size" = "64000",
  "cassandra.range.size" = "1000",
  "cassandra.slice.predicate.size" = "1000");

DROP TABLE IF EXISTS StockHist;
create external table StockHist(row_key string, column_name string, value string)
STORED BY 'org.apache.hadoop.hive.cassandra.CassandraStorageHandler'
WITH SERDEPROPERTIES ("cassandra.ks.name" = "PortfolioDemo");

--first calculate returns
DROP TABLE IF EXISTS 10dayreturns;
CREATE TABLE 10dayreturns(ticker string, rdate string, return double)
STORED AS SEQUENCEFILE;

INSERT OVERWRITE TABLE 10dayreturns
select a.row_key ticker, b.column_name rdate, (cast(b.value as DOUBLE) - cast(a.value as DOUBLE)) ret
from StockHist a JOIN StockHist b on
(a.row_key = b.row_key AND date_add(a.column_name,10) = b.column_name);


--CALCULATE PORTFOLIO RETURNS
DROP TABLE IF EXISTS portfolio_returns;
CREATE TABLE portfolio_returns(portfolio string, rdate string, preturn double)
STORED AS SEQUENCEFILE;


INSERT OVERWRITE TABLE portfolio_returns
select row_key portfolio, rdate, SUM(b.return)
from Portfolios a JOIN 10dayreturns b ON
    (a.column_name = b.ticker)
group by row_key, rdate;


--Next find worst returns and save them back to cassandra
DROP TABLE IF EXISTS HistLoss;
create external table HistLoss(row_key string, worst_date string, loss string)
STORED BY 'org.apache.hadoop.hive.cassandra.CassandraStorageHandler'
WITH SERDEPROPERTIES ("cassandra.ks.name" = "PortfolioDemo");

INSERT OVERWRITE TABLE HistLoss
select a.portfolio, rdate, cast(minp as string)
FROM (
  select portfolio, MIN(preturn) as minp
  FROM portfolio_returns
  group by portfolio
) a JOIN portfolio_returns b ON (a.portfolio = b.portfolio and a.minp = b.preturn);

