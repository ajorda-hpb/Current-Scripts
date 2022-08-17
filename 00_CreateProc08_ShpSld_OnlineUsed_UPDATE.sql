SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE or ALTER procedure [dbo].[ShpSld_OnlineUsed_UPDATE]

-- Add the parameters for the stored procedure here
@ends datetime

as
SET XACT_ABORT, NOCOUNT ON;

-- declare @ends datetime = cast(dateadd(DD,-DATEPART(Weekday,getdate())+1,getdate()) as date)

-- Run the complete past week, Sunday - Sunday(excl) if @ends is specifically defined.
if @ends is null begin
	set @ends = cast(dateadd(DD,-DATEPART(Weekday,getdate())+1,getdate()) as date)
end 
select dateadd(DD,-7,@ends)[StartDate],@ends[EndDate]

----Set start & end dates
drop table if exists #dates
select dateadd(WW,-1,@ends)[sDate]
	,@ends[eDate]
into #dates

-- ----Set start & end dates
-- drop table if exists #dates
-- select '11/1/20'[sDate]
-- 	,'11/8/20'[eDate]
-- into #dates

----build list of stores...
drop table if exists #stores
select distinct LocationNo[LocNo]
into #stores  
from ReportsData..Locations with(nolock)
where LocationNo between '00001' and '00150'
	--Closed/Inactive Stores
    -- and LocationNo not in ('00020','00027','00028','00042','00060','00063','00079','00089','00092','00093','00101','00106')

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

