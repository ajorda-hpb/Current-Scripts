
-- Code for the #MrgdRoSs table that is/was part of the pipeline, but may not be in a future version.

-- Secn RoS Staging------------------------------
-------------------------------------------------
declare @Cutoff date = (select dateadd(YY,-15,getdate()))
declare @CrPer int = 3


--TTB & HPB CDC Available Inventory-----------------------
drop table if exists #wmsInv
select s.Secn
    ,coalesce(pg.RordGrp,case when li.company = 'TTB' then 'TRO' else 'CDC' end)[RordGrp]
    ,li.Item
    ,right('00000000000000000000' + it.Item,20) collate database_default [ItemCode]
    ,sum(li.ON_HAND_QTY - li.ALLOCATED_QTY - li.SUSPENSE_QTY)[AllQty]
    ,sum(case when l.LOCATION_CLASS = 'Inventory' then li.ON_HAND_QTY - li.ALLOCATED_QTY - li.SUSPENSE_QTY else 0 end)[Qty]
    ,it.ITEM_CATEGORY3[SchID]
    ,sch.TOTAL_SCHEME_QTY[SchTot]
    ,it.USER_DEF4[Cost]
    ,it.NET_PRICE[Price]
    ,it.NET_PRICE-it.USER_DEF4[Profit]
    ,min(li.RECEIVED_DATE)[FirstDate]
    ,max(li.RECEIVED_DATE)[LastDate]
    ,count(*)[Lines]
    ,max(li.USER_STAMP)[MaxUsr]
into #wmsInv
from wms_ils..LOCATION_INVENTORY li with(nolock)
    inner join wms_ils..location l with(nolock) on li.location = l.location
    left join wms_ils..item it with(nolock) on li.item = it.item
    left join ReportsView..ShpSld_SbjScnCapMap s on s.Section = ltrim(rtrim(it.ITEM_CATEGORY1 collate database_default))
    left join ReportsView..ProdGoals_ItemMaster pg with(nolock) on pg.ItemCode = right('00000000000000000000' + it.Item,20) collate database_default
    left join WMS_ILS..HPB_SCHEME_HEADER sch with(nolock) on it.ITEM_CATEGORY3 = sch.SCHEME_ID
where li.COMPANY in ('TTB','HPB')
    and l.LOCATION_CLASS = 'Inventory' --This excludes items in prcv-dock-01, like assortments in-process. Amazing!
group by s.Secn
    ,li.Item
    ,right('00000000000000000000' + it.Item,20) collate database_default
    ,coalesce(pg.RordGrp,case when li.company = 'TTB' then 'TRO' else 'CDC' end)
    ,it.USER_DEF4
    ,it.NET_PRICE
    ,it.ITEM_CATEGORY3
    ,sch.TOTAL_SCHEME_QTY
having sum(li.ON_HAND_QTY - li.ALLOCATED_QTY - li.SUSPENSE_QTY) > 0




