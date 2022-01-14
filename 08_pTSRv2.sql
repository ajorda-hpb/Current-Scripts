
use master

----Set start & end dates
declare @sDate smalldatetime, @eDate smalldatetime, @tDate smalldatetime
set @eDate = cast(dateadd(DD,-DATEPART(Weekday,getdate())+1,getdate()) as date)
-- set @eDate = '11/8/20'
set @sDate = '12/31/17' --dateadd(WW,-76,@eDate)
set @tDate = dateadd(WW,16,@eDate)

declare @lDate date = dateadd(WW,-1,@eDate)
declare @bDate date = dateadd(WW,-16,@eDate)

-- May need to comment these out to troubleshoot potential cutoff bugs with EoY.
declare @eYr int = (select shpsld_year from ReportsView..DayCalendar where calendar_date = @lDate)
declare @bYr int = @eYr - 1
declare @tYr int = (select shpsld_year from ReportsView..DayCalendar where calendar_date = @tDate)

declare @eWk int = (select shpsld_week from ReportsView..DayCalendar where calendar_date = @lDate)
declare @bWk int = (select shpsld_week from ReportsView..DayCalendar where calendar_date = @bDate)
declare @tWk int = (select shpsld_week from ReportsView..DayCalendar where calendar_date = @tDate)

declare @2mDate date = dateadd(WW,-8,@eDate)
declare @1mDate date = dateadd(WW,-4,@eDate)
declare @f2mDate date = dateadd(WW,8,@eDate)
declare @f1mDate date = dateadd(WW,4,@eDate)

declare @2mWk int = (select shpsld_week from ReportsView..DayCalendar where calendar_date = @2mDate)
declare @1mWk int = (select shpsld_week from ReportsView..DayCalendar where calendar_date = @1mDate)
declare @f2mWk int = (select shpsld_week from ReportsView..DayCalendar where calendar_date = @f2mDate)
declare @f1mWk int = (select shpsld_week from ReportsView..DayCalendar where calendar_date = @f1mDate)

drop table if exists #fence
create table #fence(
    sDate datetime,eDate datetime
    ,lDate date,bDate date,tDate date
    ,eYr int,bYr int,tYr int
    ,eWk int,bWk int,tWk int
    ,[2mDate] date,[1mDate] date
    ,[2mWk] int,[1mWk] int
    ,[f2mDate] date,[f1mDate] date
    ,[f2mWk] int,[f1mWk] int)
insert into #fence
    values (@sDate,@eDate,@lDate,@bDate,@tDate
            ,@eYr,@bYr,@tYr
            ,@eWk,@bWk,@tWk
            ,@2mDate,@1mDate,@2mWk,@1mWk
            ,@f2mDate,@f1mDate,@f2mWk,@f1mWk)

----build list of stores...
drop table if exists #ReopenWks
create table #ReopenWks(DistrictName varchar(20), ReopWk int)
insert into #ReopenWks values ('Arizona',20),('Austin',19),('California',23),('Chicago',23)
                             ,('Columbus',20),('Dallas South',19),('Georgia',20),('Houston North',19)
                             ,('Houston South',19),('Indiana',20),('Iowa/Nebraska',20),('Kansas',20)
                             ,('Kentucky',21),('Minnesota',21),('North Texas',19),('Oklahoma',19)
                             ,('Penn-Cleveland',20),('San Antonio',19),('Southern Ohio',20)
                             ,('St. Louis',21),('Washington',23),('Wisconsin',21)
drop table if exists #stores
select lm.DistrictName
    ,lm.LocationNo[LocNo]
    ,case when lm.LocationNo in ('00061','00062','00066','00107') then 21 
        else rw.ReopWk end[ReopWk]
into #stores
from MathLab..StoreLocationMaster lm with(nolock)
    inner join #ReopenWks rw on lm.DistrictName = rw.DistrictName
where LocationNo not in ('00020','00027','00028','00042','00052','00060','00063','00079','00089','00092','00093','00101','00106')
    and LocationNo < '00200'

drop table if exists #dates
select shpsld_year[Yr]
    ,shpsld_week[Wk]
    ,first_day_in_week[minDt]
    ,dateadd(DD,7,first_day_in_week)[endDt]
into #dates
from ReportsView..DayCalendar
where shpsld_year between (@eYr - 2) and @eYr and first_day_in_week < @eDate
group by shpsld_year
    ,shpsld_week
    ,first_day_in_week


