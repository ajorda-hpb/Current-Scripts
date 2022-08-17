SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[ShpSld_fEAN_UPDATE]
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
    ,sd.ItemCode
	,ISNULL(sum(sd.Qty*sd.CostEach),0)[ShipCost]
	,ISNULL(sum(sd.Qty),0)[ShipQty]
	,ISNULL(sum(sd.Qty*pm.Price),0)[ShipVal]
into #ship
from ReportsData..ShipmentHeader sh with(nolock)
	inner join ReportsData..ShipmentDetail sd with(nolock) on sh.TransferID = sd.TransferID
	inner join ReportsData..ProductMaster pm with(nolock) on pm.ItemCode=sd.ItemCode 
	inner join #minDts m on sh.DateTransferred >= m.minDt and sh.DateTransferred < m.endDt
    left  join #excludes e on sd.ItemCode = e.ItemCode
where sh.FromLocationNo='00944' 
	and e.ItemCode is null
    and pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
    -- and ltrim(rtrim(pm.UserChar30)) <> 'F'
group by m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
	,ltrim(rtrim(pm.SectionCode))
	,sh.ToLocationNo
    ,sd.ItemCode

----New Goods Store Receiving-----------------
----------------------------------------------
drop table if exists #receiveds
select m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end[Src]
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end[Prog]
	,ltrim(rtrim(pm.SectionCode)) as Section
	,sh.LocationNo as LocNum
    ,sd.ItemCode
	,ISNULL(sum(sd.Qty*pm.Cost),0)[RcvCost]
	,ISNULL(sum(sd.Qty),0)[RcvQty]
	,ISNULL(sum(sd.Qty*pm.Price),0)[RcvVal]
into #receiveds
from ReportsData.dbo.SR_Header sh  with(nolock) 
	inner join ReportsData.dbo.SR_Detail sd  with(nolock) on sh.BatchID = sd.BatchID 
	inner join ReportsData..ProductMaster pm with(nolock) on pm.ItemCode=sd.ItemCode 
	inner join #minDts m on sd.ProcessDate >= m.minDt and sd.ProcessDate < m.endDt
    left  join #excludes e on sd.ItemCode = e.ItemCode
where pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
    -- and ltrim(rtrim(pm.UserChar30)) <> 'F'
	and sh.ShipmentType in ('R','W')
	and e.ItemCode is null
group by m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
	,ltrim(rtrim(pm.SectionCode))
	,sh.LocationNo
    ,sd.ItemCode


----New Goods Sales---------------------------
----------------------------------------------
drop table if exists #sales_store
;with HpbSales as(
	select * from HPB_SALES..SIH2021 with(nolock)
	union all select * from HPB_SALES..SIH2022 with(nolock)
)
select m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end[Src]
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end[Prog]
	,ltrim(rtrim(pm.SectionCode)) as Section
	,loc.LocationNo as LocNum
    ,sd.ItemCode
	-- ,isnull(count(distinct sd.ItemCode),0)[SoldNumIts]
	--total sales.............................................................................
	,isnull(sum(case sd.isreturn when 'y' then -sd.quantity else sd.quantity end),0)[SoldQty]
	,isnull(sum(case sd.isreturn when 'y' then -pm.cost else pm.cost end),0)[SoldCost]
	,isnull(sum(sd.extendedamt),0)[SoldVal]
	,isnull(sum(case sd.isreturn when 'y' then -sd.UnitPrice else sd.UnitPrice end),0)[ListVal]
	-- -- actual sales excl returns...............................................................
	-- ,isnull(sum(case sd.isreturn when 'n' then sd.quantity else 0 end),0)[SoldQty]
	-- ,isnull(sum(case sd.isreturn when 'n' then pm.cost else 0 end),0)[SoldCost]
	-- ,isnull(sum(sd.extendedamt),0)[SoldVal]
	-- ,isnull(sum(case sd.isreturn when 'n' then sd.UnitPrice else 0 end),0)[ListVal]
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
	--returned sales.............................................................................
	,isnull(sum(case sd.isreturn when 'y' then sd.quantity else 0 end),0)[RfndQty]
	,isnull(sum(case sd.isreturn when 'y' then pm.cost else 0 end),0)[RfndCost]
	,isnull(sum(case sd.isreturn when 'y' then -sd.extendedamt else 0 end),0)[RfndVal]
	,isnull(sum(case sd.isreturn when 'y' then sd.UnitPrice else 0 end),0)[RfndListVal]