-- Wholesale Sales---------------------------------
-- All Wholesale sales in last @CrPer months for comparing Section breadth and individual Item performance
drop table if exists #WhslRoSs
;with whsl as(
    select sh.ACTUAL_SHIP_DATE_TIME[ShipDt]
            ,sh.CUSTOMER,sd.Item
            ,sd.TOTAL_QTY[SoldQty]
        from wms_ils..SHIPMENT_DETAIL sd with(nolock)
            inner join wms_ils..SHIPMENT_HEADER sh with(nolock) on sd.INTERNAL_SHIPMENT_NUM = sh.INTERNAL_SHIPMENT_NUM
        where sd.ORDER_TYPE in ('TTB WHOLESALE','WEBORDER')
            and sd.company = 'TTB' and sh.ACTUAL_SHIP_DATE_TIME is not null and sd.Customer not in ('SAMPLE','REPS')
    union all select sh.ACTUAL_SHIP_DATE_TIME[ShipDt]
            ,sh.CUSTOMER,sd.Item,sd.TOTAL_QTY[SoldQty]
        from wms_ils..ar_SHIPMENT_DETAIL sd with(nolock)
            inner join wms_ils..ar_SHIPMENT_HEADER sh with(nolock) on sd.INTERNAL_SHIPMENT_NUM = sh.INTERNAL_SHIPMENT_NUM
        where sd.ORDER_TYPE in ('TTB WHOLESALE','WEBORDER')
            and sd.company = 'TTB' and sh.ACTUAL_SHIP_DATE_TIME is not null and sd.Customer not in ('SAMPLE','REPS')
    union all select sh.ACTUAL_SHIP_DATE_TIME[ShipDt]
            ,sh.CUSTOMER,sd.Item,sd.TOTAL_QTY[SoldQty]
        from wms_ar_ils..ar_SHIPMENT_DETAIL sd with(nolock)
            inner join wms_ar_ils..ar_SHIPMENT_HEADER sh with(nolock) on sd.INTERNAL_SHIPMENT_NUM = sh.INTERNAL_SHIPMENT_NUM
        where sd.ORDER_TYPE in ('TTB WHOLESALE','WEBORDER')
            and sd.company = 'TTB' and sh.ACTUAL_SHIP_DATE_TIME is not null and sd.Customer not in ('SAMPLE','REPS')
)
,excludes as(
    select sa.Item from whsl sa group by sa.Item having min(ShipDt) < @Cutoff
)
select coalesce(it.RptIt,right('00000000000000000000' + wh.item,20) collate database_default)[RptIt]
    ,it.RptIt[origRptIt]
    ,min(case when md.Item is null then 'inac' else 'active' end)[Active]
    ,min(wh.ShipDt)[minShpDt]
    ,sum(case when wh.ShipDt >= dateadd(MONTH,-@CrPer,getdate()) then wh.SoldQty else 0 end)[crSldQ]
    ,sum(wh.SoldQty)[atSldQ]
    ,count(distinct case when wh.ShipDt >= dateadd(MONTH,-@CrPer,getdate()) then wh.CUSTOMER end)[crCusts]
    ,count(distinct wh.CUSTOMER)[atCusts]
    ,sum(case when wh.ShipDt >= dateadd(MONTH,-@CrPer,getdate()) then wh.SoldQty else 0 end) / 30.3 / @CrPer [CrWhRoS]
    ,sum(wh.SoldQty) * 24.0 / isnull(nullif(datediff(HH,min(wh.ShipDt),max(wh.ShipDt)),0),28 * 24.0) [AtWhRoS]
    ,convert(numeric(19,5), isnull(nullif(datediff(HH,min(wh.ShipDt),max(wh.ShipDt)),0),28 * 24.0) / 24.0)[ActiveDays]
    ,convert(numeric(19,5), datediff(HH,max(wh.ShipDt),getdate()) / 24.0)[DaysDiff]
into #WhslRoSs
from whsl wh
    left join ReportsView..ngXacns_Items it with(nolock) 
        on right('00000000000000000000' + wh.item,20) collate database_default = it.ItemCode
    left join #wmsInv md on md.Item = wh.Item 
    left join excludes ex on ex.Item = wh.Item
where ex.item is null
group by coalesce(it.RptIt,right('00000000000000000000' + wh.item,20) collate database_default)
    ,it.RptIt
having sum(wh.SoldQty) > 0


-- All-Time Retail Sales---------------------------
drop table if exists #atRtlRoSs
;with excludes as(
    select RptIt from ReportsView..ngXacns ng with(nolock) 
        inner join ReportsView..ngXacns_Items it with(nolock) on ng.ItemCode = it.ItemCode
    group by RptIt
    having max(Date) < @Cutoff
)
select it.RptIt
    ,count(distinct case when bd.LGI > 1 and (bd.maxDt > dateadd(MONTH,-@CrPer,getdate())) then bd.Loc end)[crLocs]
    ,count(distinct bd.Loc)[atLocs]
    ,sum(bd.LGI)[LGI]
    ,sum(bd.SoldQty)[atSldQ]
    ,sum(case when bd.zRoS > 3 then (ie.avgRoS+bd.RoS)*0.5 else bd.RoS end)[atRoS]
    ,ie.avgRoS[avLocRoS]
