/*
drop table if exists #SSD_prep
drop table if exists #oSSD
drop table if exists #SSD_prep2
drop table if exists #ssd

*/



drop table if exists #SSD_prep
create table #SSD_prep
	(UsNw varchar(5),Src varchar(5)
	,Yr int,Wk int,Fy int,Fw int
	,[Fw-Wk] varchar(5)
	,minDt smalldatetime
    ,LocNo varchar(5)
	-- ,Cp varchar(5),Secn varchar(10)
	-- ,NumLocs int
	,ShpQty int,ShpCost money,ShpList money
	,RcvQty int,RcvCost money,RcvList money
	,SldQty int,SldCost money,SldVal money
	,mdSldQty int,mdSldCost money,mdSldVal money
	,RfiQty int,RfiCost money
	,StSQty int
	,BsmQty int,BsmCost money
	,RtnQty int,RtnCost money)

--select * from #SSD_prep

----Used Data - BaseInv-----------
----------------------------------
insert into #SSD_prep
select 'Used'[UsNw]
	,'BI'[Src]
	,Yr,Wk
	,case when Wk > 26 then Yr else Yr - 1 end [Fy]
	,case when Wk > 26 then Wk - 26 else Wk + 26 end [Fw]
	,right('00' + cast(case when Wk > 26 then Wk - 26 else Wk + 26 end as varchar(5)),2)
		+ '-' + right('00'+ cast(Wk as varchar(5)),2)[Fw-Wk]
	,minDt
	,LocNo
	-- ,''[Cp]
	-- ,ltrim(rtrim(pm.ProductType))[Section]
	-- ,count(distinct LocNo)[NumLocs]
	----Ship Data
	,''[ShpQty]
	,''[ShpCost]
	,''[ShpList]
	----Receive/Buy/Sips data
	,sum(bi.BuyQty)[RcvQty]
	,sum(bi.BuyCost)[RcvCost]
	,''[RvcList]
	----Sales data
	,sum(bi.SoldQty)[SldQty]
	,''[SldCost]
	,sum(bi.SoldVal)[SldVal]
	----Markdown data
	,sum(bi.mdSoldQty)[mdSldQty]
	,''[mdSldCost]
	,sum(bi.mdSoldVal)[mdSldVal]
	----Transfer data
	,sum(bi.RfiQty)[RfiQty]
	,sum(bi.RfiCost)[RfiCost]
	,sum(abs(bi.iStSQty)+abs(bi.oStSQty))/2.0[StSQty]
	,sum(bi.BsmQty)[BsmQty]
	,sum(bi.BsmCost)[BsmCost]
	,''[RtnQty]
	,''[RtnCost]
from ReportsView..ShpSld_BI bi with(nolock)
	inner join ReportsView..vw_DistributionProductMaster pm witH(nolock)
		on bi.itemcode = pm.itemcode
where bi.Yr >= 2016
group by Yr, Wk, minDt
	-- ,ltrim(rtrim(pm.ProductType))
	,LocNo
	

----Used Data - SIPS--------------
----------------------------------
insert into #SSD_prep
select 'Used'[UsNw]
	,'SIPS'[Src]
	,Yr,Wk
	,case when Wk > 26 then Yr else Yr - 1 end [Fr]
	,case when Wk > 26 then Wk - 26 else Wk + 26 end [Fw]
	,right('00' + cast(case when Wk > 26 then Wk - 26 else Wk + 26 end as varchar(5)),2)
		+ '-' + right('00'+ cast(Wk as varchar(5)),2)[Fw-Wk]
	,minDt
	,LocNo
	-- ,cm.Cap[Cp]
	-- ,cm.Secn[Section]
	-- ,count(distinct LocNo)[NumLocs]
	----Ship Data
	,''[ShpQty]
	,''[ShpCost]
	,''[ShpList]
	----Receive/Buy/Sips data
	,sum(sp.SipsQty)[RcvQty]
	,''[RcvCost]
	,sum(sp.SipsList)[RcvList]
	----Sales data
	,sum(sp.SoldQty)[SldQty]
	,''[SldCost]
	,sum(sp.SoldVal)[SldVal]
	----Markdown data
	,sum(sp.mdSoldQty)[mdSldQty]
	,''[mdSldCost]
	,sum(sp.mdSoldVal)[mdSldVal]
	----Transfer data
	,sum(sp.RfiQty)[RfiQty]
	,sum(sp.RfiCost)[RfiCost]
	,sum(abs(sp.iStSQty)+abs(sp.oStSQty))/2.0[StSQty]
	,sum(sp.BsmQty)[BsmQty]
	,''[BsmCost]
	,''[RtnQty]
	,''[RtnCost]
