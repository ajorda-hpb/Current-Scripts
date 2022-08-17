SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[ShpSld_BI_UPDATE]
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
	--Closed/Inactive Stores
	and LocationNo not in ('00027','00028','00042','00060','00063','00079','00089','00092','00093','00101')

----build a table with capped product types
drop table if exists #BaseInvIts
select pm.ItemCode
	,ltrim(rtrim(pm.ProductType))[PrTy]
	--Map Buy product types to ONE item code. The below items are other base inv items with the same product type as the designated "BuySafe" item code.
	,case when pm.ItemCode not in ('00000000000000005766','00000000000000005780','00000000000000005782','00000000000000005783'
									,'00000000000000005781','00000000000000005786','00000000000000005785','00000000000000005801') then 1 else 0 end[BuySafe]
into #BaseInvIts  --  select ItemCode,Title,ltrim(rtrim(pm.ProductType))
from ReportsView.dbo.vw_DistributionProductMaster pm with(nolock)
where (pm.ItemCode in (select distinct ItemCode from [ReportsView].[dbo].[vw_BaseInventory] with(nolock)) 
		or pm.ItemCode in ('00000000000010058656','00000000000010058657','00000000000010058658'  --Misc Used not in the BaseInv table (MediaPlayer,Tablet,Phone)
						  ,'00000000000010017201','00000000000010017202','00000000000010041275'  --More Used  (Boardgames,Puzzles,Electronics)
						  ,'00000000000010017203','00000000000010017200'))						 --& more Used (GameSystem,Textbooks)

--Build table of each week & its Yr/Wk/MinDate
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


-----------------------------------
--used data from vw_BuyDetail
drop table if exists #buys
select m.minDt
	,bi.ItemCode
	,bd.LocationNo[LocNo]
	,sum(bd.Quantity)[BuyQty]
    ,sum(bd.LineOffer)[BuyCost]
into #buys 
from ReportsView.dbo.vw_BuyDetail bd with(nolock)
	inner join #BaseInvIts bi on ltrim(rtrim(bd.BuyType)) = bi.PrTy and bi.BuySafe = 1
	inner join #minDts m on bd.EndDate >= m.minDt and bd.EndDate < m.endDt
    inner join #stores s on bd.LocationNo = s.LocNo
where bd.Status = 'A'
	and bd.Quantity > 0
	and bd.TotalOffer < 600000
group by m.minDt
	,bd.LocationNo
	,bi.ItemCode

----------------------------------
----get all the sales data....
drop table if exists #sales
;with HpbSales as(
	select * from HPB_SALES..SIH2021 with(nolock)
	union all select * from HPB_SALES..SIH2022 with(nolock)
)
select m.minDt
	,bi.ItemCode
	,loc.LocationNo as LocNo
	--total sales.............................................................................
	,isnull(sum(case sd.isreturn when 'y' then -sd.quantity else sd.quantity end),0)[SoldQty]
	,isnull(sum(sd.extendedamt),0)[SoldVal]
	--markdown sales...........................................................................
	,isnull(sum(case 
				when sd.isreturn='y' and sd.RegisterPrice < sd.UnitPrice then -sd.quantity 
				when sd.isreturn='n' and sd.RegisterPrice < sd.UnitPrice then  sd.quantity 
				else 0 end),0)[mdSoldQty]
	,isnull(sum(case
				when (sd.isreturn='y' and sd.RegisterPrice < sd.UnitPrice) 
				  or (sd.isreturn='n' and sd.RegisterPrice < sd.UnitPrice) then sd.extendedamt 
				else 0 end),0)[mdSoldVal]
into #sales
from HpbSales sd with(nolock)
	inner join ReportsView.dbo.location loc on sd.LocationID=loc.LocationID
	inner join #BaseInvIts bi on sd.ItemCode = bi.ItemCode
	inner join #minDts m on sd.BusinessDate >= m.minDt and sd.BusinessDate < m.endDt
    inner join #stores s on loc.LocationNo = s.LocNo
where sd.Status = 'A'
group by m.minDt
	,bi.ItemCode
	,loc.LocationNo

----get all transfers to trash data.........................
drop table if exists #xfers

