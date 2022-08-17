SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[ShpSld_FrlnBS_UPDATE]
as
SET XACT_ABORT, NOCOUNT ON;

-- Run the complete past week, Sunday - Sunday(excl)
declare @ends datetime = cast(dateadd(DD,-DATEPART(Weekday,getdate())+1,getdate()) as date)
select dateadd(DD,-7,@ends)[StartDate],@ends[EndDate]

----Set start & end dates
drop table if exists #dates
select dateadd(DD,-7,@ends)[sDate]
	,@ends[eDate]
into #dates

----build list of stores...
drop table if exists #stores
select distinct LocationNo[LocNo]
into #stores    
from ReportsData..Locations with(nolock)
where LocationNo between '00001' and '00150'

----build a table with all sections....
drop table if exists #sections
select distinct ltrim(rtrim(pm.SectionCode))[Section]
into #sections
from ReportsView.dbo.vw_DistributionProductMaster pm with(nolock)

--build table with Src types for Frontline product (BS vs Frln)
drop table if exists #src
create table #src (Src varchar(5))
insert into #src values ('BS'),('Frln')

-- Spliting between Initial (from Publisher) vendors and the reorder/warehouse ones...
drop table if exists #progs
create table #progs(prog varchar(5))
insert into #progs values ('init'),('rord')

----List of DIPS itemCode excludes
drop table if exists #excludes
select pm.ItemCode
into #excludes
from ReportsView..vw_DistributionProductMaster pm with(nolock)
where (pm.ItemCode in ('00000000000010058656','00000000000010058657','00000000000010058658'  --Misc Used not in the BaseInv table (MediaPlayer,Tablet,Phone)
					  ,'00000000000010017201','00000000000010017202','00000000000010041275'  --More Used  (Boardgames,Puzzles,Electronics)
					  ,'00000000000010017203','00000000000010017200'						 --& more Used (GameSystem,Textbooks)
					  ,'00000000000010051490','00000000000010196953','00000000000010200047') --Sticker King & Bag Charges
		or pm.ItemCode in (select distinct ItemCode from ReportsData..BaseInventory with(nolock))
		or ltrim(rtrim(pm.ProductType)) in ('HPBP','PRMO','SUP'))
	--Tote bags are the bane of my existence
	and ltrim(rtrim(pm.PurchaseFromVendorID)) <> 'IDTXBKSTAP' 
	and ltrim(rtrim(pm.VendorID)) <> 'IDTXBKSTAP'

--build table of each week & its Yr/Wk/MinDate
drop table if exists #minDts
select dc.shpsld_year[Yr]
	,dc.shpsld_week[Wk]
	,dc.calendar_date[minDt]
    ,dateadd(DD,7,dc.calendar_date)[endDt]
into #minDts
from #dates d inner join ReportsView..DayCalendar dc 
    on d.sDate <= dc.calendar_date and dc.calendar_date < d.eDate 
where dc.calendar_date = dc.first_day_in_week
select * from #minDts order by minDt


----New Goods Shipments-----------------------
----------------------------------------------
----get all the shipment data....
drop table if exists #ship
select m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end[Src]
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end[Prog]
	,ltrim(rtrim(pm.SectionCode))[Section]
	,sh.ToLocationNo[LocNum]
	,ISNULL(count(distinct sd.ItemCode),0)[ShipNumIts]
	,ISNULL(sum(sd.Qty*sd.CostEach),0)[ShipCost]
	,ISNULL(sum(sd.Qty),0)[ShipQty]
	,ISNULL(sum(sd.Qty*pm.Price),0)[ShipVal]
into #ship
from ReportsData..ShipmentHeader sh with(nolock)
	inner join ReportsData..ShipmentDetail sd with(nolock) on sh.TransferID = sd.TransferID
	inner join ReportsData..ProductMaster pm with(nolock) on pm.ItemCode=sd.ItemCode 
	inner join #minDts m on sh.DateTransferred >= m.minDt and sh.DateTransferred < m.endDt
    inner join #stores s on sh.ToLocationNo = s.LocNo
    left  join #excludes e on sd.ItemCode = e.ItemCode
where sh.FromLocationNo='00944' 
	and e.ItemCode is null
    and pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
group by m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
	,ltrim(rtrim(pm.SectionCode))
	,sh.ToLocationNo