drop table if exists #PbyW
select dt.*,s.Cap,s.GoalGrp,s.Secn,s.Section
into #PbyW
from ReportsView..ShpSld_SbjScnCapMap s
    cross join #dates dt

select * from #fence 
-- select * from #dates

-- Online Sales Rates. Current past month and 4mo average from last year.
-------------------------------------------------------------------------
drop table if exists #ShpSld_Online
select dt.Yr,dt.Wk,dt.minDt
    ,os.Secn[Section]
    ,sum(SoldQty)[SoldQty]
into #ShpSld_Online
from ReportsView..ShpSld_online os
    inner join #dates dt on os.Yr = dt.Yr and os.Wk = dt.Wk
    inner join ReportsView..ShpSld_SbjScnCapMap ss on os.Secn = ss.Section
where UsNw = 'New'
group by dt.Yr,dt.Wk,dt.minDt
    ,os.Secn

-- Wholesale Sales Rates. Current past month and 4mo average from last year.
----------------------------------------------------------------------------
--    declare @sDate datetime = '12/31/17' select datepart(WW,@sDate)
drop table if exists #ShpSld_Whsl
;with ships as(
    select sh.ACTUAL_SHIP_DATE_TIME[ShipDt]
        ,ltrim(rtrim(sd.ITEM_CATEGORY1)) collate database_default[Section]
        ,sd.Item
        ,sd.TOTAL_QTY[SoldQty]
    from wms_ils..SHIPMENT_DETAIL sd with(nolock)
        inner join wms_ils..SHIPMENT_HEADER sh with(nolock) on sd.INTERNAL_SHIPMENT_NUM = sh.INTERNAL_SHIPMENT_NUM
    where sd.ORDER_TYPE in ('TTB WHOLESALE','WEBORDER')
        and sh.ACTUAL_SHIP_DATE_TIME >= @sDate
        and sh.ACTUAL_SHIP_DATE_TIME is not null
    union all
    select sh.ACTUAL_SHIP_DATE_TIME[ShipDt]
        ,ltrim(rtrim(sd.ITEM_CATEGORY1)) collate database_default[Section]
        ,sd.Item
        ,sd.TOTAL_QTY[SoldQty]
    from wms_ils..ar_SHIPMENT_DETAIL sd with(nolock)
        inner join wms_ils..ar_SHIPMENT_HEADER sh with(nolock) on sd.INTERNAL_SHIPMENT_NUM = sh.INTERNAL_SHIPMENT_NUM
    where sd.ORDER_TYPE in ('TTB WHOLESALE','WEBORDER')
        and sh.ACTUAL_SHIP_DATE_TIME >= @sDate
        and sh.ACTUAL_SHIP_DATE_TIME is not null
    union all
    select sh.ACTUAL_SHIP_DATE_TIME[ShipDt]
        ,ltrim(rtrim(sd.ITEM_CATEGORY1)) collate database_default[Section]
        ,sd.Item
        ,sd.TOTAL_QTY[SoldQty]
    from wms_ar_ils..ar_SHIPMENT_DETAIL sd with(nolock)
        inner join wms_ar_ils..ar_SHIPMENT_HEADER sh with(nolock) on sd.INTERNAL_SHIPMENT_NUM = sh.INTERNAL_SHIPMENT_NUM
    where sd.ORDER_TYPE in ('TTB WHOLESALE','WEBORDER')
        and sh.ACTUAL_SHIP_DATE_TIME >= @sDate
        and sh.ACTUAL_SHIP_DATE_TIME is not null
) 
select dt.Yr,dt.Wk,dt.minDt
    ,sh.Section
	,count(distinct sh.Item)[SoldIts]
    ,sum(sh.SoldQty)[SoldQty]
into #ShpSld_Whsl
from ships sh inner join #dates dt on sh.ShipDt >= dt.minDt and sh.[ShipDt] < dt.endDt
group by dt.Yr,dt.Wk,dt.minDt
    ,sh.Section

-- Brick & Mortar Sales Rates------------------
-----------------------------------------------
drop table if exists #ShpSld_BnM
select dt.Yr,dt.Wk,dt.minDt
    ,nw.Section
    ,sum(nw.ShipQty)[ShipQty]
    ,sum(nw.SoldQty)[SoldQty]
