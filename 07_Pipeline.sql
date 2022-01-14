

--Product Pipeline---------------------------------------------------
---------------------------------------------------------------------
-- Manually define the setID for the current suggested orders 
-- (e.g.if there's a later/experimental set between now and the most recent actual set)
declare @setID int = 44 --(select max(SetID) from ReportsView..SuggOrds_OrigOrders)  --
-- ...or just pull the most recent/biggest setID:
-- select * from ReportsView..SuggOrds_Params order by SetID desc
-- declare @setID int = (select max(SetID) from ReportsView..SuggOrds_OrigOrders)

-- SetID for the most recent 180-Day Out Of Stock Sugg Ords set
declare @OoS_setID int = 36


--TTB & HPB CDC Available Inventory-----------------------
drop table if exists #PoolCheck
;with prep as(
    select li.Item
        ,min(li.RECEIVED_DATE)[FirstDate]
        ,sum(li.ON_HAND_QTY - li.ALLOCATED_QTY - li.SUSPENSE_QTY + li.IN_TRANSIT_QTY)[InvQ]
    from wms_ils..LOCATION_INVENTORY li 
        inner join wms_ils..location l on li.location = l.location
    where li.COMPANY in ('TTB','HPB') 
        and l.LOCATION_CLASS = 'Inventory' --This excludes items in prcv-dock-01, like assortments in-process. Amazing!
    group by li.Item
    having sum(li.ON_HAND_QTY - li.ALLOCATED_QTY - li.SUSPENSE_QTY + li.IN_TRANSIT_QTY) > 0
)
select p.*
    ,sum(case when Status1 >= 100 and Status1 < 300 then sd.TOTAL_QTY else 0 end)[WaveQ]
    ,sum(case when Status1 >= 300 and Status1 < 900 then sd.TOTAL_QTY else 0 end)[ProgQ]
	,max(sd.DATE_TIME_STAMP)[maxWvDt]
into #PoolCheck
from prep p 
    left join wms_ils..Shipment_Detail sd on p.item = sd.item and sd.CUSTOMER = 'HPB'
group by p.Item
    ,p.FirstDate
    ,p.InvQ
    

-- Items in Scale Inventory------------------------------------
drop table if exists #PipelineInv
--   delete from #PipelineInv where Status in ('3 - Scale Inv','4 - Waved Inv')
;with rcts as(
    select rd.Item,rd.DATE_TIME_STAMP,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rd.ITEM_CATEGORY3,sum(rd.TOTAL_QTY)[RctQty]
      from wms_ils..RECEIPT_DETAIL rd inner join wms_ils..RECEIPT_HEADER rh on rd.INTERNAL_RECEIPT_NUM = rh.INTERNAL_RECEIPT_NUM
      group by rd.Item,rd.DATE_TIME_STAMP,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rd.ITEM_CATEGORY3
    union all select rd.Item,rd.DATE_TIME_STAMP,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rd.ITEM_CATEGORY3,sum(rd.TOTAL_QTY)[RctQty]
      from wms_ils..ar_RECEIPT_DETAIL rd inner join wms_ils..ar_RECEIPT_HEADER rh on rd.INTERNAL_RECEIPT_NUM = rh.INTERNAL_RECEIPT_NUM
      group by rd.Item,rd.DATE_TIME_STAMP,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rd.ITEM_CATEGORY3
    union all select rd.Item,rd.DATE_TIME_STAMP,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rd.ITEM_CATEGORY3,sum(rd.TOTAL_QTY)[RctQty]
      from wms_ar_ils..ar_RECEIPT_DETAIL rd inner join wms_ar_ils..ar_RECEIPT_HEADER rh on rd.INTERNAL_RECEIPT_NUM = rh.INTERNAL_RECEIPT_NUM
      group by rd.Item,rd.DATE_TIME_STAMP,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rd.ITEM_CATEGORY3
)
,pos as(
    select pd.Item,ph.CREATED_DATE_TIME,ph.PURCHASE_ORDER_ID,ph.SHIP_FROM,pd.ITEM_CATEGORY3,sum(pd.TOTAL_QUANTITY)[PoQty]
      from wms_ils..PURCHASE_ORDER_DETAIL pd inner join wms_ils..PURCHASE_ORDER_HEADER ph on pd.PURCHASE_ORDER_ID = ph.PURCHASE_ORDER_ID
      group by pd.Item,ph.CREATED_DATE_TIME,ph.PURCHASE_ORDER_ID,ph.SHIP_FROM,pd.ITEM_CATEGORY3
    -- There's no call to wms_ils..ar_PURCHASE_ORDER_% tables because data doesn't get saved there. For some reason.
    union all select pd.Item,ph.CREATED_DATE_TIME,ph.PURCHASE_ORDER_ID,ph.SHIP_FROM,pd.ITEM_CATEGORY3,sum(pd.TOTAL_QUANTITY)[PoQty]
      from wms_ar_ils..ar_PURCHASE_ORDER_DETAIL pd inner join wms_ar_ils..ar_PURCHASE_ORDER_HEADER ph on pd.PURCHASE_ORDER_ID = ph.PURCHASE_ORDER_ID
      group by pd.Item,ph.CREATED_DATE_TIME,ph.PURCHASE_ORDER_ID,ph.SHIP_FROM,pd.ITEM_CATEGORY3
)
select md.Item
    ,coalesce(r.Item_Category3,p.Item_Category3)[SchID]
    ,case when md.InvQ <= md.WaveQ then 0 else md.InvQ-md.WaveQ end [Qty]
    ,cast(case when md.WaveQ + md.ProgQ = 0 then '3 - Scale Inv' else '4 - Waved Inv' end as varchar(20))[Status]
    ,md.FirstDate[LastDate]
    ,cast(coalesce(r.Receipt_ID,'no rct') as varchar(20))[Notes1]
    ,cast(coalesce(r.SHIP_FROM,p.SHIP_FROM) as varchar(20))[Notes2]
into #PipelineInv
from #PoolCheck md
    outer apply( --find the receipt with the most recent close date (kinda dodgy since rcts can be reopened/closed) before the inventory's "received date"
        select top 1 rc.RECEIPT_ID,rc.SHIP_FROM,rc.ITEM_CATEGORY3
            ,datediff(HH,md.FirstDate,coalesce(rc.CLOSE_DATE,rc.DATE_TIME_STAMP))/24.0[DaysDiff]
        from rcts rc
        where md.ITEM = rc.ITEM and rc.CLOSE_DATE is not null
        order by abs(datediff(HH,md.FirstDate,coalesce(rc.CLOSE_DATE,rc.DATE_TIME_STAMP)))
    )r
    outer apply( --find the PO with the most recent create date before the inventory's "received date", in case no receipts exist
        select top 1 po.PURCHASE_ORDER_ID,po.SHIP_FROM,po.ITEM_CATEGORY3
            ,datediff(HH,md.FirstDate,po.CREATED_DATE_TIME)/24.0[DaysDiff]
        from pos po
        where md.ITEM = po.ITEM
        order by abs(datediff(HH,md.FirstDate,po.CREATED_DATE_TIME))
    )p


-- Items on Purchase Orders w/ no receipts----------------------------------
--   delete from #PipelineInv where Status in ('1a - PO without Rcts')
insert into #PipelineInv
select pd.Item
    ,pd.ITEM_CATEGORY3[SchID]
    ,SUM(pd.TOTAL_QUANTITY)[Qty]
    ,cast('1a - PO without Rcts' as varchar(30))[Status]
    ,max(pd.DATE_TIME_STAMP)[LastDate]
    ,cast(max(pd.PURCHASE_ORDER_ID) as varchar(20))[Notes1]
    ,max(ph.SHIP_FROM)[Notes2]
from wms_ils..PURCHASE_ORDER_HEADER ph with(nolock)
    inner join wms_ils..PURCHASE_ORDER_DETAIL pd with(nolock) on ph.PURCHASE_ORDER_ID = pd.PURCHASE_ORDER_ID 
	-- Make sure PO hasn't been deleted from Dips. Because that happens. And Scale doesn't get updated! :D Also, don't accidentally drop HPR% POs.
	inner join ReportsView..vw_PurchaseOrders po with(nolock) on right(ph.PURCHASE_ORDER_ID,6) collate database_default = po.PONumber 
        and right('00000000000000000000' + pd.Item,20) collate database_default = po.ItemCode
where pd.PURCHASE_ORDER_ID not in (select substring(RECEIPT_ID,0,LEN(RECEIPT_ID)-2) from wms_ils..RECEIPT_DETAIL with(nolock)
                                   union select substring(RECEIPT_ID,0,LEN(RECEIPT_ID)-2) from wms_ils..AR_RECEIPT_DETAIL with(nolock) )
    -- Only POs created in the last YEAR, if NO receipts have been created
    and ph.CREATED_DATE_TIME >= DATEADD(DD,-366,getdate()) 
    and pd.COMPANY in ('HPB','TTB') 
    -- janky avoidance of POs created to create item codes only
    and pd.TOTAL_QUANTITY > 1
group by pd.Item
    ,pd.ITEM_CATEGORY3
    

-- Items that have never been on receipts, on POs that have receipts that closed less than 6 months ago--------------------
-- idea being we'll give these items another 6 months to show up after the last receipt closed (even if the PO is >1yr old)
--   delete from #PipelineInv where Status in ('1b - PO with Rcts')
insert into #PipelineInv
select pd.Item
    ,pd.ITEM_CATEGORY3[SchID]
    ,SUM(pd.TOTAL_QUANTITY)[Qty]
    ,'1b - PO with Rcts'[Status]
    ,max(pd.DATE_TIME_STAMP)[LastDate]
    ,max(pd.PURCHASE_ORDER_ID)[Notes1]
    ,max(ph.SHIP_FROM)[Notes2]
from wms_ils..PURCHASE_ORDER_HEADER ph  with(nolock)
    inner join wms_ils..PURCHASE_ORDER_DETAIL pd with(nolock) on ph.PURCHASE_ORDER_ID = pd.PURCHASE_ORDER_ID 
where pd.COMPANY in ('HPB','TTB')
    -- janky avoidance of POs created to create item codes only
    and pd.TOTAL_QUANTITY > 1										
    and exists (select RECEIPT_ID from wms_ils..RECEIPT_HEADER where pd.PURCHASE_ORDER_ID = substring(RECEIPT_ID,0,LEN(RECEIPT_ID)-2) 
                and coalesce(CLOSE_DATE,CREATION_DATE_TIME_STAMP) > DATEADD(DD,-180,getdate()) )	
    and not exists (select ITEM from wms_ils..RECEIPT_DETAIL where ITEM=pd.ITEM and PURCHASE_ORDER_ID=pd.PURCHASE_ORDER_ID
                    union select ITEM from wms_ils..AR_RECEIPT_DETAIL where ITEM=pd.ITEM and PURCHASE_ORDER_ID=pd.PURCHASE_ORDER_ID
                    union select ITEM from wms_ar_ils..AR_RECEIPT_DETAIL where ITEM=pd.ITEM and PURCHASE_ORDER_ID=pd.PURCHASE_ORDER_ID )	
group by pd.Item
    ,pd.ITEM_CATEGORY3
   

---Items on Open/Unreceived Receipts---------------------------------------------------------
--   delete from #PipelineInv where Status in ('2 - Open Rct')
insert into #PipelineInv
select rd.Item
    ,rd.ITEM_CATEGORY3[SchID]
    ,SUM(rd.TOTAL_QTY)[Qty]
    ,'2 - Open Rct'[Status]
    ,max(rd.RECEIPT_DATE)
    ,max(rd.RECEIPT_ID)[Notes1]
    ,max(rh.SHIP_FROM)[Notes2]
from wms_ils..RECEIPT_HEADER rh with(nolock) 
    inner join wms_ils..RECEIPT_DETAIL rd with(nolock) on rh.INTERNAL_RECEIPT_NUM=rd.INTERNAL_RECEIPT_NUM
where rd.TOTAL_QTY=rd.OPEN_QTY 
    and rh.CLOSE_DATE is null
    and rd.COMPANY in ('HPB','TTB')
group by rd.Item
    ,rd.ITEM_CATEGORY3


---- Scale inv without a receipt was adjusted into inventory, insted of being received into inventory. 
-- This happens either because folks wanted an item under a different company, like with a bunch of product from April 2020;
-- or because we don't have an actual item code for the product, like what happens with "straggler" product sent to us that wasn't on the PO. 
-- It's cheaper for us process it instead of trying to send it back. Mostly.
-- Since there's no reliably consistent/systematic way (at least that anyone uses) to cancel a PO, nor to create items withOUT a PO, 
-- we're left with a bunch of "junk" POs in the system we're never going to see inventory from.
-- This is another step in trying to filter out some of that stuff, for when the item code conventiently doesn't change. 
-- The "pd.TOTAL_QUANTITY > 1" criteria when adding to the #PipelineInv table was another step to catch "used only to create items" POs.
-- There's another step below that looks for matching ISBN's or Titles on #PipelineInv lines, along with specific statuses.
drop table if exists #unduped
;with adjs as(
    select distinct Item,Notes1
    from #PipelineInv 
    where Notes1 = 'no rct'
)
select pl.Item
    ,pl.SchID
    ,pl.Qty
    ,pl.Status
    ,pl.LastDate
    ,pl.Notes1
    ,pl.Notes2
    ,count(*) over(partition by pl.Item)[NumStss]
into #unduped
from #PipelineInv pl
    left join adjs aj on pl.ITEM = aj.item 
where aj.Notes1 is null or aj.Notes1 = pl.Notes1
-- To see what's excluded...
-- where aj.Notes1 is not null and isnull(aj.Notes1,'') <> pl.Notes1


drop table if exists #staging
;with moar as(
	select pl.Item
		,pl.Status
		,count(*) over(partition by pl.Item)[#Lines]
		,pl.Notes1,pl.Notes2
        ,pl.SchID[OrigSchID]
		,cast(pl.LastDate as date)[LastDate]
        -- ,coalesce(pg.RordGrp,case when pm.UserChar15 = 'TTB' then 'TRO' else 'CDC' end)[RordGrp]
        -- New logic, to possibly route mis-assigned Inac back into CDC:
        ,case when pm.UserChar15 = 'TTB' then 'TRO' when pg.ngqVendor <> 'Inac' and pg.RordGrp = 'HRO' then 'HRO' else 'CDC' end[RordGrp]
		,isnull(pm.PurchaseFromVendorID,'')[RordVendor]
        ,ss.Cap
        ,ss.Secn
        ,ss.DefaultScheme[SecnSchID]
		,coalesce(nullif(pm.ISBN,''),nullif(pm.UPC,''),it.ITEM_STYLE collate database_default)[ISBN/UPC]
		,it.DESCRIPTION[Title]
        ,it.USER_DEF4[Cost]
        ,it.NET_PRICE[Price]
		,cast(pl.Qty as int)[Qty]
        ,isnull(cast(sc.Total_Scheme_Qty as int),0)[OrigSchQ]
		,isnull(cast(ch.Total_Scheme_Qty as int),0)[SecnSchQ]
		,isnull(pm.ReorderableItem+pm.Reorderable,'NN')[RIR]
		,case when isnull(mr.atLocs,0) + isnull(mr.atRoS,0) - isnull(mr.atWhRoS,0) + isnull(mr.LGI,0) = 0  
                -- and (pl.Status <> '4 - Waved Inv' or coalesce(pg.RordGrp,case when pm.UserChar15 = 'TTB' then 'TRO' else 'CDC' end) = 'CDC') 
                and (pl.Status <> '4 - Waved Inv' or case when pm.UserChar15 = 'TTB' then 'TRO' when pg.ngqVendor <> 'Inac' and pg.RordGrp = 'HRO' then 'HRO' else 'CDC' end = 'CDC') 
              then 'init' else 'rord' end[OrdCat]
		,coalesce(ng.RptIt,hr.RptIt,'new')[RptIt]
		,isnull(mr.LGI,0)[chInvQ]
		,isnull(mr.crSldQ,0)[crSldQ]
		,isnull(mr.atSldQ,0)[atSldQ]
		,isnull(mr.crLocs,0)[crLocs]
		,isnull(mr.atLocs,0)[atLocs]
		,isnull(mr.CrRoS,0)[CrRoS]
		,isnull(mr.atRoS,0)[AtRoS]
		,isnull(mr.CrWhRoS,0)[CrWhRoS]
		,isnull(mr.AtWhRoS,0)[AtWhRoS]
		,isnull(mr.crWhCusts,0)[crWsCusts]
		,isnull(mr.atWhCusts,0)[atWsCusts]
        ,(pl.Qty + isnull(mr.LGI,0)) / nullif(mr.crRoS,0)[DaysCrRoS]
        ,(pl.Qty + isnull(mr.LGI,0)) / nullif(mr.atRoS,0)[DaysAtRoS]
		,count(*) over(partition by it.DESCRIPTION)[nTis]
		,count(*) over(partition by it.DESCRIPTION,pm.UserChar15)[nTiPerCmp]
		,min(left(pl.Status,2)) over(partition by it.Description)[minTiSts]
        ,left(pl.Status,1)[StsID]
	from #unduped pl
        left join WMS_ILS..item it on pl.item = it.item
		left join ReportsView..vw_DistributionProductMaster pm on right('00000000000000000000'+pl.item,20) collate database_default = pm.ItemCode
		left join ReportsView..ngXacns_Items ng with(nolock) on pm.ItemCode = ng.ItemCode
		left join ReportsView..hroXacns_Items hr with(nolock) on pm.ItemCode = hr.ItemCode
        left join ReportsView..ProdGoals_ItemMaster pg with(nolock) on pg.ItemCode = pm.ItemCode
		left join ReportsView..ShpSld_SbjScnCapMap ss on pm.SectionCode = ss.Section
		left join ReportsView..Pipeline_MrgdRoSs mr on coalesce(ng.RptIt,hr.RptIt,pm.ItemCode) = mr.RptIt
		left join wms_ils..HPB_Scheme_Header sc with(nolock) on pl.SchID = sc.Scheme_ID collate database_default
		left join wms_ils..HPB_Scheme_Header ch with(nolock) on ss.DefaultScheme = ch.Scheme_ID collate database_default
)
select case 
        when mr.Status = '1b - PO with Rcts' and mr.nTis >= 2 and mr.nTiPerCmp = 1 and mr.minTiSts = left(mr.Status,2) then 'maybe' 
		when mr.Status <> '1a - PO without Rcts' or mr.nTis < 2 or mr.nTiPerCmp > 1 then 'ok' else 'dup' end[DupLine]
	,*
    ,case when StsID > 2  and RptIt <> 'new' then row_number() over(partition by RptIt order by RIR desc,Item) end[RptItDistRnk]
into #staging
from moar mr



-- 01: Output for PipelineDetails tab--------------------------
---------------------------------------------------------------
-- SuggOrds data from most recent set----

truncate table ReportsView.dbo.Pipeline
--   declare @setID int = 44 declare @OoS_setID int = 36 --(select * from ReportsView..SuggOrds_Params)
;with SuggOrds as(
    select RptIt
        ,cast(sum(      case when SetID = @SetID then OrderQty else 0 end) as int)[SuggOrdQty]
        ,count(distinct case when SetID = @SetID and OrderQty > 0 then Loc end)[SuggOrdLocs]
        ,cast(sum(      case when SetID = @OoS_setID then OrderQty else 0 end) as int)[OoS_SuggOrdQty]
        ,count(distinct case when SetID = @OoS_setID and OrderQty > 0 then Loc end)[OoS_SuggOrdLocs]
    from ReportsView..SuggOrds_OrigOrders o
    where SetID in (@setID,@OoS_setID) 
        -- and RptIt = '00000000000001805020'
    group by RptIt
)
insert into ReportsView..Pipeline
select right(concat('00000000000000000000',cast(f.Item as varchar(20))),20) collate database_default [ItemCode]
    ,f.[Status]
    ,f.[#Lines]
    ,f.Notes1[PO/Rct]
    ,f.Notes2[OrigVendor]
    ,f.OrigSchID
    ,f.LastDate[StatusDt]
    ,f.RordGrp[Prog]
    ,f.RordVendor,f.Cap,f.Secn
    ,f.SecnSchID
    ,f.[ISBN/UPC]
    ,f.Title,f.Cost,f.Price
    ,f.Qty,f.OrigSchQ,f.SecnSchQ
    ,f.RIR,f.OrdCat
    ,f.RptIt,f.chInvQ
    -- empty field instead of zero ==> suggestions weren't calculated
    -- ,f.RptItDistRnk,f.StsID,o.OoS_SuggOrdQty,o.SuggOrdQty
    ,case when o.OoS_SuggOrdQty >= o.SuggOrdQty then o.OoS_SuggOrdQty else o.SuggOrdQty end[SuggOrdQty]
    ,f.crSldQ,f.atSldQ
    ,case when o.OoS_SuggOrdQty >= o.SuggOrdQty then o.OoS_SuggOrdLocs else o.SuggOrdLocs end[SuggOrdLocs]
    ,f.crLocs,f.atLocs
    ,f.CrRoS,f.AtRoS
    ,f.CrWhRoS,f.AtWhRoS
    ,f.crWsCusts,f.atWsCusts
    ,f.DaysCrRoS
    ,f.DaysAtRoS
-- into ReportsView.dbo.Pipeline
from #staging f 
    left join SuggOrds o on f.RptIt collate database_default = o.RptIt collate database_default --and (f.RptItDistRnk = 1 or f.StsID < 3)
where DupLine = 'ok'
    and Notes1 not in ('513161','509383','510155','509725') -- junk POs of the Llewellyn assortment that was ultimately received under PO 518323
    -- and f.RptIt = '00000000000001805020'

select * 
from ReportsView..Pipeline
order by Prog
    ,[ISBN/UPC]
    ,[Status] desc
    ,ItemCode



--02: Output for mockup tab showing Pipeline by Secn for CDC & TTB------
------------------------------------------------------------------------    
-- I'm sorry. SQL's pivot syntax is hot garbage.
;with GbyS as(
    select distinct g.RordGrp --,s.Cap,s.GoalGrp,s.Secn,s.Section
        ,case when s.Section is null then 'zzz' else s.Cap end[Cap]
        ,case when s.Section is null then 'zzz' else s.GoalGrp end[GoalGrp]
        ,case when s.Section is null then '--SectionMissing--' else s.Secn end[Secn]
        ,s.Section
    from (select distinct RordGrp from ReportsView..ProdGoals_ItemMaster) g
        cross join ReportsView..ShpSld_SbjScnCapMap s)
select gs.Cap,gs.Secn
    -- CDC-only product----------------
	,sum(           case when gs.RordGrp = 'CDC' and i.StsID > 2 then i.Qty else 0 end)[iCdcQty]
	,sum(           case when gs.RordGrp = 'CDC' and i.StsID = 2 then i.Qty else 0 end)[rCdcQty]
	,sum(           case when gs.RordGrp = 'CDC' and i.StsID = 1 then i.Qty else 0 end)[pCdcQty]
	,count(distinct case when gs.RordGrp = 'CDC' and i.StsID > 2 then i.Item       end)[iCdcTi]
	,count(distinct case when gs.RordGrp = 'CDC' and i.StsID = 2 then i.Item       end)[rCdcTi]
	,count(distinct case when gs.RordGrp = 'CDC' and i.StsID = 1 then i.Item       end)[pCdcTi]
    -- ALL TTB product------------------
	,sum(           case when gs.RordGrp = 'TRO' and i.StsID > 2 then i.Qty else 0 end)[iTtbQty]
	,sum(           case when gs.RordGrp = 'TRO' and i.StsID = 2 then i.Qty else 0 end)[rTtbQty]
	,sum(           case when gs.RordGrp = 'TRO' and i.StsID = 1 then i.Qty else 0 end)[pTtbQty]
	,count(distinct case when gs.RordGrp = 'TRO' and i.StsID > 2 then i.Item       end)[iTtbTi]
	,count(distinct case when gs.RordGrp = 'TRO' and i.StsID = 2 then i.Item       end)[rTtbTi]
	,count(distinct case when gs.RordGrp = 'TRO' and i.StsID = 1 then i.Item       end)[pTtbTi]
    -- TTB initial product--------------
	,count(distinct case when gs.RordGrp = 'TRO' and i.StsID > 2 and i.OrdCat = 'init' then i.Item       end)[iTi]
	,count(distinct case when gs.RordGrp = 'TRO' and i.StsID = 2 and i.OrdCat = 'init' then i.Item       end)[rTi]
	,count(distinct case when gs.RordGrp = 'TRO' and i.StsID = 1 and i.OrdCat = 'init' then i.Item       end)[pTi]
	,sum(           case when gs.RordGrp = 'TRO' and i.StsID > 2 and i.OrdCat = 'init' then i.Qty else 0 end)[iQty]
	,sum(           case when gs.RordGrp = 'TRO' and i.StsID = 2 and i.OrdCat = 'init' then i.Qty else 0 end)[rQty]
	,sum(           case when gs.RordGrp = 'TRO' and i.StsID = 1 and i.OrdCat = 'init' then i.Qty else 0 end)[pQty]
from GbyS gs left join #staging i 
    on (gs.Section = i.Secn or (gs.Section is null and i.Secn is null))
    and gs.RordGrp = i.RordGrp and i.DupLine = 'ok'
where gs.Secn not in ('0','BCD','BTFic','BTNonFic','Kids','NONE','Stash','')
    and gs.RordGrp in ('CDC','TRO')
group by gs.Cap,gs.Secn
order by 1,2
 


/* -- temp table cleanup----------------
drop table if exists #staging
drop table if exists #unduped
drop table if exists #PipelineInv
drop table if exists #PoolCheck


*/