from ReportsView..ShpSld_SIPS sp with(nolock)
	inner join ReportsView..ShpSld_SbjScnCapMap cm with(nolock)
		on sp.Subj = cm.Subj
where sp.Yr >= 2016
group by Yr, Wk, minDt
	-- ,cm.Cap,cm.Section
	,LocNo
	
	
----New Goods Data----------------
----------------------------------
insert into #SSD_prep
select 'New'[UsNw]
	,'DIPS'[Src]
	,Yr,Wk
	,case when Wk > 26 then Yr else Yr - 1 end [Fr]
	,case when Wk > 26 then Wk - 26 else Wk + 26 end [Fw]
	,right('00' + cast(case when Wk > 26 then Wk - 26 else Wk + 26 end as varchar(5)),2)
		+ '-' + right('00'+ cast(Wk as varchar(5)),2)[Fw-Wk]
	,minDt
	,LocNo
	-- ,cm.Cap[Cp]
	-- ,cm.Secn[Section]
	-- ,count(distinct LocNo)[NumLocs]
	----Ship Data
	,sum(ShipQty)[ShpQty]
	,sum(ShipCost)[ShpCost]
	,sum(ShipVal)[ShpList]
	----Receive/Buy/Sips data
	,sum(RcvQty)[RcvQty]
	,sum(RcvCost)[RcvCost]
	,sum(RcvVal)[RcvList]
	----Sales data
	,sum(SoldQty)[SldQty]
	,sum(SoldCost)[SldCost]
	,sum(SoldVal)[SldVal]
	----Markdown data
	,sum(mdSoldQty)[mdSldQty]
	,sum(mdCost)[mdSldCost]
	,sum(mdSoldVal)[mdSldVal]
	----Transfer data
	,sum(RfiQty)[RfiQty]
	,sum(RfiCost)[RfiCost]
	,sum(abs(iStSQty)+abs(oStSQty))/2.0[StSQty]
	,''[BsmQty]
	,''[BsmCost]
	,''[RtnQty]
	,''[RtnCost]
from ReportsView..ShpSld_NEW nw with(nolock)
	inner join ReportsView..ShpSld_SbjScnCapMap cm with(nolock)
		on nw.Section = cm.Section
where Yr >= 2016
group by Yr, Wk, minDt
	-- ,cm.Cap,cm.Secn
	,LocNo
	
	
----Bestsellers Data--------------
----------------------------------
insert into #SSD_prep
select 'New'[UsNw]
	,'BS'[Src]
	,Yr,Wk
	,case when Wk > 26 then Yr else Yr - 1 end [Fr]
	,case when Wk > 26 then Wk - 26 else Wk + 26 end [Fw]
	,right('00' + cast(case when Wk > 26 then Wk - 26 else Wk + 26 end as varchar(5)),2)
		+ '-' + right('00'+ cast(Wk as varchar(5)),2)[Fw-Wk]
	,minDt
	,LocNo
	-- ,cm.Cap[Cp]
	-- ,cm.Secn[Section]
	-- ,count(distinct LocNo)[NumLocs]
	----Ship Data
	,sum(ShipQty)[ShpQty]
	,sum(ShipCost)[ShpCost]
	,sum(ShipVal)[ShpList]
	----Receive/Buy/Sips data
	,sum(RcvQty)[RcvQty]
	,sum(RcvCost)[RcvCost]
	,sum(RcvVal)[RcvList]
	----Sales data
	,sum(SoldQty)[SldQty]
	,sum(SoldCost)[SldCost]
	,sum(SoldVal)[SldVal]
	----Markdown data
	,sum(mdSoldQty)[mdSldQty]
	,sum(mdCost)[mdSldCost]
	,sum(mdSoldVal)[mdSldVal]
	----Transfer data
	,sum(RfiQty)[RfiQty]
	,sum(RfiCost)[RfiCost]
	,sum(abs(iStSQty)+abs(oStSQty))/2.0[StSQty]
	,''[BsmQty]
	,''[BsmCost]
	,sum(RtnQty)[RtnQty]
	,sum(RtnCost)[RtnCost]
from ReportsView..ShpSld_FrlnSrcPrg bs with(nolock)
	inner join ReportsView..ShpSld_SbjScnCapMap cm with(nolock)
		on bs.Section = cm.Section
where Yr >= 2016
	-- Only the book product types included since all other frontline prtys get rolled into new goods.
	and bs.Src = 'BS'