----New Goods Store Receiving-----------------
----------------------------------------------
drop table if exists #receiveds
select m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end[Src]
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end[Prog]
	,ltrim(rtrim(pm.SectionCode)) as Section
	,sh.LocationNo as LocNum
	,ISNULL(count(distinct sd.ItemCode),0)[RcvNumIts]
	,ISNULL(sum(sd.Qty*pm.Cost),0)[RcvCost]
	,ISNULL(sum(sd.Qty),0)[RcvQty]
	,ISNULL(sum(sd.Qty*pm.Price),0)[RcvVal]
into #receiveds
from --ReportsView.dbo.vw_StoreReceiving s with(nolock)
	ReportsData.dbo.SR_Header sh  with(nolock) 
	inner join ReportsData.dbo.SR_Detail sd  with(nolock) on sh.BatchID = sd.BatchID 
	inner join ReportsData..ProductMaster pm with(nolock) on pm.ItemCode=sd.ItemCode 
	inner join #minDts m on sd.ProcessDate >= m.minDt and sd.ProcessDate < m.endDt
    inner join #stores s on sh.LocationNo = s.LocNo
    left  join #excludes e on sd.ItemCode = e.ItemCode
where sh.ShipmentType in ('R','W')
	and pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
	and e.ItemCode is null
group by m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
	,ltrim(rtrim(pm.SectionCode))
	,sh.LocationNo
--select count(*) from #receiveds



----New Goods Sales---------------------------
----------------------------------------------
drop table if exists #sales
;with HpbSales as(
	select * from HPB_SALES..SIH2021 with(nolock)
	union all select * from HPB_SALES..SIH2022 with(nolock)
)
select m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end[Src]
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end[Prog]
	,ltrim(rtrim(pm.SectionCode)) as Section
	,loc.LocationNo as LocNum
	,isnull(count(distinct sd.ItemCode),0)[SoldNumIts]
	--total sales.............................................................................
	,isnull(sum(case sd.isreturn when 'y' then -sd.quantity else sd.quantity end),0)[SoldQty]
	,isnull(sum(case sd.isreturn when 'y' then -pm.cost else pm.cost end),0)[SoldCost]
	,isnull(sum(sd.extendedamt),0)[SoldVal]
	,isnull(sum(case sd.isreturn when 'y' then -sd.UnitPrice else sd.UnitPrice end),0)[ListVal]
	--markdown sales...........................................................................
	,isnull(sum(case 
				when sd.isreturn='y' and sd.RegisterPrice < sd.UnitPrice then -sd.quantity 
				when sd.isreturn='n' and sd.RegisterPrice < sd.UnitPrice then  sd.quantity 
				else 0 end),0)[mdSoldQty]
	,isnull(sum(case 
				when sd.isreturn='y' and sd.RegisterPrice < sd.UnitPrice then -pm.cost 
				when sd.isreturn='n' and sd.RegisterPrice < sd.UnitPrice then  pm.cost 
				else 0 end),0)[mdCost]
	,isnull(sum(case
				when sd.RegisterPrice < sd.UnitPrice then sd.ExtendedAmt
				else 0 end),0)[mdSoldVal]
	,isnull(sum(case 
				when sd.isreturn='y' and sd.RegisterPrice < sd.UnitPrice then -sd.UnitPrice
				when sd.isreturn='n' and sd.RegisterPrice < sd.UnitPrice then  sd.UnitPrice 
				else 0 end),0)[mdListVal]
into #sales
from HpbSales sd 
	inner join ReportsData..ProductMaster pm with(nolock) on pm.ItemCode=sd.ItemCode 
	inner join ReportsData..Locations loc with(nolock) on sd.LocationID=loc.LocationID
	inner join #minDts m on sd.BusinessDate >= m.minDt and sd.BusinessDate < m.endDt
    inner join #stores s on loc.LocationNo = s.LocNo
    left  join #excludes e on sd.ItemCode = e.ItemCode
where pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
	and sd.Status = 'A'
	and e.ItemCode is null
group by m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
	,ltrim(rtrim(pm.SectionCode))
	,loc.LocationNo