into #ShpSld_BnM
from ReportsView..ShpSld_NEW nw with(nolock)
    inner join #dates dt on nw.minDt = dt.minDt
group by dt.Yr,dt.Wk,dt.minDt
    ,nw.Section

-- Combine Online & B&M & Whsl Sales--------------------------
--------------------------------------------------------------
drop table if exists #sums
select ss.Yr,ss.Wk,ss.minDt
    ,ss.Cap,ss.Secn
    ,isnull(sum(bm.ShipQty),0)[ShpQ]
    ,isnull(sum(bm.SoldQty),0)[SldQ]
    ,isnull(sum(ol.SoldQty),0)[oSldQ]
    ,count(ol.SoldQty)[oCount]
    ,isnull(sum(ws.SoldQty),0)[wSldQ]
    ,count(ws.SoldQty)[wCount]
into #sums
from #PbyW ss
    left join #ShpSld_BnM bm with(nolock) on ss.Section = bm.Section and ss.minDt = bm.minDt
    left join #ShpSld_Online ol with(nolock) on ss.Section = ol.Section and ss.minDt = ol.minDt
    left join #ShpSld_Whsl ws with(nolock) on ss.Section = ws.Section and ss.minDt = ws.minDt
where ss.Secn not in ('0','BCD','BTFic','BTNonFic','Kids','NONE','Stash','') 
    and ss.Cap != 'loc'
group by ss.Yr,ss.Wk,ss.minDt
    ,ss.Cap,ss.Secn

drop table if exists #janus
;with rosses as(
    select Yr,Wk,minDt
        ,Cap,Secn
        ,ShpQ
        ,SldQ+oSldQ+wSldQ[SldQ]
        ,SldQ[sSldQ]
        ,oSldQ
        ,wSldQ
        ,sum(SldQ+oSldQ+wSldQ) over(partition by Secn order by minDt rows between 3 preceding and current row)
            / 4.0[RoS]
        ,sum(SldQ+oSldQ+wSldQ) over(partition by Secn order by minDt rows between 1 following and 4 following)
            / 4.0[fRoS]
        ,sum(SldQ) over(partition by Secn order by minDt rows between 3 preceding and current row)
            / 4.0[sRoS]
        ,sum(SldQ) over(partition by Secn order by minDt rows between 1 following and 4 following)
            / 4.0[fsRoS]
        ,sum(oSldQ) over(partition by Secn order by minDt rows between 3 preceding and current row)
            / 4.0[oRoS]
        ,sum(oSldQ) over(partition by Secn order by minDt rows between 1 following and 4 following)
            / 4.0[foRoS]
        ,sum(wSldQ) over(partition by Secn order by minDt rows between 3 preceding and current row)
            / 4.0[wRoS]
        ,sum(wSldQ) over(partition by Secn order by minDt rows between 1 following and 4 following)
            / 4.0[fwRoS]
    from #sums
    )