into #atRtlRoSs
from ReportsView..SuggOrds_BaseData bd with(nolock)
    left join excludes ex on bd.RptIt = ex.RptIt
    -- need to join on both because SOMETIMES the RptIt changes and will be up to date on ngxacns, 
    -- but since SuggOrds only updates every 3wks, it can be out of date.
    inner join ReportsView..ngXacns_Items it on bd.RptIt = it.ItemCode
    inner join ReportsView..SuggOrds_ItemEquivs ie with(nolock) on bd.RptIt = ie.ItemCode
where ex.RptIt is null
group by it.RptIt,ie.avgRoS


-- Current Period Retail Sales--------------------
drop table if exists #crRtlRoSs
;with excludes as(
    select RptIt from ReportsView..ngXacns ng with(nolock) 
        inner join ReportsView..ngXacns_Items it with(nolock) on ng.ItemCode = it.ItemCode
    group by RptIt
    having max(Date) < @Cutoff
)
select it.RptIt
    ,it.riSection[Section]
    ,im.RordGrp
    -- If ANY item is active, then the RptIt is active. Also, I apologize for aggregating on a string. >.>
    ,min(case when md.Item is null then 'inac' else 'active' end)[Active]
    --,count(distinct it.Item)[NumIts]
    ,min(ng.Date)[minShpDt]
    ,convert(numeric(19,5),datediff(HH,min(ng.Date),max(ng.Date))/24.0)[ActiveDays]
    ,convert(numeric(19,5),datediff(HH,max(ng.Date),getdate()) / 24.0)[DaysDiff]

    ,sum(case when xacn in ('CDC','Drps') and ng.Date > dateadd(MONTH,-@CrPer,getdate()) then ng.Qty else 0 end)[crShpQ]
    ,sum(case when xacn in ('CDC','Drps') then ng.Qty else 0 end)[atShpQ]

    ,count(distinct case when ng.Date > dateadd(MONTH,-@CrPer,getdate()) then ng.Loc end)[crLocs]
    ,sum(case when xacn in ('Sale','iSale','hSale','Rtrn') and ng.Date > dateadd(MONTH,-@CrPer,getdate()) then -ng.Qty else 0 end)[crSldQ]
    ,sum(case when xacn in ('Sale','iSale','hSale','Rtrn') and ng.Date > dateadd(MONTH,-@CrPer,getdate()) then -ng.Qty else 0 end) / 30.3 / @CrPer [crRoS]

    --,count(distinct ng.Loc)[atLocs]
    ,sum(case when xacn in ('Sale','iSale','hSale','Rtrn') then -ng.Qty else 0 end)[atSldQ]
    ,sum(case when xacn in ('Sale','iSale','hSale','Rtrn') then -ng.Qty else 0 end)
        / nullif(convert(numeric(19,5),datediff(DD,min(ng.Date),max(ng.Date))),0)[atRoS]
into #crRtlRoSs
from ReportsView..ngXacns ng with(nolock)
    inner join ReportsView..ngXacns_Items it with(nolock) on ng.ItemCode = it.ItemCode
    left join excludes ex on it.RptIt = ex.RptIt
    inner join ReportsView..ProdGoals_ItemMaster im with(nolock) on ng.Item = im.ItemCode
    left join #wmsInv md on ng.ItemCode = md.ItemCode
where ex.RptIt is null
group by it.RptIt
    ,it.riSection
    ,im.RordGrp


-- Staging Table of all RptIts
drop table if exists #SecnIts
;with its as(
    select distinct cr.RptIt from #crRtlRoSs cr 
    union select distinct w.RptIt from #WhslRoSs w 
    union select distinct ar.RptIt from #atRtlRoSs ar
    )
select im.RordGrp,ss.Cap
    ,ss.GoalGrp,ss.Secn
    ,ss.DefaultScheme[DefSchID]
    ,ch.Total_Scheme_Qty[SchQ]
    ,it.RptIt
    ,case when isnull(r.InvQ,0) > 0 then 'active' else 'inac' end[Active]