;with xfersF as(   --Item FROM a location...
    select m.minDt
        ,bi.ItemCode
        ,h.LocationNo[FromLoc]
        ,isnull(sum(case when h.TransferType = 1 then d.Quantity else 0 end),0)[TshQty]
        ,isnull(sum(case when h.TransferType = 1 then d.DipsCost*d.Quantity else 0 end),0)[TshCost]
        ,isnull(sum(case when h.TransferType = 7 then d.Quantity else 0 end),0)[DmgQty]
        ,isnull(sum(case when h.TransferType = 7 then d.DipsCost*d.Quantity else 0 end),0)[DmgCost]
        ,isnull(sum(case when h.TransferType = 3 then d.Quantity else 0 end),0)[StSQty]
        ,isnull(sum(case when h.TransferType = 3 then d.DipsCost*d.Quantity else 0 end),0)[StSCost]
        ,isnull(sum(case when h.TransferType = 2 then d.Quantity else 0 end),0)[DntQty]
        ,isnull(sum(case when h.TransferType = 2 then d.DipsCost*d.Quantity else 0 end),0)[DntCost]
        ,isnull(sum(case when h.TransferType = 4 then d.Quantity else 0 end),0)[BsmQty]
        ,isnull(sum(case when h.TransferType = 4 then d.DipsCost*d.Quantity else 0 end),0)[BsmCost]
        ,isnull(sum(case when h.TransferType = 6 then d.Quantity else 0 end),0)[RtnQty]
        ,isnull(sum(case when h.TransferType = 6 then d.DipsCost*d.Quantity else 0 end),0)[RtnCost]
        ,isnull(sum(case when h.TransferType = 5 then d.Quantity else 0 end),0)[MktQty]
        ,isnull(sum(case when h.TransferType = 5 then d.DipsCost*d.Quantity else 0 end),0)[MktCost]
    from ReportsData..SipsTransferBinHeader as h 
		inner join ReportsData..SipsTransferBinDetail as d on h.TransferBinNo = d.TransferBinNo 
        inner join #BaseInvIts bi on d.DipsItemCode = bi.ItemCode
        inner join #minDts m on h.UpdateTime >= m.minDt and h.UpdateTime < m.endDt
        inner join #stores s on h.LocationNo = s.LocNo
    where h.StatusCode = 3
        and h.TransferType in (1,2,3,4,5,6,7)
        and d.StatusCode = 1
        and not(d.DipsCost > '75' and (d.DipsCost / d.Quantity) < '50')
        and d.Quantity < '1000'
        and d.DipsCost < '500'
    group by m.minDt
        ,h.LocationNo 
        ,bi.ItemCode
)
,xfersT as(  --Items TO a location...
    select m.minDt
        ,h.ToLocationNo[ToLoc]
        ,bi.ItemCode
        ,isnull(sum(d.Quantity),0)[RcvQty]
        ,isnull(sum(d.DipsCost*d.Quantity),0)[ExtCost]
    from ReportsData..SipsTransferBinHeader as h 
		inner join ReportsData..SipsTransferBinDetail as d on h.TransferBinNo = d.TransferBinNo 
        inner join #BaseInvIts bi on d.DipsItemCode = bi.ItemCode
        inner join #minDts m on h.UpdateTime >= m.minDt and h.UpdateTime < m.endDt
        inner join #stores s on h.ToLocationNo = s.LocNo
    where h.StatusCode = 3
        and h.TransferType = 3
        and d.StatusCode = 1
        and not(d.DipsCost > '75' and (d.DipsCost / d.Quantity) < '50')
        and d.Quantity < '1000'
        and d.DipsCost < '500'
    group by m.minDt
        ,h.ToLocationNo
        ,bi.ItemCode
) --All Transfers together...
select isnull(xf.minDt,xt.minDt)[minDt]
	,isnull(xf.FromLoc,xt.ToLoc)[LocNo]
	,isnull(xf.ItemCode,xt.ItemCode)[ItemCode]
	,isnull(sum(xt.RcvQty),0) - isnull(sum(xf.StSQty),0)[StSQty]
	,isnull(sum(xt.ExtCost),0) - isnull(sum(xf.StsCost),0)[StSCost]
	,isnull(sum(xt.RcvQty),0)[iStSQty]
	,isnull(sum(xt.ExtCost),0)[iStSCost]
	,isnull(sum(xf.StSQty),0)[oStSQty]
	,isnull(sum(xf.StsCost),0)[oStSCost]
	,isnull(sum(xf.TshQty),0)[TshQty]
	,isnull(sum(xf.TshCost),0)[TshCost]
	,isnull(sum(xf.DmgQty),0)[DmgQty]
	,isnull(sum(xf.DmgCost),0)[DmgCost]
	,isnull(sum(xf.DntQty),0)[DntQty]
	,isnull(sum(xf.DntCost),0)[DntCost]
	,isnull(sum(xf.BsmQty),0)[BsmQty]
	,isnull(sum(xf.BsmCost),0)[BsmCost]
	,isnull(sum(xf.RtnQty),0)[RtnQty]
	,isnull(sum(xf.RtnCost),0)[RtnCost]
	,isnull(sum(xf.MktQty),0)[MktQty]
	,isnull(sum(xf.MktCost),0)[MktCost]
