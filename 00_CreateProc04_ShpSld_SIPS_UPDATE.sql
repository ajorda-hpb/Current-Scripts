SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[ShpSld_SIPS_UPDATE]
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

----build a table with all sips subjects....
drop table if exists #subjects
select distinct ltrim(rtrim(s.SubjectKey))[Subj]
into #subjects
from ReportsData..SubjectSummary s with(nolock)

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


----SIPS Item Creation------------------------
----------------------------------------------

---Corrected Prices---------------------------
drop table if exists #pfixes
select s.ItemCode
    ,s.LocationNo
    ,first_value(OldPrice) 
        over(partition by s.ItemCode,s.LocationNo order by pc.ModifiedTime desc)[SetPriceTo]
into #pfixes_prep
from ReportsView.dbo.vw_SipsProductInventoryFull s with(nolock)
    inner join ReportsData..SipsPriceChanges pc with(nolock) on s.ItemCode = pc.ItemCode and s.LocationNo = pc.LocationNo
	inner join #minDts m on s.DateInStock >= m.minDt and s.DateInStock < m.endDt
where s.Price >= '500'
    and (	((OldPrice/nullif(NewPrice,0) < .001 or OldPrice/nullif(Price,0) < .001) and s.ProductType = 'NOST') 
            or ((OldPrice/nullif(NewPrice,0) < .02 or OldPrice/nullif(Price,0) < .02) and s.ProductType <> 'NOST'))

select ItemCode,LocationNo,SetPriceTo
into #pfixes from #pfixes_prep
group by ItemCode,LocationNo,SetPriceTo


---Item Counts & Values-----------------------
drop table if exists #sipsItemCounts
select m.minDt
	,s.LocationNo[LocNo]
	,ltrim(rtrim(s.SubjectKey))[Subj]
	,count(distinct s.ItemCode)[NumItems]
	,sum(isnull(pf.SetPriceTo,s.Price))[SipsList]
into #sipsItemCounts
from ReportsView.dbo.vw_SipsProductInventoryFull s with(nolock)
	inner join ReportsData.dbo.SipsProductMaster spm with(nolock) on s.SipsID=spm.SipsID
	left  join #pfixes pf on s.ItemCode = pf.ItemCode and s.LocationNo = pf.LocationNo
	inner join #minDts m on s.DateInStock >= m.minDt and s.DateInStock < m.endDt
where (s.Price < '5000' or pf.SetPriceTo is not null)
group by m.minDt
	,s.LocationNo
	,ltrim(rtrim(s.SubjectKey))

----SIPS Sales Data---------------------------
----Remove '_Recent' from the sales tables----
------if pulling data before 1/1/16 !---------
----------------------------------------------
drop table if exists #sipsSales
;with sih as(
	select * from HPB_SALES..SIH2021 sd with(nolock)
	union all select * from HPB_SALES..SIH2022 sd with(nolock)
)
,shh as(
	select * from HPB_SALES..SHH2021 sd with(nolock)
	union all select * from HPB_SALES..SHH2022 sd with(nolock)
)
select m.minDt
	,spi.LocationNo[LocNo]
	,ltrim(rtrim(spi.SubjectKey))[Subj]
	--total sales.............................................................................
	,isnull(sum(case sih.isreturn when 'y' then -sih.quantity else sih.quantity end),0)[SoldQty]
	,isnull(sum(sih.extendedamt),0)[SoldVal]
	,isnull(sum(case sih.isreturn when 'y' then -isnull(pf.SetPriceTo,spi.Price) else isnull(pf.SetPriceTo,spi.Price) end),0)[ListVal]
	--markdown sales...........................................................................
	,isnull(sum(case 
				when sih.isreturn='y' and sih.RegisterPrice < sih.UnitPrice then -sih.quantity 
				when sih.isreturn='n' and sih.RegisterPrice < sih.UnitPrice then  sih.quantity 
				else 0 end),0)[mdSoldQty]
	,isnull(sum(case
				when (sih.isreturn='y' and sih.RegisterPrice < sih.UnitPrice) 
				  or (sih.isreturn='n' and sih.RegisterPrice < sih.UnitPrice) then sih.extendedamt 
				else 0 end),0)[mdSoldVal]
	,isnull(sum(case 
				when sih.isreturn='y' and sih.RegisterPrice < sih.UnitPrice then -isnull(pf.SetPriceTo,spi.Price) 
				when sih.isreturn='n' and sih.RegisterPrice < sih.UnitPrice then  isnull(pf.SetPriceTo,spi.Price) 
				else 0 end),0)[mdListVal]
	--Age Proportions..........................................................................
	,sum(case when datediff(DD,spi.DateInStock,shh.EndDate) < 15 then 1 else 0 end)[015Day]
	,sum(case when datediff(DD,spi.DateInStock,shh.EndDate) >= 15 
					and datediff(DD,spi.DateInStock,shh.EndDate) < 30 then 1 else 0 end)[030Day]
	,sum(case when datediff(DD,spi.DateInStock,shh.EndDate) >= 30 
					and datediff(DD,spi.DateInStock,shh.EndDate) < 60 then 1 else 0 end)[060Day]
	,sum(case when datediff(DD,spi.DateInStock,shh.EndDate) >= 60 
					and datediff(DD,spi.DateInStock,shh.EndDate) < 180 then 1 else 0 end)[180Day]
	,sum(case when datediff(DD,spi.DateInStock,shh.EndDate) >= 180 
					and datediff(DD,spi.DateInStock,shh.EndDate) < 365 then 1 else 0 end)[365Day]