----TEMP VARS GUYS.!-------------------------
declare @stores table(LocNo char(5)) declare @sDate smalldatetime, @eDate smalldatetime
insert into @stores select distinct LocNo from #stores
set @sDate = (select max(sDate) from #dates)
set @eDate = (select max(eDate) from #dates)
---------------------------------------------


---Corrected Prices---------------------------
----------------------------------------------
drop table if exists #pfixes_prep
select s.ItemCode
	,s.LocationNo
	,first_value(OldPrice) 
		over(partition by s.ItemCode,s.LocationNo order by pc.ModifiedTime desc)[SetPriceTo]
into #pfixes_prep
from ReportsView.dbo.vw_SipsProductInventoryFull s with(nolock)
	inner join ReportsData..SipsPriceChanges pc with(nolock)
		on s.ItemCode = pc.ItemCode and s.LocationNo = pc.LocationNo
where s.Price >= '500'
	and ( ((OldPrice/nullif(NewPrice,0) < .001 or OldPrice/nullif(Price,0) < .001) and s.ProductType = 'NOST') 
			or ((OldPrice/nullif(NewPrice,0) < .02 or OldPrice/nullif(Price,0) < .02) and s.ProductType <> 'NOST') )

drop table if exists #pfixes
select ItemCode,LocationNo,SetPriceTo
into #pfixes from #pfixes_prep
group by ItemCode,LocationNo,SetPriceTo



--iStore Sales (Sips SKUs in Monsoon)-----------------------
drop table if exists #isales_prep
select (case when datepart(WEEK, om.OrderDate) = 53 and datepart(YEAR, om.OrderDate) >= 2017 then datepart(YEAR, om.OrderDate)+1 
			 when datepart(WEEK, om.OrderDate) = 1 and datepart(YEAR, om.OrderDate) < 2017 then datepart(YEAR, om.OrderDate)-1 
			 else datepart(YEAR, om.OrderDate) end)[Yr]
	,(case when datepart(WEEK, om.OrderDate) = 53 and datepart(YEAR, om.OrderDate) >= 2017 then 1 
			 when datepart(WEEK, om.OrderDate) = 1 and datepart(YEAR, om.OrderDate) < 2017 then 52 
			 else datepart(WEEK, om.OrderDate) - case when datepart(YEAR, om.OrderDate) < 2017 then 1 else 0 end end)[Wk]
    ,cast(max(om.OrderDate) as date)[maxDt]
	,isnull(od.LocationNo,fa.HPBLocationNo)[LocNo]
    ,'USED'[RordGrp]
    ,'SIPS'[ngqVendor]
	,ltrim(rtrim(spi.ProductType))[PrTy]
	,ltrim(rtrim(spi.SubjectKey))[Subj]
    ,'s'[Dir]
	,'i'[Site]
	,sum(om.ShippedQuantity)[SoldQty]
	,sum(od.Price)[SoldVal]
	,sum(ShippedQuantity * isnull(pf.SetPriceTo,spi.Price))[SoldList]
	,sum(om.ShippingFee)[SoldFee]
    ,cast(0 as money)[RfndAmt]
    ,count(distinct om.MarketOrderID)[NumOrds]
    ,count(distinct om.SKU)[NumIts]
	-- --Age Proportions............................................................................
	-- ,sum(case when datediff(DD,spi.DateInStock,om.OrderDate) < 15 then 1 else 0 end)[015Day]
	-- ,sum(case when datediff(DD,spi.DateInStock,om.OrderDate) >= 15 
	-- 				and datediff(DD,spi.DateInStock,om.OrderDate) < 30 then 1 else 0 end)[030Day]
	-- ,sum(case when datediff(DD,spi.DateInStock,om.OrderDate) >= 30 
	-- 				and datediff(DD,spi.DateInStock,om.OrderDate) < 90 then 1 else 0 end)[090Day]
	-- ,sum(case when datediff(DD,spi.DateInStock,om.OrderDate) >= 90 
	-- 				and datediff(DD,spi.DateInStock,om.OrderDate) < 180 then 1 else 0 end)[180Day]
	-- ,sum(case when datediff(DD,spi.DateInStock,om.OrderDate) >= 180 
	-- 				and datediff(DD,spi.DateInStock,om.OrderDate) < 365 then 1 else 0 end)[365Day]
into #isales_prep
from isis..Order_Monsoon om with(nolock)
	inner join isis..App_Facilities fa with(nolock) on om.FacilityID = fa.FacilityID
	--pre-2014ish, SAS & XFRs would show up in Monsoon, so specifying 'MON' excludes those
	left join ofs..Order_Header oh with(nolock) on om.ISIS_OrderID = oh.ISISOrderID and oh.OrderSystem = 'MON' 
	--Grabs fulfilment location where available, otherwise uses originating location
	left join ofs..Order_Detail od with(nolock) on oh.OrderID = od.OrderID and od.Status in (1,4)
		--Problem orders have ProblemStatusID not null
		and (od.ProblemStatusID is null or od.ProblemStatusID = 0)	
	inner join ReportsView..vw_SipsProductInventoryFull spi with(nolock) on replace(om.SKU,'S_','') = spi.ItemCode
	inner join ReportsData..SipsProductMaster spm with(nolock) on spi.SipsID = spm.SipsID
	left outer join #pfixes pf on spi.ItemCode = pf.ItemCode and spi.LocationNo = pf.LocationNo
where isnumeric(replace(om.SKU,'S_','')) = 1
	and om.OrderStatus in ('New','Pending','Shipped')
	and om.ShippedQuantity > 0
	and om.OrderDate >= @sDate
	and om.OrderDate < @eDate
	-- and isnull(od.LocationNo,fa.HPBLocationNo) in (select distinct LocNo from #stores) 
	and (spi.Price < '5000' or pf.SetPriceTo is not null)
	and left(om.SKU,1) = 'S'
group by (case when datepart(WEEK, om.OrderDate) = 53 and datepart(YEAR, om.OrderDate) >= 2017 then datepart(YEAR, om.OrderDate)+1 
			 when datepart(WEEK, om.OrderDate) = 1 and datepart(YEAR, om.OrderDate) < 2017 then datepart(YEAR, om.OrderDate)-1 
			 else datepart(YEAR, om.OrderDate) end)
	,(case when datepart(WEEK, om.OrderDate) = 53 and datepart(YEAR, om.OrderDate) >= 2017 then 1 
			 when datepart(WEEK, om.OrderDate) = 1 and datepart(YEAR, om.OrderDate) < 2017 then 52 
			 else datepart(WEEK, om.OrderDate) - case when datepart(YEAR, om.OrderDate) < 2017 then 1 else 0 end end)
	,isnull(od.LocationNo,fa.HPBLocationNo)
	,ltrim(rtrim(spi.ProductType))
	,ltrim(rtrim(spi.SubjectKey))

--iStore Refunds (Sips SKUs in Monsoon)---------------------
insert into #isales_prep
select (case when datepart(WEEK, om.RefundDate) = 53 and datepart(YEAR, om.RefundDate) >= 2017 then datepart(YEAR, om.RefundDate)+1 
			 when datepart(WEEK, om.RefundDate) = 1 and datepart(YEAR, om.RefundDate) < 2017 then datepart(YEAR, om.RefundDate)-1 
			 else datepart(YEAR, om.RefundDate) end)[Yr]
	,(case when datepart(WEEK, om.RefundDate) = 53 and datepart(YEAR, om.RefundDate) >= 2017 then 1 
			 when datepart(WEEK, om.RefundDate) = 1 and datepart(YEAR, om.RefundDate) < 2017 then 52 
			 else datepart(WEEK, om.RefundDate) - case when datepart(YEAR, om.RefundDate) < 2017 then 1 else 0 end end)[Wk]
    ,cast(max(om.RefundDate) as date)[maxDt]
	,isnull(od.LocationNo,fa.HPBLocationNo)[LocNo]
    ,'USED'[RordGrp]
    ,'SIPS'[ngqVendor]
	,ltrim(rtrim(spi.ProductType))[PrTy]
	,ltrim(rtrim(spi.SubjectKey))[Subj]
    ,'r'[Dir]
	,'i'[Site]
	,cast(0 as int)[SoldQty]
	,cast(0 as money)[SoldVal]
	,cast(0 as money)[SoldList]
	,cast(0 as money)[SoldFee]
    ,sum(om.RefundAmount)[RfndAmt]
    ,count(distinct om.MarketOrderID)[NumOrds]
    ,count(distinct om.SKU)[NumIts]
	-- --Age Proportions.................................
	-- ,0[015Day],0[030Day],0[090Day],0[180Day],0[365Day]
from isis..Order_Monsoon om with(nolock)
	inner join isis..App_Facilities fa with(nolock) on om.FacilityID = fa.FacilityID
	--pre-2014ish, SAS & XFRs would show up in Monsoon, so specifying 'MON' excludes those
	left join ofs..Order_Header oh with(nolock) on om.ISIS_OrderID = oh.ISISOrderID and oh.OrderSystem = 'MON' 
	--Grabs fulfilment location where available, otherwise uses originating location
	left join ofs..Order_Detail od with(nolock) on oh.OrderID = od.OrderID and od.Status in (1,4)
		--Problem orders have ProblemStatusID not null
		and (od.ProblemStatusID is null or od.ProblemStatusID = 0)	
	inner join ReportsView..vw_SipsProductInventoryFull spi with(nolock) on replace(om.SKU,'S_','') = spi.ItemCode
	inner join ReportsData..SipsProductMaster spm with(nolock) on spi.SipsID = spm.SipsID
	left outer join #pfixes pf on spi.ItemCode = pf.ItemCode and spi.LocationNo = pf.LocationNo
where isnumeric(replace(om.SKU,'S_','')) = 1
	and om.OrderStatus in ('New','Pending','Shipped')
	and om.RefundAmount > 0
	and om.RefundDate >= @sDate
	and om.RefundDate < @eDate
	-- and isnull(od.LocationNo,fa.HPBLocationNo) in (select distinct LocNo from #stores) 
	and (spi.Price < '5000' or pf.SetPriceTo is not null)
	and left(om.SKU,1) = 'S'
group by (case when datepart(WEEK, om.RefundDate) = 53 and datepart(YEAR, om.RefundDate) >= 2017 then datepart(YEAR, om.RefundDate)+1 
			 when datepart(WEEK, om.RefundDate) = 1 and datepart(YEAR, om.RefundDate) < 2017 then datepart(YEAR, om.RefundDate)-1 
			 else datepart(YEAR, om.RefundDate) end)
	,(case when datepart(WEEK, om.RefundDate) = 53 and datepart(YEAR, om.RefundDate) >= 2017 then 1 
			 when datepart(WEEK, om.RefundDate) = 1 and datepart(YEAR, om.RefundDate) < 2017 then 52 
			 else datepart(WEEK, om.RefundDate) - case when datepart(YEAR, om.RefundDate) < 2017 then 1 else 0 end end)
	,isnull(od.LocationNo,fa.HPBLocationNo)
	,ltrim(rtrim(spi.ProductType))
	,ltrim(rtrim(spi.SubjectKey))

--HPB.com Sales (Sips SKUs in OMNI on ISIS)---------------------
insert into #iSales_prep
select (case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then datepart(YEAR, od.OrderDate)+1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then datepart(YEAR, od.OrderDate)-1 
			 else datepart(YEAR, od.OrderDate) end)[Yr]
	,(case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then 1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then 52 
			 else datepart(WEEK, od.OrderDate) - case when datepart(YEAR, od.OrderDate) < 2017 then 1 else 0 end end)[Wk]
    ,cast(max(od.OrderDate) as date)[maxDt]
	,fa.HPBLocationNo[LocNo]
    ,'USED'[RordGrp]
    ,'SIPS'[ngqVendor]
	,ltrim(rtrim(spi.ProductType))[PrTy]
	,ltrim(rtrim(spi.SubjectKey))[Subj]
    ,'s'[Dir]
	,'h'[Site]
	,sum(od.Quantity)[SoldQty]
	,sum(od.ExtendedAmount)[SoldVal]
	,sum(od.Quantity * isnull(pf.SetPriceTo,spi.Price))[SoldList]
	,sum(od.ShippingAmount)[SoldFee]
    ,0[RfndAmt]
    ,count(distinct od.MarketOrderID)[NumOrds]
    ,count(distinct od.SKU)[NumIts]
	-- --Age Proportions............................................................................
	-- ,sum(case when datediff(DD,spi.DateInStock,od.OrderDate) < 15 then 1 else 0 end)[015Day]
	-- ,sum(case when datediff(DD,spi.DateInStock,od.OrderDate) >= 15 
	-- 				and datediff(DD,spi.DateInStock,od.OrderDate) < 30 then 1 else 0 end)[030Day]
	-- ,sum(case when datediff(DD,spi.DateInStock,od.OrderDate) >= 30 
	-- 				and datediff(DD,spi.DateInStock,od.OrderDate) < 90 then 1 else 0 end)[090Day]
	-- ,sum(case when datediff(DD,spi.DateInStock,od.OrderDate) >= 90 
	-- 				and datediff(DD,spi.DateInStock,od.OrderDate) < 180 then 1 else 0 end)[180Day]
	-- ,sum(case when datediff(DD,spi.DateInStock,od.OrderDate) >= 180 
	-- 				and datediff(DD,spi.DateInStock,od.OrderDate) < 365 then 1 else 0 end)[365Day]
from isis..Order_Omni od with(nolock)
	inner join isis..App_Facilities fa with(nolock) on od.FacilityID = fa.FacilityID
	inner join ReportsView..vw_SipsProductInventoryFull spi with(nolock) on replace(od.SKU,'S_','') = spi.ItemCode
	inner join ReportsData..SipsProductMaster spm with(nolock) on spi.SipsID = spm.SipsID
	left outer join #pfixes pf on spi.ItemCode = pf.ItemCode and spi.LocationNo = pf.LocationNo
where isnumeric(replace(od.SKU,'S_','')) = 1
	and od.ItemStatus not in ('canceled')
	and od.OrderStatus not in ('canceled')
	and od.Quantity > 0
	and od.OrderDate >= @sDate
	and od.OrderDate < @eDate
	-- and fa.HPBLocationNo in (select distinct LocNo from #stores) 
	and (spi.Price < '5000' or pf.SetPriceTo is not null)
	and left(od.SKU,1) = 'S'
group by (case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then datepart(YEAR, od.OrderDate)+1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then datepart(YEAR, od.OrderDate)-1 
			 else datepart(YEAR, od.OrderDate) end)
	,(case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then 1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then 52 
			 else datepart(WEEK, od.OrderDate) - case when datepart(YEAR, od.OrderDate) < 2017 then 1 else 0 end end)
	,fa.HPBLocationNo
	,ltrim(rtrim(spi.ProductType))
	,ltrim(rtrim(spi.SubjectKey))
	
--HPB.com Refunds (Sips SKUs in OMNI on ISIS) Refunds--------------------
insert into #iSales_prep
select (case when datepart(WEEK, od.SiteLastModifiedDate) = 53 and datepart(YEAR, od.SiteLastModifiedDate) >= 2017 then datepart(YEAR, od.SiteLastModifiedDate)+1 
			 when datepart(WEEK, od.SiteLastModifiedDate) = 1 and datepart(YEAR, od.SiteLastModifiedDate) < 2017 then datepart(YEAR, od.SiteLastModifiedDate)-1 
			 else datepart(YEAR, od.SiteLastModifiedDate) end)[Yr]
	,(case when datepart(WEEK, od.SiteLastModifiedDate) = 53 and datepart(YEAR, od.SiteLastModifiedDate) >= 2017 then 1 
			 when datepart(WEEK, od.SiteLastModifiedDate) = 1 and datepart(YEAR, od.SiteLastModifiedDate) < 2017 then 52 
			 else datepart(WEEK, od.SiteLastModifiedDate) - case when datepart(YEAR, od.SiteLastModifiedDate) < 2017 then 1 else 0 end end)[Wk]
    ,cast(max(od.SiteLastModifiedDate) as date)[maxDt]
	,fa.HPBLocationNo[LocNo]
    ,'USED'[RordGrp]
    ,'SIPS'[ngqVendor]
	,ltrim(rtrim(spi.ProductType))[PrTy]
	,ltrim(rtrim(spi.SubjectKey))[Subj]
    ,'r'[Dir]
	,'h'[Site]
	,0[SoldQty]
	,0[SoldVal]
	,0[SoldList]
	,0[SoldFee]
    ,sum(od.ItemRefundAmount)[RfndAmt]
    ,count(distinct od.MarketOrderID)[NumOrds]
    ,count(distinct od.SKU)[NumIts]
	-- --Age Proportions.................................
	-- ,0[015Day],0[030Day],0[090Day],0[180Day],0[365Day]
from isis..Order_Omni od with(nolock)
	inner join isis..App_Facilities fa with(nolock) on od.FacilityID = fa.FacilityID
	inner join ReportsView..vw_SipsProductInventoryFull spi with(nolock) on replace(od.SKU,'S_','') = spi.ItemCode
	inner join ReportsData..SipsProductMaster spm with(nolock) on spi.SipsID = spm.SipsID
	left outer join #pfixes pf on spi.ItemCode = pf.ItemCode and spi.LocationNo = pf.LocationNo
where isnumeric(replace(od.SKU,'S_','')) = 1
	and od.ItemStatus not in ('canceled')
	and od.OrderStatus not in ('canceled')
	and od.Quantity > 0
	and od.SiteLastModifiedDate >= @sDate
	and od.SiteLastModifiedDate < @eDate
	-- and fa.HPBLocationNo in (select distinct LocNo from #stores) 
	and (spi.Price < '5000' or pf.SetPriceTo is not null)
	and left(od.SKU,1) = 'S'
	and od.ItemRefundAmount > 0
group by (case when datepart(WEEK, od.SiteLastModifiedDate) = 53 and datepart(YEAR, od.SiteLastModifiedDate) >= 2017 then datepart(YEAR, od.SiteLastModifiedDate)+1 
			 when datepart(WEEK, od.SiteLastModifiedDate) = 1 and datepart(YEAR, od.SiteLastModifiedDate) < 2017 then datepart(YEAR, od.SiteLastModifiedDate)-1 
			 else datepart(YEAR, od.SiteLastModifiedDate) end)
	,(case when datepart(WEEK, od.SiteLastModifiedDate) = 53 and datepart(YEAR, od.SiteLastModifiedDate) >= 2017 then 1 
			 when datepart(WEEK, od.SiteLastModifiedDate) = 1 and datepart(YEAR, od.SiteLastModifiedDate) < 2017 then 52 
			 else datepart(WEEK, od.SiteLastModifiedDate) - case when datepart(YEAR, od.SiteLastModifiedDate) < 2017 then 1 else 0 end end)
	,fa.HPBLocationNo
	,ltrim(rtrim(spi.ProductType))
	,ltrim(rtrim(spi.SubjectKey))


--Booksmarter Sales (aka Base Inventory)---------------------
---omfg... mf char(5) having hidden spaces at the end of a mf THREE DIGIT LocNo. GRHA%$*#&*$&
insert into #iSales_prep
select (case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then datepart(YEAR, od.OrderDate)+1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then datepart(YEAR, od.OrderDate)-1 
			 else datepart(YEAR, od.OrderDate) end)[Yr]
	,(case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then 1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then 52 
			 else datepart(WEEK, od.OrderDate) - case when datepart(YEAR, od.OrderDate) < 2017 then 1 else 0 end end)[Wk]
    ,cast(max(od.OrderDate) as date)[maxDt]
    ,right('00000'+cast(rtrim(od.LocationNo) as varchar(5)),5)[LocNo]
    ,'USED'[RordGrp]
    ,'BI'[ngqVendor]
	,cast(null as varchar(4))[PrTy]
	,cast(null as varchar(6))[Subj]
    ,'s'[Dir]
	,'i'[Site]
	,sum(od.ShippedQuantity)[SoldQty]
	,sum(od.Price)[SoldVal]
	,sum(od.Price)[SoldList]
	,sum(od.ShippingFee)[SoldFee]
    ,cast(0 as money)[RfndAmt]
    ,count(distinct od.MarketOrderID)[NumOrds]
    ,count(distinct od.SKU)[NumIts]
from Monsoon..OrderDetailsReporting od with(nolock)
where od.ServerID in ('4','5','11') --Booksmarter ServerIDs
	and od.OrderDate >= @sDate
	and od.OrderDate < @eDate
	and od.Status not in ('Cancelled')
	and left(od.SKU,1) = 'm'
group by (case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then datepart(YEAR, od.OrderDate)+1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then datepart(YEAR, od.OrderDate)-1 
			 else datepart(YEAR, od.OrderDate) end)
	,(case when datepart(WEEK, od.OrderDate) = 53 and datepart(YEAR, od.OrderDate) >= 2017 then 1 
			 when datepart(WEEK, od.OrderDate) = 1 and datepart(YEAR, od.OrderDate) < 2017 then 52 
			 else datepart(WEEK, od.OrderDate) - case when datepart(YEAR, od.OrderDate) < 2017 then 1 else 0 end end)
    ,right('00000'+cast(rtrim(od.LocationNo) as varchar(5)),5)
    

--Booksmarter Refunds (aka Base Inventory)---------------------
insert into #iSales_prep
select (case when datepart(WEEK, od.LastStatusModified) = 53 and datepart(YEAR, od.LastStatusModified) >= 2017 then datepart(YEAR, od.LastStatusModified)+1 
			 when datepart(WEEK, od.LastStatusModified) = 1 and datepart(YEAR, od.LastStatusModified) < 2017 then datepart(YEAR, od.LastStatusModified)-1 
			 else datepart(YEAR, od.LastStatusModified) end)[Yr]
	,(case when datepart(WEEK, od.LastStatusModified) = 53 and datepart(YEAR, od.LastStatusModified) >= 2017 then 1 
			 when datepart(WEEK, od.LastStatusModified) = 1 and datepart(YEAR, od.LastStatusModified) < 2017 then 52 
			 else datepart(WEEK, od.LastStatusModified) - case when datepart(YEAR, od.LastStatusModified) < 2017 then 1 else 0 end end)[Wk]
    ,cast(max(od.LastStatusModified) as date)[maxDt]
    ,right('00000'+cast(rtrim(od.LocationNo) as varchar(5)),5)[LocNo]
    ,'USED'[RordGrp]
    ,'BI'[ngqVendor]
	,cast(null as varchar(4))[PrTy]
	,cast(null as varchar(6))[Subj]
    ,'r'[Dir]
	,'i'[Site]
	,cast(0 as int)[SoldQty]
	,cast(0 as money)[SoldVal]
	,cast(0 as money)[SoldList]
	,cast(0 as money)[SoldFee]
    ,sum(od.RefundAmount)[RfndAmt]
    ,count(distinct od.MarketOrderID)[NumOrds]
    ,count(distinct od.SKU)[NumIts]
from Monsoon..OrderDetailsReporting od with(nolock)
where od.ServerID in ('4','5','11') --Booksmarter ServerIDs
	and od.LastStatusModified >= @sDate
	and od.LastStatusModified < @eDate
	and od.Status not in ('Cancelled')
	and left(od.SKU,1) = 'm'
	and RefundAmount > 0
group by (case when datepart(WEEK, od.LastStatusModified) = 53 and datepart(YEAR, od.LastStatusModified) >= 2017 then datepart(YEAR, od.LastStatusModified)+1 
			 when datepart(WEEK, od.LastStatusModified) = 1 and datepart(YEAR, od.LastStatusModified) < 2017 then datepart(YEAR, od.LastStatusModified)-1 
			 else datepart(YEAR, od.LastStatusModified) end)
	,(case when datepart(WEEK, od.LastStatusModified) = 53 and datepart(YEAR, od.LastStatusModified) >= 2017 then 1 
			 when datepart(WEEK, od.LastStatusModified) = 1 and datepart(YEAR, od.LastStatusModified) < 2017 then 52 
			 else datepart(WEEK, od.LastStatusModified) - case when datepart(YEAR, od.LastStatusModified) < 2017 then 1 else 0 end end)
    ,right('00000'+cast(rtrim(od.LocationNo) as varchar(5)),5)


-- Normalize MaxDt field...
-- set maxDt to date Wk*7 days from start of calendar year
update #isales_prep
    set maxDt = dateadd(DD,Wk*7,datefromparts(Yr,1,1))
from #isales_prep
-- Round to nearest month
update #isales_prep
    set maxDt = dateadd(MM,round(day(maxDt)/28.0,0),maxDt)
from #isales_prep
-- truncate days to get first day of month
update #isales_prep
    set maxDt = datefromparts(datepart(YY,maxDt),datepart(MM,maxDt),1)
from #isales_prep


--Combine all online sales into one table-----
----------------------------------------------
drop table if exists #iSales
select cast('Used' as varchar(4))[UsNw]
	,cast(sa.ngqVendor as varchar(4))[Src]
	,m.Yr
	,m.Wk
	,sa.LocNo
    ,cast(sa.RordGrp as varchar(4))[RordGrp]
    ,cast(sa.ngqVendor as varchar(12))[ngqVendor]
    ,ss.Cap
    ,ss.Secn
    ,sa.Site
    ,sum(case when Dir = 's' then NumOrds else 0 end)[SoldOrds]
    ,sum(case when Dir = 's' then NumIts else 0 end)[SoldIts]
	,sum(SoldQty)[SoldQty]
	,sum(coalesce(sa.SoldQty*bc.Cost
                ,sa.SoldVal*cf.CoGFactor*0.01
                ,null))[SoldCost]
	,sum(SoldVal)[SoldVal]
	,sum(SoldList)[SoldList]
	,sum(SoldFee)[SoldFee]
    ,sum(case when Dir = 'r' then NumOrds else 0 end)[RfndOrds]
    ,sum(case when Dir = 'r' then NumIts else 0 end)[RfndIts]
    ,sum(RfndAmt)[RfndAmt]
	--Age Proportions........
	-- ,sum([015Day])[015Day]
	-- ,sum([030Day])[030Day]
	-- ,sum([090Day])[090Day]
	-- ,sum([180Day])[180Day]
	-- ,sum([365Day])[365Day]
into #iSales
from #iSales_prep sa
	inner join #minDts m on sa.Yr = m.oYr and sa.Wk = m.oWk
	left join ReportsView..ShpSld_SbjScnCapMap ss 
        on sa.Subj = ss.Subj and ss.Section is null
	--Store/Month/PrTy specific Costing
	left join ReportsData..AvgBookCost_v2 bc with(nolock)
		on maxDt = bc.FirstDayOfMonth
			and sa.LocNo = bc.LocationNo and sa.PrTy = bc.ProductType 
            and bc.Quantity is not null and bc.Cost is not null
	--PrTy CoG Factors to apply to ListValue in the absence of above
	left join HPB_Inv..Inv_CoGFactors cf with(nolock) on sa.PrTy = cf.ProductType
group by cast(sa.ngqVendor as varchar(4))
	,m.Yr,m.Wk
	,sa.LocNo
    ,cast(sa.RordGrp as varchar(4))
    ,cast(sa.ngqVendor as varchar(12))
    ,ss.Cap
    ,ss.Secn
    ,sa.Site




----Transaction 1--------------------------------
--Add good rows to ShpSld_-------------------[
-----------------------------------------------[
BEGIN TRY
	begin transaction
	
	insert into ReportsView.dbo.ShpSld_online
	select o.*
	from #iSales o 
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
drop table if exists #iSales 
drop table if exists #iSales_prep 
drop table if exists #pfixes 
drop table if exists #pfixes_prep 





GO