into #SecnIts
from its it
    inner join ReportsView..vw_DistributionProductMaster pm with(nolock) on it.RptIt = pm.ItemCode
    inner join ReportsView..ProdGoals_ItemMaster im with(nolock) on pm.ItemCode = im.ItemCode
    inner join ReportsView..ShpSld_SbjScnCapMap ss with(nolock) on pm.SectionCode = ss.Section
    inner join wms_ils..HPB_Scheme_Header ch with(nolock) on ss.DefaultScheme = ch.Scheme_ID collate database_default
    left join (select i.RptIt,sum(m.Qty)[InvQ] from #wmsInv m 
                inner join ReportsView..ngXacns_Items i on m.ItemCode = i.ItemCode 
                group by i.RptIt
        )r on it.RptIt = r.RptIt




drop table if exists ReportsView.dbo.Pipeline_MrgdRoSs
select si.RordGrp,si.Cap
    ,si.GoalGrp,si.Secn
    ,si.RptIt,si.Active
    ,min(coalesce(cr.minShpDt,wr.minShpDt))[minShpDt]
    ,max(case when coalesce(cr.ActiveDays,0) >= coalesce(wr.ActiveDays,0) then coalesce(cr.ActiveDays,0) 
                else coalesce(wr.ActiveDays,0) end)[ActiveDays]
    ,max(case when coalesce(cr.DaysDiff,0) >= coalesce(wr.DaysDiff,0) then coalesce(cr.DaysDiff,0) 
                else coalesce(wr.DaysDiff,0) end)[DaysDiff]
    ,sum(isnull(ar.LGI,0))[LGI]
    ,sum(isnull(cr.crRoS,0)+isnull(wr.crWhRoS,0))[crRoS]
    --ZidRoS removes ZIDs from the denominator. Shows what store's actual sales potential is when we bother to keep it in stock.
    ,sum(isnull(ar.atRoS,0)+isnull(wr.atWhRoS,0))[atZidRoS]
    --cr.crRoS preserves days when there's zero inv in stores. cos it's STILL sitting at the CDC not selling.
    ,sum(isnull(cr.atRoS,0)+isnull(wr.atWhRoS,0))[atRoS]
    ,sum(isnull(wr.crWhRoS,0))[crWhRoS]
    ,sum(isnull(wr.atWhRoS,0))[atWhRoS]
    ,sum(isnull(cr.atShpQ,0))[atRtlShpQ]
    ,sum(isnull(cr.atSldQ,0))[atRtlSldQ]
    ,sum(isnull(cr.crSldQ,0)+isnull(wr.crSldQ,0))[crSldQ]
    --cr.atSldQ will be SLIGHTLY more up to date since SuggOrds_BaseData only gets updated every 3wks
    ,sum(isnull(cr.atSldQ,0)+isnull(wr.atSldQ,0))[atSldQ]
    ,sum(isnull(wr.crSldQ,0))[crWhSldQ]
    ,sum(isnull(wr.atSldQ,0))[atWhSldQ]
    ,max(coalesce(ar.crLocs,0))[crLocs]
    ,max(coalesce(ar.atLocs,0))[atLocs]
    ,max(coalesce(wr.crCusts,0))[crWhCusts]
    ,max(coalesce(wr.atCusts,0))[atWhCusts]
into ReportsView.dbo.Pipeline_MrgdRoSs
from #SecnIts si 
    left join #atRtlRoSs ar on si.RptIt = ar.RptIt
    left join #crRtlRoSs cr on si.RptIt = cr.RptIt
    left join #WhslRoSs wr on si.RptIt = wr.RptIt
group by si.RordGrp,si.Cap
    ,si.GoalGrp,si.Secn
    ,si.RptIt,si.Active


/*-- Cleanup on aisle temp tables---------------------
drop table if exists #SecnIts
drop table if exists #crRtlRoSs
drop table if exists #atRtlRoSs
drop table if exists #wmsInv_prep
drop table if exists #WhslRoSs


select top 10* from #SecnIts where RptIt = '00000000000002111014'

select top 10* from #WhslRoSs where RptIt = '00000000000002111014'


*/