into #sales_store
from HpbSales sd
	inner join ReportsData..ProductMaster pm with(nolock) on pm.ItemCode=sd.ItemCode 
	inner join ReportsData..Locations loc with(nolock) on sd.LocationID=loc.LocationID
	inner join #minDts m on sd.BusinessDate >= m.minDt and sd.BusinessDate < m.endDt
    left  join #excludes e on sd.ItemCode = e.ItemCode
where pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
    -- and ltrim(rtrim(pm.UserChar30)) <> 'F'
	and sd.Status = 'A'
	and e.ItemCode is null
group by m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
	,ltrim(rtrim(pm.SectionCode))
	,loc.LocationNo
    ,sd.ItemCode
    
    
--HPB.com Sales----------------------
drop table if exists #sales_online
select m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end[Src]
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end[Prog]
	,ltrim(rtrim(pm.SectionCode)) as Section
    ,'s'[Dir]
    ,'h'[Site]
    ,fa.HPBLocationNo[LocNo]
	,pm.ItemCode
	,sum(od.Quantity)[SoldQty]
	,sum(pm.Cost * od.Quantity)[SoldCost]
	,sum(od.ExtendedAmount)[SoldVal]
    ,sum(pm.Price * od.Quantity)[SoldList]
	,sum(od.ShippingAmount)[SoldFee]
	,sum(case when od.ItemPrice < pm.Price then od.Quantity else 0 end)[mdSoldQty]
	,sum(case when od.ItemPrice < pm.Price then pm.Cost * od.Quantity else 0 end)[mdSoldCost]
	,sum(case when od.ItemPrice < pm.Price then od.ExtendedAmount else 0 end)[mdSoldVal]
    ,sum(case when od.ItemPrice < pm.Price then pm.Price * od.Quantity else 0 end)[mdSoldList]
	,sum(case when od.ItemPrice < pm.Price then od.ShippingAmount else 0 end)[mdSoldFee]
    ,cast(null as money)[RfndAmt] --summed separately b/c of specific refund timestamps
    ,count(distinct od.MarketOrderID)[NumOrds]
into #sales_online
from isis..Order_Omni od with(nolock)
	inner join isis..App_Facilities fa with(nolock) on od.FacilityID = fa.FacilityID
	inner join ReportsData..ProductMaster pm with(nolock) on right(od.SKU,20) = pm.ItemCode
	inner join #minDts m on od.OrderDate >= m.minDt and od.OrderDate < m.endDt
    left  join #excludes e on pm.ItemCode = e.ItemCode
where od.OrderStatus not in ('canceled')
	and od.ItemStatus not in ('canceled')
	and left(od.SKU,1) = 'D'
	and od.Quantity > 0
    and pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
	and e.ItemCode is null
    -- and ltrim(rtrim(pm.UserChar30)) <> 'F'
group by m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
	,ltrim(rtrim(pm.SectionCode)) 
    ,fa.HPBLocationNo
	,pm.ItemCode

--HPB.com Refunds--------------------
insert into #sales_online
select m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end[Src]
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end[Prog]
	,ltrim(rtrim(pm.SectionCode)) as Section
    ,'r'[Dir]
    ,'h'[Site]
    ,fa.HPBLocationNo[LocNo]
	,pm.ItemCode
	--Same idea... don't think we actually get the thing back to the store.
	,sum(od.Quantity)[SoldQty]
	,sum(pm.Cost * od.Quantity)[SoldCost]
	,sum(od.ExtendedAmount)[SoldVal]
    ,sum(pm.Price * od.Quantity)[SoldList]
	,sum(od.ShippingAmount)[SoldFee]
	,sum(case when od.ItemPrice < pm.Price then od.Quantity else 0 end)[mdSoldQty]
	,sum(case when od.ItemPrice < pm.Price then pm.Cost * od.Quantity else 0 end)[mdSoldCost]
	,sum(case when od.ItemPrice < pm.Price then od.ExtendedAmount else 0 end)[mdSoldVal]
    ,sum(case when od.ItemPrice < pm.Price then pm.Price * od.Quantity else 0 end)[mdSoldList]
	,sum(case when od.ItemPrice < pm.Price then od.ShippingAmount else 0 end)[mdSoldFee]
    ,sum(od.ItemRefundAmount)[RfndAmt]
    ,count(distinct od.MarketOrderID)[NumOrds]