into #xfers 
from xfersF xf full outer join xfersT xt
	on xf.minDt = xt.minDt and xf.FromLoc=xt.ToLoc and xf.ItemCode = xt.ItemCode
group by isnull(xf.minDt,xt.minDt)
	,isnull(xf.FromLoc,xt.ToLoc)
	,isnull(xf.ItemCode,xt.ItemCode)

-----------------------------------
----EVERYTHING all together now....
drop table if exists #LSD_BaseInv
;with MbyPbyS as(
	select md.Yr, md.Wk, md.minDt, st.LocNo, b.ItemCode
	from #minDts md cross join #stores st cross join #BaseInvIts b
)
select mps.Yr
	,mps.Wk
	,mps.minDt
	,mps.ItemCode
	,mps.LocNo
	,isnull(b.BuyQty,0)[BuyQty]
	,isnull(b.BuyCost,0)[BuyCost]
	,isnull(sa.SoldQty,0)[SoldQty]
	,isnull(sa.SoldVal,0)[SoldVal]
	,isnull(sa.mdSoldQty,0)[mdSoldQty]
	,isnull(sa.mdSoldVal,0)[mdSoldVal]
	,isnull(xr.TshQty+xr.DmgQty+xr.DntQty,0)[RfiQty]
	,isnull(xr.TshCost+xr.DmgCost+xr.DntCost,0)[RfiCost]
	,isnull(xr.iStSQty,0)[iStSQty]
	,isnull(xr.oStSQty,0)[oStSQty]
	,isnull(xr.BsmQty,0)[BsmQty]
	,isnull(xr.BsmCost,0)[BsmCost]
into #LSD_BaseInv
from MbyPbyS mps
	left outer join #buys   b on mps.minDt =  b.minDt and mps.LocNo =  b.LocNo and mps.ItemCode = b.ItemCode
	left outer join #sales sa on mps.minDt = sa.minDt and mps.LocNo = sa.LocNo and mps.ItemCode = sa.ItemCode
	left outer join #xfers xr on mps.minDt = xr.minDt and mps.LocNo = xr.LocNo and mps.ItemCode = xr.ItemCode

--Limit LSD records to only when each store was open.
drop table if exists #limits
select LocNo
	,min(minDt)[minDt]
	,max(minDt)[maxDt]
into #limits
from #LSD_BaseInv
where (BuyQty <> 0
	or SoldQty <> 0
	or RfiQty <> 0
	or iStSQty <> 0
	or oStSQty <> 0
	or mdSoldQty <> 0)
	and LocNo in (select distinct LocNo from #stores)
group by LocNo
order by LocNo


----Transaction 1--------------------------------
--Add good rows to ShpSld_BI---------------------[
-----------------------------------------------[
BEGIN TRY
	begin transaction
	
	insert into ReportsView.dbo.ShpSld_BI
	select lsd.*
	from #LSD_BaseInv lsd
		inner join #limits li on lsd.LocNo = li.LocNo 
		left join ReportsView.dbo.ShpSld_BI ss 
			on ss.minDt = lsd.minDt and ss.ItemCode = lsd.ItemCode and ss.LocNo = lsd.LocNo 
	where ss.minDt is null
		and lsd.minDt >= li.minDt
		and lsd.minDt <= li.maxDt
		and lsd.LocNo not in ('00020','00027','00028','00042','00060','00063','00079','00089','00092','00093','00101','00106')

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
drop table if exists #LSD_BaseInv
drop table if exists #limits
drop table if exists #buys
drop table if exists #sales
drop table if exists #xfers
drop table if exists #BaseInvIts
drop table if exists #minDts
drop table if exists #stores
drop table if exists #dates

GO