into #sipsSales
from shh inner join sih 
		on sih.LocationID = shh.LocationID
		and sih.BusinessDate = shh.BusinessDate
		and sih.SalesXactionId = shh.SalesXactionID
		and sih.XactionType = shh.XactionType
	inner join ReportsView.dbo.vw_SipsProductInventoryFull spi with(nolock) on cast(right(sih.ItemCode,9) as int) = spi.ItemCode and sih.LocationID = spi.LocationID
	inner join ReportsData.dbo.SipsProductMaster spm with(nolock) on spi.SipsID=spm.SipsID
	left  join #pfixes pf on spi.ItemCode = pf.ItemCode and spi.LocationNo = pf.LocationNo
	inner join #minDts m on shh.EndDate >= m.minDt and shh.EndDate < m.endDt
where isnumeric(sih.itemcode) = 1
	and sih.ItemCode not like '%[^0-9]%'
	and left(sih.itemcode,1) <> '0'
	and sih.ExtendedAmt <> 0
	and shh.Status = 'A'
	and (spi.Price < '5000' or pf.SetPriceTo is not null)
group by m.minDt
	,spi.LocationNo
	,ltrim(rtrim(spi.SubjectKey))

--Transfers FROM a Location-------------------
----------------------------------------------
drop table if exists #xfersF
select m.minDt
	,ltrim(rtrim(spi.SubjectKey))[Subj]
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
into #xfersF
from ReportsData..SipsTransferBinHeader as h 
		inner join ReportsData..SipsTransferBinDetail as d on h.TransferBinNo = d.TransferBinNo  
	inner join ReportsView.dbo.vw_SipsProductInventoryFull spi with(nolock) on cast(right(d.SipsItemCode,9) as int) = spi.ItemCode
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
	,ltrim(rtrim(spi.SubjectKey))
--Transfers TO a Location-------------------
drop table if exists #xfersT
select m.minDt
	,h.ToLocationNo[ToLoc]
	,ltrim(rtrim(spi.SubjectKey))[Subj]
	,isnull(sum(d.Quantity),0)[RcvQty]
	,isnull(sum(d.DipsCost*d.Quantity),0)[ExtCost]
into #xfersT
from ReportsData..SipsTransferBinHeader as h 
		inner join ReportsData..SipsTransferBinDetail as d on h.TransferBinNo = d.TransferBinNo 
	inner join ReportsView.dbo.vw_SipsProductInventoryFull spi with(nolock) on cast(right(d.SipsItemCode,9) as int) = spi.ItemCode
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
	,ltrim(rtrim(spi.SubjectKey))
--All Transfers Together----------------------
----Joined up by itemcode cos StS
drop table if exists #xfers
select isnull(xf.minDt,xt.minDt)[minDt]
	,isnull(xf.FromLoc,xt.ToLoc)[LocNo]
	,isnull(xf.Subj,xt.Subj)[Subj]
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
into #xfers  --  select count(*) from #xfers
from #xfersF xf full outer join #xfersT xt
	on xf.minDt = xt.minDt and xf.FromLoc=xt.ToLoc and xf.Subj = xt.Subj