from isis..Order_Omni od with(nolock)
	inner join isis..App_Facilities fa with(nolock) on od.FacilityID = fa.FacilityID
	inner join ReportsData..ProductMaster pm with(nolock) on right(od.SKU,20) = pm.ItemCode
	inner join #minDts m on od.SiteLastModifiedDate >= m.minDt and od.SiteLastModifiedDate < m.endDt
    left  join #excludes e on pm.ItemCode = e.ItemCode
where od.ItemStatus not in ('canceled')
	and od.OrderStatus not in ('canceled')								  
	and left(od.SKU,1) = 'D'
	and od.Quantity > 0
	and od.ItemRefundAmount > 0
    and pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
    -- and ltrim(rtrim(pm.UserChar30)) <> 'F'
	and e.ItemCode is null
group by m.minDt
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
	,ltrim(rtrim(pm.SectionCode)) 
    ,fa.HPBLocationNo
	,pm.ItemCode

-- Combine Store & Online Sales into one table
----------------------------------------------
drop table if exists #sales
;with its as(
	select distinct ItemCode from #sales_store
	union select distinct ItemCode from #sales_online
)
select md.Yr,md.Wk,md.minDt
	,st.LocNo
	,coalesce(ss.Src,so.Src)[Src]
	,coalesce(ss.Prog,so.Prog)[Prog]
	,it.ItemCode
	,sum(isnull(ss.SoldQty,0))[StSoldQty]
	,sum(isnull(ss.SoldVal,0))[StSoldVal]
	,sum(isnull(ss.mdSoldQty,0))[mdStSoldQty]
	,sum(isnull(ss.mdSoldVal,0))[mdStSoldVal]
	,sum(isnull(ss.RfndQty,0))[StRfndQty]
	,sum(isnull(ss.RfndVal,0))[StRfndVal]
	,sum(isnull(case when so.Dir = 's' then so.SoldQty end,0))[OnlSoldQty]
	-- Because online sales have the refund data (dollars + date) on the sales line, not on its own line
	,sum(isnull(case when so.Dir = 's' then so.SoldVal end,0)-isnull(case when so.Dir = 'r' then so.RfndAmt end,0))[OnlSoldVal]
	,sum(isnull(case when so.Dir = 's' then so.SoldFee end,0))[OnlSoldFee]
	,sum(isnull(case when so.Dir = 's' then so.mdSoldQty end,0))[mdOnlSoldQty]
	,sum(isnull(case when so.Dir = 's' then so.mdSoldVal end,0)-isnull(case when so.Dir = 'r' then so.RfndAmt end,0))[mdOnlSoldVal]
	,sum(isnull(case when so.Dir = 's' then so.mdSoldFee end,0))[mdOnlSoldFee]
	,sum(isnull(case when so.Dir = 'r' then so.SoldQty end,0))[OnlRfndQty]
	,sum(isnull(case when so.Dir = 'r' then so.RfndAmt end,0))[OnlRfndVal]
into #sales
from #minDts md cross join #stores st cross join its it
	left join #sales_store ss on md.minDt = ss.minDt and st.LocNo = ss.LocNum and it.ItemCode = ss.ItemCode
	left join #sales_online so on md.minDt = so.minDt and st.LocNo = so.LocNo and it.ItemCode = so.ItemCode
where ss.ItemCode is not null or so.ItemCode is not null
group by md.Yr,md.Wk,md.minDt
	,st.LocNo
	,coalesce(ss.Src,so.Src)
	,coalesce(ss.Prog,so.Prog)
	,it.ItemCode


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
        left  join #excludes e on pm.ItemCode = e.ItemCode
	where e.ItemCode is null
		and pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
        -- and ltrim(rtrim(pm.UserChar30)) <> 'F'
		and h.StatusCode = 3
		and h.TransferType in (1,2,3,4,5,6,7)
		and d.StatusCode = 1
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
        left  join #excludes e on pm.ItemCode = e.ItemCode
	where e.ItemCode is null 
		and pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
        -- and ltrim(rtrim(pm.UserChar30)) <> 'F'
		and h.StatusCode = 3
		and h.TransferType = 3
		and d.StatusCode = 1
	group by m.minDt
		,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end
	    ,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end
		,h.ToLocationNo
		,ltrim(rtrim(pm.SectionCode))
		,d.DipsItemCode
	)