group by Yr, Wk, minDt
	-- ,cm.Cap,cm.Secn
	,LocNo


drop table if exists #minDts
select Yr,Wk,minDt
	,Fy,Fw,[Fw-Wk]
into #minDts
from #SSD_prep
group by Yr,Wk,minDt
	,Fy,Fw,[Fw-Wk]


drop table if exists #oSSD
select UsNw,Src
	,os.Yr,os.Wk,md.minDt
	,md.Fy,md.Fw,md.[Fw-Wk]
	,LocNo
	-- ,Cap[Cp]
	-- ,Secn
	-- ,count(distinct LocNo)[NumLocs]
	,sum(SoldQty)[SldQty]
	,sum(SoldCost)[SldCost]
	,sum(SoldVal + SoldFee - RfndAmt)[SldVal]
	,sum(SoldFee)[SldFee]
	,sum(RfndOrds)[RfndOrds]
	,sum(RfndAmt)[RfndAmt]
	,sum(case when os.Site = 'h' then SoldQty else 0 end)[hSldQty]
	,sum(case when os.Site = 'h' then SoldVal + SoldFee - RfndAmt else 0 end)[hSldVal]
into #oSSD
from ReportsView..ShpSld_online os
	left join #minDts md on os.Yr = md.Yr and os.Wk = md.Wk
group by UsNw,Src
	,os.Yr,os.Wk,md.minDt
	,md.Fy,md.Fw,md.[Fw-Wk]
	-- ,Cap,Secn
	,LocNo

-- TODO: Confirm minDt exists for all records.
select 'missing minDt!!'[No Records = WIN]
	,* 
from #oSSd where minDt is null


drop table if exists #SSD_prep2
--Copy/Paste into the 'data' tab table
select isnull(ss.LocNo,oss.LocNo)[LocNo]
	,isnull(ss.UsNw,oss.UsNw)[UsNw]
	,isnull(ss.Src,oss.Src)[Src]
	,isnull(ss.Yr,oss.Yr)[Yr]
	,isnull(ss.Wk,oss.Wk)[Wk]
	,isnull(ss.Fy,oss.Fy)[Fy]
	,isnull(ss.Fw,oss.Fw)[Fw]
	,isnull(ss.[Fw-Wk],oss.[Fw-Wk])[Fw-Wk]
	,isnull(ss.minDt,oss.minDt)[minDt]
	-- ,isnull(ss.Cp,oss.Cp)[Cp]
	-- ,isnull(ss.Secn,oss.Secn)[Secn]
	-- ,isnull(ss.NumLocs,oss.NumLocs)[NumLocs]
	,isnull(sum(ss.ShpQty),0)[ShpQty]
	,isnull(sum(ss.ShpCost),0)[ShpCost]
	,isnull(sum(ss.ShpList),0)[ShpList]
	----Receive/Buy/Sips data
	,isnull(sum(ss.RcvQty),0)[RcvQty]
	,isnull(sum(ss.RcvCost),0)[RcvCost]
	,isnull(sum(ss.RcvList),0)[RcvList]
	----Store & Online Sales data
	,sum(isnull(ss.SldQty,0) + isnull(oss.SldQty,0))[SldQty]
	,sum(isnull(ss.SldCost,0) + isnull(oss.SldCost,0))[SldCost]
	,sum(isnull(ss.SldVal,0) + isnull(oss.SldVal,0))[SldVal]
	----Online Sales data
	,sum(isnull(oss.SldQty,0))[oSldQty]
	,sum(isnull(oss.SldCost,0))[oSldCost]
	,sum(cast(isnull(oss.SldVal,0) as money))[oSldVal]
	,sum(cast(isnull(oss.SldFee,0) as money))[oSldFee]
	,sum(isnull(oss.RfndOrds,0))[RfndOrds]
	,sum(cast(isnull(oss.RfndAmt,0) as money))[RfndAmt]
	,sum(isnull(oss.hSldQty,0))[hSldQty]
	,sum(cast(isnull(oss.hSldVal,0) as money))[hSldVal]
	----Markdown data
	,isnull(sum(ss.mdSldQty),0)[mdSldQty]
	,isnull(sum(ss.mdSldCost),0)[mdSldCost]
	,isnull(sum(ss.mdSldVal),0)[mdSldVal]
	----Transfer data
	,isnull(sum(ss.RfiQty),0)[RfiQty]
	,isnull(sum(ss.RfiCost),0)[RfiCost]
	,isnull(SUM(ss.StSQty),0)[StSQty]
	,''[BsmQty]
	,''[BsmCost]
	,isnull(sum(ss.RtnQty),0)[RtnQty]
	,isnull(sum(ss.RtnCost),0)[RtnCost]