----New Goods Transfers-----------------------
----------------------------------------------
drop table if exists #xfers
--Item FROM a location---------
;with xfersF as(
	select m.minDt
		,h.LocationNo[FromLoc]
		,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end[Src]
		,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end[Prog]
		,ltrim(rtrim(pm.SectionCode))[Section]
		,d.DipsItemCode[ItemCode]
		,isnull(sum(case when h.TransferType = 1 then d.Quantity else 0 end),0)[TshQty]
		,isnull(sum(case when h.TransferType = 1 then d.DipsCost*d.Quantity else 0 end),0)[TshCost]
		,isnull(sum(case when h.TransferType = 1 then pm.Price*d.Quantity else 0 end),0)[TshList]
		,isnull(sum(case when h.TransferType = 7 then d.Quantity else 0 end),0)[DmgQty]
		,isnull(sum(case when h.TransferType = 7 then d.DipsCost*d.Quantity else 0 end),0)[DmgCost]
		,isnull(sum(case when h.TransferType = 7 then pm.Price*d.Quantity else 0 end),0)[DmgList]
		,isnull(sum(case when h.TransferType = 3 then d.Quantity else 0 end),0)[StSQty]
		,isnull(sum(case when h.TransferType = 3 then d.DipsCost*d.Quantity else 0 end),0)[StSCost]
		,isnull(sum(case when h.TransferType = 3 then pm.Price*d.Quantity else 0 end),0)[StSList]
		,isnull(sum(case when h.TransferType = 2 then d.Quantity else 0 end),0)[DntQty]
		,isnull(sum(case when h.TransferType = 2 then d.DipsCost*d.Quantity else 0 end),0)[DntCost]
		,isnull(sum(case when h.TransferType = 2 then pm.Price*d.Quantity else 0 end),0)[DntList]
		,isnull(sum(case when h.TransferType = 4 then d.Quantity else 0 end),0)[BsmQty]
		,isnull(sum(case when h.TransferType = 4 then d.DipsCost*d.Quantity else 0 end),0)[BsmCost]
		,isnull(sum(case when h.TransferType = 4 then pm.Price*d.Quantity else 0 end),0)[BsmList]
		,isnull(sum(case when h.TransferType = 6 then d.Quantity else 0 end),0)[RtnQty]
		,isnull(sum(case when h.TransferType = 6 then d.DipsCost*d.Quantity else 0 end),0)[RtnCost]
		,isnull(sum(case when h.TransferType = 6 then pm.Price*d.Quantity else 0 end),0)[RtnList]
		,isnull(sum(case when h.TransferType = 5 then d.Quantity else 0 end),0)[MktQty]
		,isnull(sum(case when h.TransferType = 5 then d.DipsCost*d.Quantity else 0 end),0)[MktCost]
		,isnull(sum(case when h.TransferType = 5 then pm.Price*d.Quantity else 0 end),0)[MktList]
	from ReportsData..SipsTransferBinHeader as h 
		inner join ReportsData..SipsTransferBinDetail as d on h.TransferBinNo = d.TransferBinNo
		inner join Reportsdata..ProductMaster pm with(nolock) on d.DipsItemCode = pm.ItemCode
		inner join #minDts m on h.UpdateTime >= m.minDt and h.UpdateTime < m.endDt
		inner join #stores s on h.LocationNo = s.LocNo
		left  join #excludes e on pm.ItemCode = e.ItemCode
	where pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
		and h.StatusCode = 3
		and h.TransferType in (1,2,3,4,5,6,7)
		and d.StatusCode = 1
		and e.ItemCode is null
	group by m.minDt
		,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
		,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
		,h.LocationNo 
		,ltrim(rtrim(pm.SectionCode))
		,d.DipsItemCode
	)
--Item TO a location-----------
,xfersT as(
	select m.minDt
		,h.ToLocationNo[ToLoc]
		,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end[Src]
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end[Prog]
		,ltrim(rtrim(pm.SectionCode))[Section]
		,d.DipsItemCode[ItemCode]
		,isnull(sum(d.Quantity),0)[RcvQty]
		,isnull(sum(d.DipsCost*d.Quantity),0)[ExtCost]
		,isnull(sum(pm.Price*d.Quantity),0)[ExtList]
	from ReportsData..SipsTransferBinHeader as h 
		inner join ReportsData..SipsTransferBinDetail as d on h.TransferBinNo = d.TransferBinNo 
		inner join Reportsdata..ProductMaster pm with(nolock) on d.DipsItemCode = pm.ItemCode
		inner join #minDts m on h.UpdateTime >= m.minDt and h.UpdateTime < m.endDt
		inner join #stores s on h.ToLocationNo = s.LocNo
		left  join #excludes e on pm.ItemCode = e.ItemCode
	where pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
		and h.StatusCode = 3
		and h.TransferType = 3
		and d.StatusCode = 1
		and e.ItemCode is null
	group by m.minDt
		,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
		,h.ToLocationNo
		,ltrim(rtrim(pm.SectionCode))
		,d.DipsItemCode
	)