--All Transfers together-------
select isnull(xf.minDt,xt.minDt)[minDt]
	,isnull(xf.FromLoc,xt.ToLoc)[Loc]
	,isnull(xf.Src,xt.Src)[Src]
	,isnull(xf.Prog,xt.Prog)[Prog]
	,isnull(xf.Section,xt.Section)[Section]
    ,isnull(xf.ItemCode,xt.ItemCode)[ItemCode]
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
into #xfers  
from xfersF xf full outer join xfersT xt
	on xf.Section = xt.Section and xf.FromLoc=xt.ToLoc 
		and xf.minDt = xt.minDt and xf.ItemCode = xt.ItemCode
group by isnull(xf.minDt,xt.minDt)
	,isnull(xf.FromLoc,xt.ToLoc)
	,isnull(xf.Src,xt.Src)
	,isnull(xf.Prog,xt.Prog)
	,isnull(xf.Section,xt.Section)
    ,isnull(xf.ItemCode,xt.ItemCode)


-- Collect distinct list of ItemCodes & match up to ISBNs-----------------
--------------------------------------------------------------------------
drop table if exists #ISBNs
;with items as (
    select Src,Prog,ItemCode
    from #Ship
    group by Src,Prog,ItemCode
    union select Src,Prog,ItemCode
    from #receiveds
    group by Src,Prog,ItemCode
    union select Src,Prog,ItemCode
    from #sales 
    group by Src,Prog,ItemCode
    union select Src,Prog,ItemCode
    from #xfers
    group by Src,Prog,ItemCode
)
select it.Src,it.Prog,it.ItemCode
    ,pm.ISBN
    ,pm.UPC
    ,coalesce(nullif(pm.ISBN,''),nullif(substring(pm.UPC,1,13),''))[EAN]
into #ISBNs
from items it 
	inner join ReportsView..vw_DistributionProductMaster pm with(nolock)
        on it.itemcode = pm.itemcode


---------------------------------------------
--------Le GRAND LSD-------------------------
drop table if exists #LocSchemeDetails
;with MbyPbyS as(
    select md.Yr, md.Wk, md.minDt,st.LocNo
        ,i.EAN,i.ItemCode,i.Src,i.Prog
    from #minDts md cross join #stores st cross join #ISBNs i
)
select mps.Yr
	,mps.Wk
	,mps.minDt
	,mps.EAN
    ,mps.ItemCode
    ,mps.Src
	,mps.Prog
	,mps.LocNo
	-- ,isnull(sh.ShipNumIts,0)[ShipNumIts]
	,isnull(sh.ShipQty,0)[ShipQty]
	,isnull(sh.ShipCost,0)[ShipCost]
	,isnull(sh.ShipVal,0)[ShipVal]
	-- ,isnull(rc.RcvNumIts,0)[RcvNumIts]
	,isnull(rc.RcvQty,0)[RcvQty]
	,isnull(rc.RcvCost,0)[RcvCost]
	,isnull(rc.RcvVal,0)[RcvVal]
	-- ,isnull(sa.SoldNumIts,0)[StSoldNumIts]
	,isnull(sa.StSoldQty,0)[StSoldQty]
	,isnull(sa.StSoldVal,0)[StSoldVal]
	,isnull(sa.mdStSoldQty,0)[mdStSoldQty]
	,isnull(sa.mdStSoldVal,0)[mdStSoldVal]
	,isnull(sa.StRfndQty,0)[StRfndQty]
	,isnull(sa.StRfndVal,0)[StRfndVal]
	,isnull(sa.OnlSoldQty,0)[OnlSoldQty]
	,isnull(sa.OnlSoldVal,0)[OnlSoldVal]
	,isnull(sa.OnlSoldFee,0)[OnlSoldFee]
	,isnull(sa.mdOnlSoldQty,0)[mdOnlSoldQty]
	,isnull(sa.mdOnlSoldVal,0)[mdOnlSoldVal]
	,isnull(sa.OnlSoldFee,0)[mdOnlSoldFee]
	,isnull(sa.OnlRfndQty,0)[OnlRfndQty]
	,isnull(sa.OnlRfndVal,0)[OnlRfndVal]
	,isnull(xr.TshQty+xr.DmgQty+xr.DntQty,0)[RfiQty]
	,isnull(xr.TshCost+xr.DmgCost+xr.DntCost,0)[RfiCost]
	,isnull(xr.TshList+xr.DmgList+xr.DntList,0)[RfiList]
	,isnull(xr.iStSQty,0)[iStSQty]
	,isnull(xr.oStSQty,0)[oStSQty]
	-- ,isnull(xr.RtnIts,0)[vRtnIts]
	,isnull(xr.RtnQty,0)[vRtnQty]
	,isnull(xr.RtnCost,0)[vRtnCost]
	,isnull(xr.RtnList,0)[vRtnList]
