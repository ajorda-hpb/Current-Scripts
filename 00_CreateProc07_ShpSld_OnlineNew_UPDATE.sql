SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[ShpSld_OnlineNew_UPDATE]
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

-- ----Set start & end dates
-- drop table if exists #dates
-- select '9/27/20'[sDate]
-- 	,'11/15/20'[eDate]
-- into #dates

--build table of each week & its Yr/Wk/MinDate
drop table if exists #minDts
select dc.shpsld_year[Yr]
	,dc.shpsld_week[Wk]
	,dc.calendar_date[minDt]
    ,dateadd(DD,7,dc.calendar_date)[endDt]
	,(case when datepart(WEEK, dc.calendar_date) = 53 and datepart(YEAR, dc.calendar_date) >= 2017 then datepart(YEAR, dc.calendar_date)+1 
			 when datepart(WEEK, dc.calendar_date) = 1 and datepart(YEAR, dc.calendar_date) < 2017 then datepart(YEAR, dc.calendar_date)-1 
			 else datepart(YEAR, dc.calendar_date) end)[oYr]
	,(case when datepart(WEEK, dc.calendar_date) = 53 and datepart(YEAR, dc.calendar_date) >= 2017 then 1 
			 when datepart(WEEK, dc.calendar_date) = 1 and datepart(YEAR, dc.calendar_date) < 2017 then 52 
			 else datepart(WEEK, dc.calendar_date) - case when datepart(YEAR, dc.calendar_date) < 2017 then 1 else 0 end end)[oWk]
into #minDts
from #dates d inner join ReportsView..DayCalendar dc 
    on d.sDate <= dc.calendar_date and dc.calendar_date < d.eDate 
where dc.calendar_date = dc.first_day_in_week
select * from #minDts order by minDt


----build list of stores...
drop table if exists #stores
select distinct LocationNo[LocNo]
into #stores    
from ReportsData..Locations with(nolock)
where LocationNo between '00001' and '00150'
    -- and LocationNo not in ('00020','00027','00028','00042','00060','00063','00079','00089','00092','00093','00101','00106')
 