--All Transfers together-------
----Joined up by itemcode cos StS
--   drop table #xfers
select isnull(xf.minDt,xt.minDt)[minDt]
	,isnull(xf.FromLoc,xt.ToLoc)[Loc]
	,isnull(xf.Src,xt.Src)[Src]
	,isnull(xf.Prog,xt.Prog)[Prog]
	,isnull(xf.Section,xt.Section)[Section]
	,isnull(sum(xt.RcvQty),0) - isnull(sum(xf.StSQty),0)[StSQty]
	,isnull(sum(xt.ExtCost),0) - isnull(sum(xf.StsCost),0)[StSCost]
	,isnull(sum(xt.ExtList),0) - isnull(sum(xf.StsList),0)[StSList]
	,isnull(sum(xt.RcvQty),0)[iStSQty]
	,isnull(sum(xt.ExtCost),0)[iStSCost]
	,isnull(sum(xt.ExtList),0)[iStSList]
	,isnull(sum(xf.StSQty),0)[oStSQty]
	,isnull(sum(xf.StsCost),0)[oStSCost]
	,isnull(sum(xf.StsList),0)[oStSList]
	,isnull(sum(xf.TshQty),0)[TshQty]
	,isnull(sum(xf.TshCost),0)[TshCost]
	,isnull(sum(xf.TshList),0)[TshList]
	,isnull(sum(xf.DmgQty),0)[DmgQty]
	,isnull(sum(xf.DmgCost),0)[DmgCost]
	,isnull(sum(xf.DmgList),0)[DmgList]
	,isnull(sum(xf.DntQty),0)[DntQty]
	,isnull(sum(xf.DntCost),0)[DntCost]
	,isnull(sum(xf.DntList),0)[DntList]
	,isnull(sum(xf.BsmQty),0)[BsmQty]
	,isnull(sum(xf.BsmCost),0)[BsmCost]
	,isnull(sum(xf.BsmList),0)[BsmList]
	,isnull(count(distinct case when xf.RtnQty <> 0 then xf.ItemCode end),0)[RtnIts]
	,isnull(sum(xf.RtnQty),0)[RtnQty]
	,isnull(sum(xf.RtnCost),0)[RtnCost]
	,isnull(sum(xf.RtnList),0)[RtnList]
	,isnull(sum(xf.MktQty),0)[MktQty]
	,isnull(sum(xf.MktCost),0)[MktCost]
	,isnull(sum(xf.MktList),0)[MktList]
into #xfers  --  select count(*) from #xfers
from xfersF xf full outer join xfersT xt
	on xf.Section = xt.Section and xf.FromLoc=xt.ToLoc 
		and xf.minDt = xt.minDt and xf.ItemCode = xt.ItemCode
group by isnull(xf.minDt,xt.minDt)
	,isnull(xf.FromLoc,xt.ToLoc)
	,isnull(xf.Src,xt.Src)
	,isnull(xf.Prog,xt.Prog)
	,isnull(xf.Section,xt.Section)


---------------------------------------------
--------Le GRAND LSD-------------------------
drop table if exists #LocSchemeDetails
;with MbyPbyS as(
	select md.Yr, md.Wk, md.minDt
		,st.LocNo,r.Src,p.Prog,s.section
	from #minDts md cross join #src r cross join #progs p 
		cross join #sections s cross join #stores st 
)
select mps.Yr
	,mps.Wk
	,mps.minDt
	,mps.Src
	,mps.Prog
	,mps.Section
	,mps.LocNo
	,isnull(sh.ShipNumIts,0)[ShipNumIts]
	,isnull(sh.ShipQty,0)[ShipQty]
	,isnull(sh.ShipCost,0)[ShipCost]
	,isnull(sh.ShipVal,0)[ShipVal]
	,isnull(rc.RcvNumIts,0)[RcvNumIts]
	,isnull(rc.RcvQty,0)[RcvQty]
	,isnull(rc.RcvCost,0)[RcvCost]
	,isnull(rc.RcvVal,0)[RcvVal]
	,isnull(sa.SoldNumIts,0)[SoldNumIts]
	,isnull(sa.SoldQty,0)[SoldQty]
	,isnull(sa.SoldCost,0)[SoldCost]
	,isnull(sa.SoldVal,0)[SoldVal]
	,isnull(sa.ListVal,0)[ListVal]
	,isnull(sa.mdSoldQty,0)[mdSoldQty]
	,isnull(sa.mdCost,0)[mdCost]
	,isnull(sa.mdSoldVal,0)[mdSoldVal]
	,isnull(sa.mdListVal,0)[mdListVal]
	,isnull(xr.TshQty+xr.DmgQty+xr.DntQty,0)[RfiQty]
	,isnull(xr.TshCost+xr.DmgCost+xr.DntCost,0)[RfiCost]
	,isnull(xr.TshList+xr.DmgList+xr.DntList,0)[RfiList]
	,isnull(xr.iStSQty,0)[iStSQty]
	,isnull(xr.oStSQty,0)[oStSQty]
	,isnull(xr.RtnIts,0)[RtnIts]
	,isnull(xr.RtnQty,0)[RtnQty]
	,isnull(xr.RtnCost,0)[RtnCost]
	,isnull(xr.RtnList,0)[RtnList]