group by isnull(xf.minDt,xt.minDt)
	,isnull(xf.FromLoc,xt.ToLoc)
	,isnull(xf.Subj,xt.Subj)

----All Together Now--------------------------
----------------------------------------------
drop table if exists #LocSchemeDetails
;with MbyPbyS as(
	select md.Yr, md.Wk, md.minDt, l.LocNo, s.subj
	from #minDts md cross join #subjects s cross join #stores l
)
select mps.Yr
	,mps.Wk
	,mps.minDt
	,mps.Subj
	,mps.LocNo
	,isnull(sic.NumItems,0)[SipsQty]
	,isnull(sic.SipsList,0)[SipsList]
	,isnull(ss.SoldQty,0)[SoldQty]
	,isnull(ss.SoldVal,0)[SoldVal]
	,isnull(ss.ListVal,0)[ListVal]
	,isnull(ss.mdSoldQty,0)[mdSoldQty]
	,isnull(ss.mdSoldVal,0)[mdSoldVal]
	,isnull(ss.mdListVal,0)[mdListVal]
	,isnull(ss.[060Day],0)[060SoldAge]
	,isnull(ss.[180Day],0)[180SoldAge]
	,isnull(ss.[365Day],0)[365SoldAge]
	,isnull(xr.TshQty+xr.DmgQty+xr.DntQty,0)[RfiQty]
	,isnull(xr.TshCost+xr.DmgCost+xr.DntCost,0)[RfiCost]
	,isnull(xr.iStSQty,0)[iStSQty]
	,isnull(xr.oStSQty,0)[oStSQty]
	,isnull(xr.BsmQty,0)[BsmQty]
	,isnull(ss.[015Day],0)[015SoldAge]
	,isnull(ss.[030Day],0)[030SoldAge]
	,isnull(xr.BsmCost,0)[BsmCost]
into #LocSchemeDetails              --  select * from #LocSchemeDetails 
from MbyPbyS mps
	left join #sipsItemCounts sic on mps.minDt=sic.minDt and mps.LocNo=sic.LocNo and mps.Subj=sic.Subj
	left join #sipsSales ss on mps.minDt=ss.minDt and mps.LocNo=ss.LocNo and mps.Subj=ss.Subj
	left join #xfers xr on mps.minDt=xr.minDt and mps.LocNo=xr.LocNo and mps.Subj=xr.Subj

drop table if exists #limits
select LocNo
	,min(minDt)[minDt]
	,max(minDt)[maxDt]
into #limits
from #LocSchemeDetails				   
where (SoldQty <> 0
	or RfiQty <> 0
	or iStSQty <> 0
	or oStSQty <> 0)
group by LocNo
order by LocNo


----Transaction 1--------------------------------
--Add good rows to ShpSld_SIPS-------------------[
-----------------------------------------------[
BEGIN TRY
	begin transaction
	
	insert into ReportsView.dbo.ShpSld_SIPS
	select lsd.*
	from #LocSchemeDetails lsd
		inner join #limits li on lsd.LocNo = li.LocNo 
		left join ReportsView.dbo.ShpSld_SIPS s on lsd.minDt = s.minDt and lsd.Subj = s.Subj and lsd.LocNo = s.LocNo
	where s.minDt is null
		and lsd.minDt >= li.minDt
		and lsd.minDt <= li.maxDt

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
drop table if exists #LocSchemeDetails
drop table if exists #limits
drop table if exists #sipsItemCounts
drop table if exists #sipsSales
drop table if exists #xfers
drop table if exists #xfersF
drop table if exists #xfersT
drop table if exists #pfixes
drop table if exists #pfixes_prep
drop table if exists #minDt
drop table if exists #subjects
drop table if exists #stores
drop table if exists #dates


/*
-- For testing replacement code...
select lsd.*
from #LocSchemeDetails lsd
	inner join #limits li on lsd.LocNo = li.LocNo 
where lsd.minDt >= li.minDt
	and lsd.minDt <= li.maxDt
except
select *
from ReportsView..ShpSld_SIPS s
where exists (select minDt from #minDts m where m.minDt = s.minDt)

drop table #subjects
drop table #sipsItemCounts
drop table #sipsSales
drop table #xfers


*/


GO