select Yr,Wk,minDt
    ,Cap,Secn
    ,ShpQ
    ,SldQ
    ,sSldQ
    ,oSldQ
    ,wSldQ
    -- ALL RoSs
    ,RoS
    ,RoS - lag(RoS,1,null) over(partition by Secn order by minDt)[d1RoS]
    ,lag(RoS,1,null) over(partition by Secn order by minDt) 
        - lag(RoS,2,null) over(partition by Secn order by minDt)[d2RoS]
    ,lag(RoS,2,null) over(partition by Secn order by minDt) 
        - lag(RoS,3,null) over(partition by Secn order by minDt)[d3RoS]
    ,fRoS
    ,lead(fRoS,4,null) over(partition by Secn order by minDt)[f1RoS]
    ,lead(fRoS,8,null) over(partition by Secn order by minDt)[f2RoS]
    ,lead(fRoS,12,null) over(partition by Secn order by minDt)[f3RoS]
    ,lead(fRoS,16,null) over(partition by Secn order by minDt)[f4RoS]
    -- B&M RoSs
    ,sRoS
    ,sRoS - lag(sRoS,1,null) over(partition by Secn order by minDt)[d1sRoS]
    ,lag(sRoS,1,null) over(partition by Secn order by minDt) 
        - lag(sRoS,2,null) over(partition by Secn order by minDt)[d2sRoS]
    ,lag(sRoS,2,null) over(partition by Secn order by minDt) 
        - lag(sRoS,3,null) over(partition by Secn order by minDt)[d3sRoS]
    ,fsRoS
    ,lead(fsRoS,4,null) over(partition by Secn order by minDt)[f1sRoS]
    ,lead(fsRoS,8,null) over(partition by Secn order by minDt)[f2sRoS]
    ,lead(fsRoS,12,null) over(partition by Secn order by minDt)[f3sRoS]
    ,lead(fsRoS,16,null) over(partition by Secn order by minDt)[f4sRoS]
    -- Online RoSs
    ,oRoS
    ,oRoS - lag(oRoS,1,null) over(partition by Secn order by minDt)[d1oRoS]
    ,lag(oRoS,1,null) over(partition by Secn order by minDt) 
        - lag(oRoS,2,null) over(partition by Secn order by minDt)[d2oRoS]
    ,lag(oRoS,2,null) over(partition by Secn order by minDt) 
        - lag(oRoS,3,null) over(partition by Secn order by minDt)[d3oRoS]
    ,foRoS
    ,lead(foRoS,4,null) over(partition by Secn order by minDt)[f1oRoS]
    ,lead(foRoS,8,null) over(partition by Secn order by minDt)[f2oRoS]
    ,lead(foRoS,12,null) over(partition by Secn order by minDt)[f3oRoS]
    ,lead(foRoS,16,null) over(partition by Secn order by minDt)[f4oRoS]
    -- Wholesale RoSs
    ,wRoS
    ,wRoS - lag(wRoS,1,null) over(partition by Secn order by minDt)[d1wRoS]
    ,lag(wRoS,1,null) over(partition by Secn order by minDt) 
        - lag(wRoS,2,null) over(partition by Secn order by minDt)[d2wRoS]
    ,lag(wRoS,2,null) over(partition by Secn order by minDt) 
        - lag(wRoS,3,null) over(partition by Secn order by minDt)[d3wRoS]
    ,fwRoS
    ,lead(fwRoS,4,null) over(partition by Secn order by minDt)[f1wRoS]
    ,lead(fwRoS,8,null) over(partition by Secn order by minDt)[f2wRoS]
    ,lead(fwRoS,12,null) over(partition by Secn order by minDt)[f3wRoS]
    ,lead(fwRoS,16,null) over(partition by Secn order by minDt)[f4wRoS]
into #janus
from rosses
where Yr >= @bYr 
order by Secn

drop table if exists #RoS
select a.Yr,a.Wk,a.minDt
    ,a.Cap,a.Secn
    ,a.RoS
    ,b.RoS[lyRoS]
    ,a.sRoS
    ,b.sRoS[lySRoS]
    ,a.oRoS
    ,b.oRoS[lyORoS]
    ,a.wRoS
    ,b.wRoS[lyWRoS]
    ,b.fRoS*4.0[exp1mo]
    ,b.f1RoS*4.0[exp2mo]
    ,b.f2RoS*4.0[exp3mo]
    ,b.f3RoS*4.0[exp4mo]
    ,b.f4RoS*4.0[exp5mo]
    ,b.fsRoS*4.0[expS1mo]
    ,b.f1sRoS*4.0[expS2mo]
    ,b.f2sRoS*4.0[expS3mo]
    ,b.f3sRoS*4.0[expS4mo]
    ,b.f4sRoS*4.0[expS5mo]
    ,b.foRoS*4.0[expO1mo]
    ,b.f1oRoS*4.0[expO2mo]
    ,b.f2oRoS*4.0[expO3mo]
    ,b.f3oRoS*4.0[expO4mo]
    ,b.f4oRoS*4.0[expO5mo]
    ,b.fwRoS*4.0[expW1mo]
    ,b.f1wRoS*4.0[expW2mo]
    ,b.f2wRoS*4.0[expW3mo]
    ,b.f3wRoS*4.0[expW4mo]
    ,b.f4WRoS*4.0[expW5mo]
    ,a.RoS/nullif(b.RoS,0)[moReb]
    ,a.SldQ*1.0/nullif(b.SldQ,0)[wkReb]
    ,a.sRoS/nullif(b.sRoS,0)[moSReb]
    ,a.sSldQ*1.0/nullif(b.sSldQ,0)[wkSReb]
    ,a.d1RoS
    ,a.d2RoS
    ,a.d1sRoS
    ,a.d2sRoS
    ,a.d1oRoS
    ,a.d2oRoS
    ,a.d1wRoS
    ,a.d2wRoS