into #LocSchemeDetails
from MbyPbyS mps
	left outer join #ship sh on mps.LocNo=sh.LocNum and mps.ItemCode=sh.ItemCode and mps.minDt=sh.minDt 
	left outer join #sales sa on mps.LocNo=sa.LocNo and mps.ItemCode=sa.ItemCode and mps.minDt=sa.minDt 
	left outer join #receiveds rc on mps.LocNo=rc.LocNum and mps.ItemCode=rc.ItemCode and mps.minDt=rc.minDt 
	left outer join #xfers xr on mps.LocNo=xr.Loc and mps.ItemCode=xr.ItemCode and mps.minDt=xr.minDt 
where coalesce(sh.LocNum,sa.LocNo,rc.LocNum,xr.Loc) is not null

delete from #LocSchemeDetails
where (ShipQty = 0
	and RcvQty = 0
	and StSoldQty = 0
    and mdStSoldQty = 0
	and StRfndQty = 0
	and OnlSoldQty = 0
    and mdOnlSoldQty = 0
	and OnlRfndQty = 0
	and RfiQty = 0
	and iStSQty = 0
	and oStSQty = 0
    and vRtnQty = 0
    and StSoldVal = 0
    and StRfndVal = 0
    and OnlSoldVal = 0
    and OnlRfndVal = 0)


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
	or StSoldQty <> 0
    or mdStSoldQty <> 0
	or StRfndQty <> 0
	or OnlSoldQty <> 0
    or mdOnlSoldQty <> 0
	or OnlRfndQty <> 0
	or RfiQty <> 0
	or iStSQty <> 0
	or oStSQty <> 0
    or vRtnQty <> 0
    or StSoldVal <> 0
    or StRfndVal <> 0
    or OnlSoldVal <> 0
    or OnlRfndVal <> 0)
group by LocNo
order by LocNo

drop table if exists #LocnExcl
select LocNo
into #LocnExcl
from #LocSchemeDetails
group by LocNo
having sum(ShipQty+RcvQty+abs(StSoldQty)+abs(OnlSoldQty)+abs(StRfndQty)+abs(OnlRfndQty)+RfiQty+iStSQty+oStSQty+vRtnQty) = 0

drop table if exists #ItemExcl
select ItemCode
into #ItemExcl
from #LocSchemeDetails
group by ItemCode
having sum(ShipQty+RcvQty+abs(StSoldQty)+abs(OnlSoldQty)+abs(StRfndQty)+abs(OnlRfndQty)+RfiQty+iStSQty+oStSQty+vRtnQty) = 0

----Cull junk rows from the #LocSchemeDetails table
delete lsd from #LocSchemeDetails lsd
	inner join #DateExcl de on lsd.LocNo = de.LocNo 
where lsd.minDt < de.minDt or lsd.minDt > de.maxDt
delete lsd from #LocSchemeDetails lsd
where LocNo in (select distinct LocNo from #LocnExcl)
delete lsd from #LocSchemeDetails lsd
where ItemCode in (select distinct ItemCode from #ItemExcl)



----Transaction 1--------------------------------
--Add good rows to ShpSld_-------------------[
-----------------------------------------------[
BEGIN TRY
	begin transaction

	insert into ReportsView.dbo.ShpSld_fEAN
	select l.*
	from #LocSchemeDetails l 
		left join ReportsView.dbo.ShpSld_fEAN s on l.minDt = s.minDt and l.ItemCode = s.ItemCode and l.LocNo = s.LocNo 
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
drop table if exists #sections
drop table if exists #progs
drop table if exists #src
drop table if exists #stores
drop table if exists #excludes
drop table if exists #minDts
drop table if exists #ship
drop table if exists #receiveds
drop table if exists #sales
drop table if exists #xfers
drop table if exists #LocSchemeDetails
drop table if exists #ItemExcl
drop table if exists #LocnExcl
drop table if exists #DateExcl
drop table if exists #ISBNs
drop table if exists #sales_store
drop table if exists #sales_online



/*
-- For testing replacement code...
select *
from #LocSchemeDetails
except
select *
from ReportsView..ShpSld_fEAN s
where exists (select minDt from #minDts m where m.minDt = s.minDt)
*/

GO