into #SSD_prep2
from #SSD_prep ss
	full outer join #oSSD oss
		on ss.UsNw = oss.UsNw and ss.Src = oss.Src 
		and ss.minDt = oss.minDt 
        -- and ss.Secn = oss.Secn
        and ss.LocNo = oss.LocNo
group by isnull(ss.UsNw,oss.UsNw)
	,isnull(ss.Src,oss.Src)
	,isnull(ss.Yr,oss.Yr)
	,isnull(ss.Wk,oss.Wk)
	,isnull(ss.Fy,oss.Fy)
	,isnull(ss.Fw,oss.Fw)
	,isnull(ss.[Fw-Wk],oss.[Fw-Wk])
	,isnull(ss.minDt,oss.minDt)
	,isnull(ss.LocNo,oss.LocNo)
	-- ,isnull(ss.Cp,oss.Cp)
	-- ,isnull(ss.Secn,oss.Secn)
	-- ,isnull(ss.NumLocs,oss.NumLocs)


drop table if exists #ssd
select *
into #ssd
from #SSD_prep2
where abs(ShpQty)+abs(RcvQty)+abs(SldQty)+abs(RfiQty)+abs(StSQty)+abs(RtnQty) > 0
order by Src,minDt
	-- ,Cp,Secn
    ,LocNo



drop table if exists #ReopenWks
create table #ReopenWks(DistrictName varchar(20), ReopWk int)
insert into #ReopenWks values ('Arizona',20),('Austin',19),('California',23),('Chicago',23),('Columbus',20),('Dallas South',19)
	,('Georgia',20),('Houston North',19),('Houston South',19),('Indiana',20),('Iowa/Nebraska',20),('Kansas',20)
	,('Kentucky',21),('Minnesota',21),('North Texas',19),('Oklahoma',19),('Penn-Cleveland',20),('San Antonio',19)
	,('Southern Ohio',20),('St. Louis',21),('Washington',23),('Wisconsin',21),('Dallas North',19),('Tarrant',19)

drop table if exists #WkMinDts
select Wk,minDt
into #WkMinDts
from #ssd
where Yr = 2020
group by Wk,minDt

drop table if exists #LocReopWks
select lm.RegionName
    ,lm.DistrictName
    ,lm.MediaMarket
    ,lm.LocationNo
    ,case when lm.LocationNo in ('00061','00062','00066','00107') then 21 
        else rw.ReopWk end[ReopWk]
	,wd.minDt[ReopMinDt]
into #LocReopWks
from MathLab..StoreLocationMaster lm with(nolock)
    left join #ReopenWks rw on lm.DistrictName = rw.DistrictName
	inner join #WkMinDts wd on rw.ReopWk = wd.Wk
where LocationNo not in ('00011','00020','00027','00028','00042','00052','00060','00063','00079','00089','00092','00093','00101','00106')
    and LocationNo < '00200'