----TEMP VARS GUYS.!-------------------------
declare @sDate smalldatetime, @eDate smalldatetime
set @sDate = (select max(sDate) from #dates)
set @eDate = (select max(eDate) from #dates)
---------------------------------------------

--HPB.com/iStore Online Sales-----------------------------------
----------------------------------------------------------------
--  declare @eDate datetime =(select max(eDate) from #dates), @sDate datetime =(select max(sDate) from #dates);
drop table if exists #online_new_prep
--iStore Sales------------------------
select (case when datepart(WEEK, om.OrderDate) = 53 and datepart(YEAR, om.OrderDate) >= 2017 then datepart(YEAR, om.OrderDate)+1 
			 when datepart(WEEK, om.OrderDate) = 1 and datepart(YEAR, om.OrderDate) < 2017 then datepart(YEAR, om.OrderDate)-1 
			 else datepart(YEAR, om.OrderDate) end)[Yr]
	,(case when datepart(WEEK, om.OrderDate) = 53 and datepart(YEAR, om.OrderDate) >= 2017 then 1 
			 when datepart(WEEK, om.OrderDate) = 1 and datepart(YEAR, om.OrderDate) < 2017 then 52 
			 else datepart(WEEK, om.OrderDate) - case when datepart(YEAR, om.OrderDate) < 2017 then 1 else 0 end end)[Wk]
	,ltrim(rtrim(pm.SectionCode)) as Section
    ,'s'[Dir]
    ,'i'[Site]
    ,it.RordGrp
    ,it.ngqVendor + case when it.ngqVendor <> 'CDC' then '' else 
							case when right(rtrim(pm.ProductType),1) = 'F' then '-f' else '-n' end end[ngqVendor]
    ,isnull(od.LocationNo,fa.HPBLocationNo)[LocNo]
	,pm.ItemCode
	,sum(om.ShippedQuantity)[SoldQty]
	-- ,sum(case when om.Price < pm.Price then om.ShippedQuantity else 0 end)[mdSoldQty]
	,sum(pm.Cost)[SoldCost]
	,sum(om.Price)[SoldVal]
	-- ,sum(case when om.Price < pm.Price then om.Price else 0 end)[mdSoldVal]
    ,sum(pm.Price)[SoldList]
	,sum(om.ShippingFee)[SoldFee]
    ,cast(0 as money)[RfndAmt] --summed separately b/c of specific refund timestamps
    ,count(distinct om.MarketOrderID)[NumOrds]
into #online_new_prep
--    select top 1000*
from isis..Order_Monsoon om with(nolock)
	inner join isis..App_Facilities fa with(nolock) on om.FacilityID = fa.FacilityID
	--pre-2014ish, SAS & XFRs would show up in Monsoon, so specifying 'MON' excludes those
	left join ofs..Order_Header oh with(nolock) on om.ISIS_OrderID = oh.ISISOrderID and oh.OrderSystem = 'MON' 
	--Grabs fulfilment location where available, otherwise uses originating location
	left join ofs..Order_Detail od with(nolock) on oh.OrderID = od.OrderID and od.Status in (1,4)
		--Problem orders have ProblemStatusID not null
		and (od.ProblemStatusID is null or od.ProblemStatusID = 0)	
	inner join #Stores loc on isnull(od.LocationNo,fa.HPBLocationNo) = loc.LocNo
	inner join ReportsData..ProductMaster pm with(nolock) on right(om.SKU,20) = pm.ItemCode
    inner join ReportsView..ProdGoals_ItemMaster it with(nolock) on pm.ItemCode = it.ItemCode
where om.ShippedQuantity > 0
	and om.OrderStatus in ('New','Pending','Shipped')
	and om.OrderDate < @eDate 
	and om.OrderDate >= @sDate 
	and left(om.SKU,1) = 'D'
group by (case when datepart(WEEK, om.OrderDate) = 53 and datepart(YEAR, om.OrderDate) >= 2017 then datepart(YEAR, om.OrderDate)+1 
			 when datepart(WEEK, om.OrderDate) = 1 and datepart(YEAR, om.OrderDate) < 2017 then datepart(YEAR, om.OrderDate)-1 
			 else datepart(YEAR, om.OrderDate) end)
	,(case when datepart(WEEK, om.OrderDate) = 53 and datepart(YEAR, om.OrderDate) >= 2017 then 1 
			 when datepart(WEEK, om.OrderDate) = 1 and datepart(YEAR, om.OrderDate) < 2017 then 52 
			 else datepart(WEEK, om.OrderDate) - case when datepart(YEAR, om.OrderDate) < 2017 then 1 else 0 end end)
	,ltrim(rtrim(pm.SectionCode))
    ,it.RordGrp
    ,it.ngqVendor + case when it.ngqVendor <> 'CDC' then '' else 
							case when right(rtrim(pm.ProductType),1) = 'F' then '-f' else '-n' end end
    ,isnull(od.LocationNo,fa.HPBLocationNo)
	,pm.ItemCode
	
--iStore Refunds---------------------
insert into #online_new_prep
select (case when datepart(WEEK, om.RefundDate) = 53 and datepart(YEAR, om.RefundDate) >= 2017 then datepart(YEAR, om.RefundDate)+1 
			 when datepart(WEEK, om.RefundDate) = 1 and datepart(YEAR, om.RefundDate) < 2017 then datepart(YEAR, om.RefundDate)-1 
			 else datepart(YEAR, om.RefundDate) end)[Yr]
	,(case when datepart(WEEK, om.RefundDate) = 53 and datepart(YEAR, om.RefundDate) >= 2017 then 1 
			 when datepart(WEEK, om.RefundDate) = 1 and datepart(YEAR, om.RefundDate) < 2017 then 52 
			 else datepart(WEEK, om.RefundDate) - case when datepart(YEAR, om.RefundDate) < 2017 then 1 else 0 end end)[Wk]
	,ltrim(rtrim(pm.SectionCode)) as Section
    ,'r'[Dir]
    ,'i'[Site]
    ,it.RordGrp
    ,it.ngqVendor + case when it.ngqVendor <> 'CDC' then '' else 
							case when right(rtrim(pm.ProductType),1) = 'F' then '-f' else '-n' end end[ngqVendor]
    ,isnull(od.LocationNo,fa.HPBLocationNo)[LocNo]
	,pm.ItemCode
	--Think refunded product doesn't go back to the store per se...
	,cast(0 as int)[SoldQty] 
	-- ,cast(0 as int)[mdSoldQty] 
	,cast(0 as money)[SoldCost]
	,cast(0 as money)[SoldVal]
	-- ,cast(0 as money)[mdSoldVal]
    ,cast(0 as money)[SoldList]
	,cast(0 as money)[SoldFee]
    ,sum(om.RefundAmount)[RfndAmt]
    ,count(distinct om.MarketOrderID)[NumOrds]
--    select top 1000*
from isis..Order_Monsoon om with(nolock)
	inner join isis..App_Facilities fa with(nolock) on om.FacilityID = fa.FacilityID
	--pre-2014ish, SAS & XFRs would show up in Monsoon, so this excludes those
	left join ofs..Order_Header oh with(nolock) on om.ISIS_OrderID = oh.ISISOrderID and oh.OrderSystem = 'MON' 
	--Grabs fulfilment location where available, otherwise uses originating location
	left join ofs..Order_Detail od with(nolock) on oh.OrderID = od.OrderID and od.Status in (1,4)
		--Problem orders have ProblemStatusID not null
		and (od.ProblemStatusID is null or od.ProblemStatusID = 0)	
	inner join #Stores loc on isnull(od.LocationNo,fa.HPBLocationNo) = loc.LocNo
	inner join ReportsData..ProductMaster pm with(nolock) on right(om.SKU,20) = pm.ItemCode
    inner join ReportsView..ProdGoals_ItemMaster it with(nolock) on pm.ItemCode = it.ItemCode
where om.OrderStatus in ('New','Pending','Shipped')
	and om.RefundAmount > 0
	and om.RefundDate < @eDate 
	and om.RefundDate >= @sDate
	and left(om.SKU,1) = 'D'
group by (case when datepart(WEEK, om.RefundDate) = 53 and datepart(YEAR, om.RefundDate) >= 2017 then datepart(YEAR, om.RefundDate)+1 
			 when datepart(WEEK, om.RefundDate) = 1 and datepart(YEAR, om.RefundDate) < 2017 then datepart(YEAR, om.RefundDate)-1 
			 else datepart(YEAR, om.RefundDate) end)
	,(case when datepart(WEEK, om.RefundDate) = 53 and datepart(YEAR, om.RefundDate) >= 2017 then 1 
			 when datepart(WEEK, om.RefundDate) = 1 and datepart(YEAR, om.RefundDate) < 2017 then 52 
			 else datepart(WEEK, om.RefundDate) - case when datepart(YEAR, om.RefundDate) < 2017 then 1 else 0 end end)
	,ltrim(rtrim(pm.SectionCode))
    ,it.RordGrp
    ,it.ngqVendor + case when it.ngqVendor <> 'CDC' then '' else 
							case when right(rtrim(pm.ProductType),1) = 'F' then '-f' else '-n' end end
    ,isnull(od.LocationNo,fa.HPBLocationNo)
	,pm.ItemCode

--HPB.com Sales----------------------
insert into #online_new_prep
select (case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then datepart(YEAR, od.OrderDate)+1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then datepart(YEAR, od.OrderDate)-1 
			 else datepart(YEAR, od.OrderDate) end)[Yr]
	,(case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then 1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then 52 
			 else datepart(WEEK, od.OrderDate) - case when datepart(YEAR, od.OrderDate) < 2017 then 1 else 0 end end)[Wk]
	,ltrim(rtrim(pm.SectionCode)) as Section
    ,'s'[Dir]
    ,'h'[Site]
    ,it.RordGrp
    ,it.ngqVendor + case when it.ngqVendor <> 'CDC' then '' else 
							case when right(rtrim(pm.ProductType),1) = 'F' then '-f' else '-n' end end[ngqVendor]
    ,fa.HPBLocationNo[LocNo]
	,pm.ItemCode
	,sum(od.Quantity)[SoldQty]
	-- ,sum(case when od.ItemPrice < pm.Price then od.Quantity else 0 end)[mdSoldQty]
	,sum(pm.Cost)[SoldCost]
	,sum(od.ExtendedAmount)[SoldVal]
	-- ,sum(case when od.ItemPrice < pm.Price then od.ExtendedAmount else 0 end)[mdSoldVal]
    ,sum(pm.Price)[SoldList]
	,sum(od.ShippingAmount)[SoldFee]
    ,0[RfndAmt] --summed separately b/c of specific refund timestamps
    ,count(distinct od.MarketOrderID)[NumOrds]
--    select top 1000*
from isis..Order_Omni od with(nolock)
	inner join isis..App_Facilities fa with(nolock) on od.FacilityID = fa.FacilityID
	inner join #Stores loc on fa.HPBLocationNo = loc.LocNo
	inner join ReportsData..ProductMaster pm with(nolock) on right(od.SKU,20) = pm.ItemCode
    inner join ReportsView..ProdGoals_ItemMaster it with(nolock) on pm.ItemCode = it.ItemCode
where od.OrderStatus not in ('canceled')
	and od.ItemStatus not in ('canceled')
	and od.OrderDate < @eDate 
	and od.OrderDate >= @sDate 
	and left(od.SKU,1) = 'D'
	and od.Quantity > 0
group by (case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then datepart(YEAR, od.OrderDate)+1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then datepart(YEAR, od.OrderDate)-1 
			 else datepart(YEAR, od.OrderDate) end)
	,(case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then 1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then 52 
			 else datepart(WEEK, od.OrderDate) - case when datepart(YEAR, od.OrderDate) < 2017 then 1 else 0 end end)
	,ltrim(rtrim(pm.SectionCode))
    ,it.RordGrp
    ,it.ngqVendor + case when it.ngqVendor <> 'CDC' then '' else 
							case when right(rtrim(pm.ProductType),1) = 'F' then '-f' else '-n' end end
    ,fa.HPBLocationNo
	,pm.ItemCode

--HPB.com Refunds--------------------
insert into #online_new_prep
select (case when datepart(WEEK, od.SiteLastModifiedDate) = 53 and datepart(YEAR, od.SiteLastModifiedDate) >= 2017 then datepart(YEAR, od.SiteLastModifiedDate)+1 
			 when datepart(WEEK, od.SiteLastModifiedDate) = 1 and datepart(YEAR, od.SiteLastModifiedDate) < 2017 then datepart(YEAR, od.SiteLastModifiedDate)-1 
			 else datepart(YEAR, od.SiteLastModifiedDate) end)[Yr]
	,(case when datepart(WEEK, od.SiteLastModifiedDate) = 53 and datepart(YEAR, od.SiteLastModifiedDate) >= 2017 then 1 
			 when datepart(WEEK, od.SiteLastModifiedDate) = 1 and datepart(YEAR, od.SiteLastModifiedDate) < 2017 then 52 
			 else datepart(WEEK, od.SiteLastModifiedDate) - case when datepart(YEAR, od.SiteLastModifiedDate) < 2017 then 1 else 0 end end)[Wk]
	,ltrim(rtrim(pm.SectionCode)) as Section
    ,'r'[Dir]
    ,'h'[Site]
    ,it.RordGrp
    ,it.ngqVendor + case when it.ngqVendor <> 'CDC' then '' else 
							case when right(rtrim(pm.ProductType),1) = 'F' then '-f' else '-n' end end[ngqVendor]
    ,fa.HPBLocationNo[LocNo]
	,pm.ItemCode
	--Same idea... don't think we actually get the thing back to the store.
	,0[SoldQty] 
	-- ,0[mdSoldQty] 
	,0[SoldCost]
	,0[SoldVal]
	-- ,0[mdSoldVal]
    ,0[SoldList]
	,0[SoldFee]
    ,sum(od.ItemRefundAmount)[RfndAmt]
    ,count(distinct od.MarketOrderID)[NumOrds]
--    select top 1000*
from isis..Order_Omni od with(nolock)
	inner join isis..App_Facilities fa with(nolock) on od.FacilityID = fa.FacilityID
	inner join #Stores loc on fa.HPBLocationNo = loc.LocNo
	inner join ReportsData..ProductMaster pm with(nolock) on right(od.SKU,20) = pm.ItemCode
    inner join ReportsView..ProdGoals_ItemMaster it with(nolock) on pm.ItemCode = it.ItemCode
where od.ItemStatus not in ('canceled')
	and od.OrderStatus not in ('canceled')
	and od.SiteLastModifiedDate < @eDate 
	and od.SiteLastModifiedDate >= @sDate 								  
	and left(od.SKU,1) = 'D'
	and od.Quantity > 0
	and od.ItemRefundAmount > 0
group by (case when datepart(WEEK, od.SiteLastModifiedDate) = 53 and datepart(YEAR, od.SiteLastModifiedDate) >= 2017 then datepart(YEAR, od.SiteLastModifiedDate)+1 
			 when datepart(WEEK, od.SiteLastModifiedDate) = 1 and datepart(YEAR, od.SiteLastModifiedDate) < 2017 then datepart(YEAR, od.SiteLastModifiedDate)-1 
			 else datepart(YEAR, od.SiteLastModifiedDate) end)
	,(case when datepart(WEEK, od.SiteLastModifiedDate) = 53 and datepart(YEAR, od.SiteLastModifiedDate) >= 2017 then 1 
			 when datepart(WEEK, od.SiteLastModifiedDate) = 1 and datepart(YEAR, od.SiteLastModifiedDate) < 2017 then 52 
			 else datepart(WEEK, od.SiteLastModifiedDate) - case when datepart(YEAR, od.SiteLastModifiedDate) < 2017 then 1 else 0 end end)
	,ltrim(rtrim(pm.SectionCode))
    ,it.RordGrp
    ,it.ngqVendor + case when it.ngqVendor <> 'CDC' then '' else 
							case when right(rtrim(pm.ProductType),1) = 'F' then '-f' else '-n' end end
    ,fa.HPBLocationNo
	,pm.ItemCode

--Combine all #online data into #online-------------------
--Right now SldFee doesn't get rolled into SldVal---------
drop table if exists #online_new
select cast('New' as varchar(4))[UsNw]
	,cast(case when op.RordGrp = 'BS' then 'BS' else 'DIPS' end as varchar(4))[Src]
	,m.Yr
    ,m.Wk
    ,op.LocNo
    ,cast(op.RordGrp as varchar(4))[RordGrp]
    ,cast(op.ngqVendor as varchar(12))[ngqVendor]
	,cast(ss.Cap as varchar(5))[Cap]  -- Cast() allows for nulls in entries
    ,ss.Secn
    ,op.Site
    ,sum(case when Dir = 's' then NumOrds else 0 end)[SoldOrds]
    ,count(distinct case when Dir = 's' then ItemCode end)[SoldIts]
    ,sum(SoldQty)[SoldQty]
	,sum(SoldCost)[SoldCost]
    ,sum(SoldVal)[SoldVal]
    ,sum(SoldList)[SoldList]
    ,sum(SoldFee)[SoldFee]
    ,sum(case when Dir = 'r' then NumOrds else 0 end)[RfndOrds]
    ,count(distinct case when Dir = 'r' then ItemCode end)[RfndIts]
    ,sum(RfndAmt)[RfndAmt]
into #online_new
from #online_new_prep op
	inner join #minDts m on op.Yr = m.oYr and op.Wk = m.oWk
	left join ReportsView..ShpSld_SbjScnCapMap ss on op.Section = ss.Section
group by cast(case when op.RordGrp = 'BS' then 'BS' else 'DIPS' end as varchar(4))
	,m.Yr
    ,m.Wk
    ,op.LocNo
    ,cast(op.RordGrp as varchar(4))
    ,cast(op.ngqVendor as varchar(12))
	,cast(ss.Cap as varchar(5))
    ,ss.Secn
    ,op.Site

select UsNw,Wk,sum(SoldQty)
from #online_new
group by UsNw,Wk
order by Wk


----Transaction 1--------------------------------
--Add good rows to ShpSld_-------------------[
-----------------------------------------------[
BEGIN TRY
	begin transaction
	
	insert into ReportsView.dbo.ShpSld_online
	select o.*
	from #online_new o 
		left join ReportsView.dbo.ShpSld_online s on o.Yr = s.Yr and o.Wk = s.Wk and o.LocNo = s.LocNo
		and o.Src = s.src and o.ngqVendor = s.ngqVendor and o.Secn = s.Secn and o.Site = s.Site
	where s.LocNo is null

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
drop table if exists #minDts 
drop table if exists #online_new_prep
drop table if exists #online_new
GO