into #RoS
from #janus a 
    inner join #fence f on a.minDt = f.lDate
    left  join #janus b on a.Yr-1 = b.Yr and a.Secn = b.Secn and a.wk = b.Wk


-- TTB Ship Unique Items per Week----------------------
-------------------------------------------------------
----Set start & end dates
declare @endTTB date = (select top 1 eDate from #fence)
-- 52 weeks to a full year + 16 weeks to get the trailing 4 months
declare @startTTB date = dateadd(WW,-68,@endTTB)
drop table if exists #ShipItsByProg
;with ships as(
    select sh.ACTUAL_SHIP_DATE_TIME[ShipDt]
        ,ltrim(rtrim(sd.ITEM_CATEGORY1)) collate database_default[Section]
		,sd.Order_Type
        ,sd.Item
        ,sd.TOTAL_QTY[SoldQty]
    from wms_ils..SHIPMENT_DETAIL sd with(nolock)
        inner join wms_ils..SHIPMENT_HEADER sh with(nolock) on sd.INTERNAL_SHIPMENT_NUM = sh.INTERNAL_SHIPMENT_NUM
    where sd.ORDER_TYPE in ('TTB WHOLESALE','WEBORDER','TTB Reorders','TTB Initial')
        and sh.ACTUAL_SHIP_DATE_TIME >= @startTTB
        and sh.ACTUAL_SHIP_DATE_TIME < @endTTB
		and sd.company = 'TTB'
    union all
    select sh.ACTUAL_SHIP_DATE_TIME[ShipDt]
        ,ltrim(rtrim(sd.ITEM_CATEGORY1)) collate database_default[Section]
		,sd.Order_Type
        ,sd.Item
        ,sd.TOTAL_QTY[SoldQty]
    from wms_ils..ar_SHIPMENT_DETAIL sd with(nolock)
        inner join wms_ils..ar_SHIPMENT_HEADER sh with(nolock) on sd.INTERNAL_SHIPMENT_NUM = sh.INTERNAL_SHIPMENT_NUM
    where sd.ORDER_TYPE in ('TTB WHOLESALE','WEBORDER','TTB Reorders','TTB Initial')
        and sh.ACTUAL_SHIP_DATE_TIME >= @startTTB
        and sh.ACTUAL_SHIP_DATE_TIME < @endTTB
		and sd.company = 'TTB'
    union all
    select sh.ACTUAL_SHIP_DATE_TIME[ShipDt]
        ,ltrim(rtrim(sd.ITEM_CATEGORY1)) collate database_default[Section]
		,sd.Order_Type
        ,sd.Item
        ,sd.TOTAL_QTY[SoldQty]
    from wms_ar_ils..ar_SHIPMENT_DETAIL sd with(nolock)
        inner join wms_ar_ils..ar_SHIPMENT_HEADER sh with(nolock) on sd.INTERNAL_SHIPMENT_NUM = sh.INTERNAL_SHIPMENT_NUM
    where sd.ORDER_TYPE in ('TTB WHOLESALE','WEBORDER','TTB Reorders','TTB Initial')
        and sh.ACTUAL_SHIP_DATE_TIME >= @startTTB
        and sh.ACTUAL_SHIP_DATE_TIME < @endTTB
		and sd.company = 'TTB'
)
select d.minDt,d.Yr,d.Wk,s.Secn
    ,isnull(sum(sh.SoldQty),0)[ShipQty]
	,count(distinct sh.Item)[ShipIts]
    ,isnull(sum(case when sh.Order_Type in ('TTB Reorders','TTB Initial') then sh.SoldQty else 0 end),0)[troShipQty]
	,count(distinct case when sh.Order_Type in ('TTB Reorders','TTB Initial') then sh.Item end)[troShipIts]
    ,isnull(sum(case when sh.Order_Type in ('TTB WHOLESALE','WEBORDER') then sh.SoldQty else 0 end),0)[wshShipQty]
	,count(distinct case when sh.Order_Type in ('TTB WHOLESALE','WEBORDER') then sh.Item end)[wslShipIts]
    ,datediff(WEEK,@endTTB,d.minDt)[WksDiff]
into #ShipItsByProg
from #dates d cross join ReportsView..ShpSld_SbjScnCapMap s
    inner join ReportsView..DayCalendar dc on d.minDt = dc.first_day_in_week
    left join ships sh on dc.calendar_date = cast(sh.ShipDt as date) and sh.Section = s.Section
where d.minDt >= @startTTB
    and d.minDt < @endTTB 
    and s.Section is not null
group by d.minDt,d.Yr,d.Wk,s.Secn

drop table if exists #ShpIts_bfraftr
;with cte as(
select Yr,Wk,WksDiff,Secn
	,sum(ShipIts) over(partition by Secn order by minDt rows between 55 preceding and 52 preceding)/ 4.0 [ly1mTi]
	,sum(ShipIts) over(partition by Secn order by minDt rows between 51 preceding and 48 preceding)/ 4.0 [fly1mTi]
	,sum(ShipIts) over(partition by Secn order by minDt rows between  3 preceding and current row)/ 4.0 [cr1mTi]
	,sum(ShipIts) over(partition by Secn order by minDt rows between 67 preceding and 52 preceding)/ 16.0 [ly4mTi]
	,sum(ShipIts) over(partition by Secn order by minDt rows between 51 preceding and 36 preceding)/ 16.0 [fly4mTi]
	,sum(ShipIts) over(partition by Secn order by minDt rows between 15 preceding and current row)/ 16.0 [cr4mTi]
	,sum(ShipQty) over(partition by Secn order by minDt rows between 55 preceding and 52 preceding)/ 4.0 [ly1mQ]
	,sum(ShipQty) over(partition by Secn order by minDt rows between 51 preceding and 48 preceding)/ 4.0 [fly1mQ]
	,sum(ShipQty) over(partition by Secn order by minDt rows between  3 preceding and current row)/ 4.0 [cr1mQ]
	,sum(ShipQty) over(partition by Secn order by minDt rows between 67 preceding and 52 preceding)/ 16.0 [ly4mQ]
	,sum(ShipQty) over(partition by Secn order by minDt rows between 51 preceding and 36 preceding)/ 16.0 [fly4mQ]
	,sum(ShipQty) over(partition by Secn order by minDt rows between 15 preceding and current row)/ 16.0 [cr4mQ]
from #ShipItsByProg so
)
select Secn
    ,ly1mTi,fly1mTi,cr1mTi
    ,ly4mTi,fly4mTi,cr4mTi
    ,ly1mQ,fly1mQ,cr1mQ
    ,ly4mQ,fly4mQ,cr4mQ
into #ShpIts_bfraftr from cte
where WksDiff = -1 



-- 01: Output All RoSs Together---------------------
----------------------------------------------------
select Yr
    ,Wk
    ,cast(minDt as date)[minDt]
    ,Cap
    ,Secn
    ,lysRoS,sRoS  -- Store RoSs 
    ,lyoRoS,oRoS  -- Online RoSs
    ,lywRoS,wRoS  -- Whsl RoSs
    ,(expS1mo+expS2mo+expS3mo)/12.0[eS3m]  --Expected Store 3mo Sales
    ,(expO1mo+expO2mo+expO3mo)/12.0[eO3m]  --Expected Online 3mo Sales
    ,(expW1mo+expW2mo+expW3mo)/12.0[eW3m]  --Expected Whsl 3mo Sales
from #RoS rs
order by Cap,rs.Secn   


-- 02: Output for 'TTB Titles Only' section of mockup tab (starts in col FD)-----
---------------------------------------------------------------------------------
select f.eYr[Yr],cast(f.eDate as date)[minDt],a.*
from #ShpIts_bfraftr a cross join #fence f 
where Secn <> '0'
order by a.Secn,f.eDate


-- 03: Output for TROSecnRoSs tab----------------------------
-------------------------------------------------------------
select ss.DefaultScheme[DefSchID]
	,ch.Total_Scheme_Qty[SchQty]
	,mr.RordGrp,mr.Cap
	,mr.GoalGrp,mr.Secn
    ,count(RptIt)[RptIts]
    ,count(case when mr.Active = 'active' then RptIt end)[AcIts]
    ,count(case when mr.Active = 'inac' and crSldQ > 0 then RptIt end)[IaCrIts]
	,sum(LGI)[LGI]
    ,sum(crRoS)[crRoS]
    ,sum(crWhRoS)[crWhRoS]
    ,sum(case when mr.Active = 'active' then crRoS else 0 end)[AcCrRoS]
    ,sum(case when mr.Active = 'active' then crWhRoS else 0 end)[AcCrWhRoS]
    ,sum(case when mr.Active = 'inac' and crSldQ > 0 then crRoS else 0 end)[IaCrRoS]
    ,sum(case when mr.Active = 'inac' and crSldQ > 0 then crWhRoS else 0 end)[IaCrWhRoS]
    ,sum(atRoS)[atRoS]
    ,sum(atZidRoS)[atZidRoS]
    ,sum(case when mr.Active = 'active' then atRoS else 0 end)[AcAtRoS]
    ,sum(case when mr.Active = 'active' then atZidRoS else 0 end)[AcAtZidRoS]
    ,sum(case when mr.Active = 'active' then atWhRoS else 0 end)[AcAtWhRoS]
    ,sum(case when mr.Active = 'inac' and atSldQ > 0 then atRoS else 0 end)[IaAtRoS]
    ,sum(case when mr.Active = 'inac' and atSldQ > 0 then atWhRoS else 0 end)[IaAtWhRoS]
    ,sum(crSldQ)[crSldQ]
    ,sum(case when mr.Active = 'active' then crSldQ else 0 end)[AcCrSldQ]
    ,sum(case when mr.Active = 'active' then crWhSldQ else 0 end)[AcCrWhSldQ]
    ,sum(case when mr.Active = 'inac' then crSldQ else 0 end)[IaCrSldQ]
    ,sum(case when mr.Active = 'inac' then crWhSldQ else 0 end)[IaCrWhSldQ]
    ,sum(atSldQ)[atSldQ]
    ,sum(case when mr.Active = 'active' then atSldQ else 0 end)[AcAtSldQ]
    ,sum(case when mr.Active = 'active' then atWhSldQ else 0 end)[AcAtWhSldQ]
    ,sum(case when mr.Active = 'inac' then atSldQ else 0 end)[IaAtSldQ]
    ,sum(case when mr.Active = 'inac' then atWhSldQ else 0 end)[IaAtWhSldQ]
from ReportsView..Pipeline_MrgdRoSs mr
    inner join ReportsView..ShpSld_SbjScnCapMap ss with(nolock) on ss.Section = mr.Secn
	left join wms_ils..HPB_Scheme_Header ch with(nolock) on ss.DefaultScheme = ch.Scheme_ID collate database_default
where RordGrp = 'TRO'
group by mr.RordGrp
	,mr.Cap
	,mr.GoalGrp
    ,mr.Secn
    ,ss.DefaultScheme
	,ch.Total_Scheme_Qty
order by Cap,GoalGrp
	,Secn


-- 04: Output for ReceiptDetails tab------------------------------------
------------------------------------------------------------------------ 
select rd.COMPANY collate database_default[Company]
    ,s.Secn
    ,pg.RordGrp
    ,rh.Receipt_ID
    ,cast(rh.Receipt_Date as date)[Receipt_Date]
    ,rh.SHIP_FROM[Vendor]
    ,rd.Item
    ,rd.ITEM_DESC[Title]
    ,SUM(rd.TOTAL_QTY)[Qty]
    ,pm.Cost
    ,pm.Price
from wms_ils..RECEIPT_HEADER rh 
    inner join wms_ils..RECEIPT_DETAIL rd 
        on rh.INTERNAL_RECEIPT_NUM=rd.INTERNAL_RECEIPT_NUM
    inner join ReportsView..ShpSld_SbjScnCapMap s 
        on s.Section = rd.ITEM_CATEGORY1 collate database_default
    inner join ReportsView..ProdGoals_ItemMaster pg with(nolock) 
        on pg.ItemCode = right('00000000000000000000' + rd.Item,20) collate database_default
    inner join ReportsView..vw_DistributionProductMaster pm with(nolock)
        on pg.ItemCode = pm.ItemCode
where rd.TOTAL_QTY=rd.OPEN_QTY 
    and rd.COMPANY in ('HPB','TTB')
    and rh.CLOSE_DATE is null
    and left(rh.RECEIPT_ID,3) <> 'HRO'
    and pg.RordGrp in ('CDC','TRO')
    and s.Section is not null
group by rd.COMPANY 
    ,s.Secn
    ,pg.RordGrp
    ,rh.Receipt_ID
    ,rh.Receipt_Date
    ,rh.SHIP_FROM
    ,rd.Item
    ,rd.ITEM_DESC
    ,pm.Cost
    ,pm.Price