----Mirrroing data from teh old Ship&Sales data tab-------
-- and adding in an updating "most recent 4wk column"----- 
----------------------------------------------------------
drop table if exists #wks
declare @maxDt date = (select max(minDt)[maxDt] from #ssd)
select distinct 
	4 - (datediff(WW,s.minDt,@maxDt) % 52)[n]
	-- 4 - datediff(WW,s.minDt,@maxDt) + (52 * datediff(YY,s.minDt,@maxDt))[n]
	,minDt
into #wks
from #ssd s 
where (datediff(WW,s.minDt,@maxDt) < 4 
		or datediff(WW,s.minDt,@maxDt) between 52 and 55)
-- where 4 - datediff(WW,s.minDt,@maxDt) + (0 * datediff(YY,s.minDt,@maxDt)) between 1 and 4 
-- 	-- if 1 year ago was in the 2020 Covid-affected months, compare to TWO years ago, otherwise 1 year ago.
-- 	and ((datediff(YY,s.minDt,@maxDt) in (0,2) and @maxDt between '3/21/21' and '8/22/21')
-- 		or (datediff(YY,s.minDt,@maxDt) in (0,1) and @maxDt not between '3/21/21' and '8/22/21'))

select isnull(w.n,0)[Cur4Wks]
	,rw.RegionName[Region]
    ,rw.DistrictName[District]
    ,rw.MediaMarket
    ,rw.ReopWk
    ,rw.ReopMinDt
    ,ss.*
from #ssd ss
    inner join #LocReopWks rw on ss.LocNo = rw.LocationNo
	left join #wks w on ss.minDt = w.minDt
where Yr >= 2019 
order by Src,minDt
	-- ,Cp,Secn
    ,LocNo

/*
drop table #SSD_prep
drop table #ssd
drop table #WkMinDts

*/


/*

----Misc Rollups for replicating Ship&Sales charts--------
----------------------------------------------------------
select 'All'[UsNw]
	,Secn
	,Yr,Wk,Fy,[Fw-Wk],minDt
	,sum(RcvQty)RcvQty
	,sum(SldQty)SldQty
	,sum(mdSldQty)mdSldQty
	,sum(RfiQty)RfiQty
	,sum(RcvCost)RcvCost
	,sum(SldCost)SldCost
	,sum(SldVal)SldVal
	,sum(mdSldVal)mdSldVal
	,sum(RfiCost)RfiCost
from #ssd ss
group by Secn,
	Yr,Wk,Fy,[Fw-Wk],minDt
order by Secn,
	Yr,Wk,minDt

select 'Sips'
	,Secn
	,Yr,Wk,Fy,[Fw-Wk],minDt
	,sum(RcvQty)RcvQty
	,sum(SldQty)SldQty
	,sum(mdSldQty)mdSldQty
	,sum(RfiQty)RfiQty
	,sum(RcvCost)RcvCost
	,sum(SldCost)SldCost
	,sum(SldVal)SldVal
	,sum(mdSldVal)mdSldVal
	,sum(RfiCost)RfiCost
from #ssd ss
where UsNw = 'Used'
	and Src = 'Sips'
group by UsNw
	,Secn
	,Yr,Wk,Fy,[Fw-Wk],minDt
order by UsNw
	,Secn
	,Yr,Wk,minDt




select Yr,Wk
	,sum(ShipQty)[ShpQty]
from ReportsView..ShpSld_NGQCDC nw with(nolock)
where Yr >= 2017
group by Yr, Wk
order by Yr, Wk


select Yr,Wk,minDt
	,sum(ShipQty)[ShpQty]
	,count(*)
from ReportsView..ShpSld_NEW nw with(nolock)
where minDt >= '1/1/17'
group by Yr, Wk, minDt
order by Yr, Wk




select nw.*
	,row_number() over(partition by Yr,Wk,minDt,Section,LocNo order by Yr,Wk,minDt,Section,LocNo)[rnk]
into #temp
from ReportsView..ShpSld_NEW nw with(nolock)
where minDt = '1/28/18'
order by Yr,Wk,minDt,Section,LocNo



delete from ReportsView..ShpSld_NEW
where minDt = '1/28/18'

insert into ReportsView..ShpSld_NEW
select Yr,Wk,minDt,Section,LocNo
    ,[ShipNumIts]
    ,[ShipQty]
    ,[ShipCost]
    ,[ShipVal]
    ,[RcvNumIts]
    ,[RcvQty]
    ,[RcvCost]
    ,[RcvVal]
    ,[SoldNumIts]
    ,[SoldQty]
    ,[SoldCost]
    ,[SoldVal]
    ,[ListVal]
    ,[mdSoldQty]
    ,[mdCost]
    ,[mdSoldVal]
    ,[mdListVal]
    ,[RfiQty]
    ,[RfiCost]
    ,[RfiList]
    ,[iStSQty]
    ,[oStSQty]
from #temp where rnk = 1

select minDt
	,Yr,Wk
	,count(*)
from ReportsView..ShpSld_NEW nw with(nolock)
group by minDt
	,Yr,Wk
order by minDt
	,Yr,Wk


--Deleting Duplicate rows--------------------------[[
--------------------------------------------------[[

with cteNEW as(select *
				,row_number() over(partition by minDt,LocNo,Section order by minDt)[rn]
			from ReportsView..ShpSld_NEW nw with(nolock)
			where minDt = '2019-10-06')
			--order by LocNo,minDt,Section,rn desc)
delete from cteNEW where rn = 2


with cteBI as(select *
				,row_number() over(partition by minDt,LocNo,ItemCode order by minDt)[rn]
			from ReportsView..ShpSld_BI nw with(nolock)
			where minDt = '2019-10-06')
			--order by LocNo,minDt,ItemCode,rn desc)
delete from cteBI where rn = 2


with cteSIPS as(select *
				,row_number() over(partition by minDt,LocNo,Subj order by minDt)[rn]
			from ReportsView..ShpSld_SIPS nw with(nolock)
			where minDt = '2019-10-06')
			--order by LocNo,minDt,Subj,rn desc)
delete from cteSIPS where rn = 2



*/