into #LocSchemeDetails
from MbyPbyS mps
	left outer join #ship sh on mps.LocNo=sh.LocNum and mps.Section=sh.Section and mps.minDt=sh.minDt and mps.Src=sh.Src and mps.Prog=sh.Prog
	left outer join #sales sa on mps.LocNo=sa.LocNum and mps.Section=sa.Section and mps.minDt=sa.minDt and mps.Src=sa.Src and mps.Prog=sa.Prog
	left outer join #receiveds rc on mps.LocNo=rc.LocNum and mps.Section=rc.Section and mps.minDt=rc.minDt and mps.Src=rc.Src and mps.Prog=rc.Prog
	left outer join #xfers xr on mps.LocNo=xr.Loc and mps.Section=xr.Section and mps.minDt=xr.minDt and mps.Src=xr.Src and mps.Prog=xr.Prog



--Clearing out junk rows from the LSD--------
---------------------------------------------
drop table if exists #DateExcl
select LocNo
	,min(minDt)[minDt]
	,max(minDt)[maxDt]
into #DateExcl
from #LocSchemeDetails
where (ShipQty <> 0
	or RcvQty <> 0
	or SoldQty <> 0
	or RfiQty <> 0
	or iStSQty <> 0
	or oStSQty <> 0)
group by LocNo
order by LocNo

drop table if exists #LocnExcl
select LocNo
into #LocnExcl
from #LocSchemeDetails
group by LocNo
having sum(ShipQty+abs(SoldQty)+RfiQty) = 0

drop table if exists #SecnExcl
select Section
into #SecnExcl
from #LocSchemeDetails
group by Section
having sum(ShipQty+abs(SoldQty)+RfiQty) = 0

----Cull junk rows from the #LocSchemeDetails table
delete lsd from #LocSchemeDetails lsd
	inner join #DateExcl de on lsd.LocNo = de.LocNo 
where lsd.minDt < de.minDt or lsd.minDt > de.maxDt
delete lsd from #LocSchemeDetails lsd
where LocNo in (select distinct LocNo from #LocnExcl)
delete lsd from #LocSchemeDetails lsd
where Section in (select distinct Section from #SecnExcl)


----Transaction 1--------------------------------
--Add good rows to ShpSld_FrlnSrcPrg-------------[
-----------------------------------------------[
BEGIN TRY
	begin transaction
	
	insert into ReportsView.dbo.ShpSld_FrlnSrcPrg
	select l.*
	from #LocSchemeDetails l
		left join ReportsView.dbo.ShpSld_FrlnSrcPrg s on l.minDt = s.minDt and l.Section = s.Section
		and l.Src = s.Src and l.Prog = s.Prog and l.LocNo = s.LocNo
	where s.minDt is null

	commit transaction
END TRY
BEGIN CATCH
	if @@trancount > 0 rollback transaction
	declare @msg1 nvarchar(2048) = error_message()  
	raiserror (@msg1, 16, 1)
END CATCH
-----------------------------------------------]
------------------------------------------------]

----clean up....
drop table if exists #dates
drop table if exists #stores
drop table if exists #sections
drop table if exists #src
drop table if exists #progs
drop table if exists #excludes
drop table if exists #minDts
drop table if exists #ship
drop table if exists #receiveds
drop table if exists #sales
drop table if exists #xfers
drop table if exists #ItemExcl
drop table if exists #LocnExcl
drop table if exists #DateExcl
drop table if exists #LocSchemeDetails


/*
-- For testing replacement code...
select *
from #LocSchemeDetails
except
select *
from ReportsView..ShpSld_FrlnSrcPrg s
where exists (select minDt from #minDts m where m.minDt = s.minDt)
*/
GO
