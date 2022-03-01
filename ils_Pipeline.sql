



--Product Pipeline---------------------------------------------------
---------------------------------------------------------------------
/*
drop table #PoolCheck
drop table #PipelineInv
drop table #unduped
drop table #staging
*/


--TTB & HPB CDC Available Inventory-----------------------
-- drop table if exists #PoolCheck
;with prep as(
    select li.Item
        ,min(li.RECEIVED_DATE)[FirstDate]
        ,sum(li.ON_HAND_QTY - li.ALLOCATED_QTY - li.SUSPENSE_QTY + li.IN_TRANSIT_QTY)[InvQ]
    from ils..LOCATION_INVENTORY li 
        inner join ils..location l on li.location = l.location
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
    left join ils..Shipment_Detail sd on p.item = sd.item and sd.CUSTOMER = 'HPB'
group by p.Item
    ,p.FirstDate
    ,p.InvQ
    

-- Items in Scale Inventory------------------------------------
-- drop table if exists #PipelineInv
--   delete from #PipelineInv where Status in ('3 - Scale Inv','4 - Waved Inv')
;with rcts as(
    select rd.Item,rd.DATE_TIME_STAMP,rh.RECEIPT_DATE,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rh.RECEIPT_TYPE,rd.ITEM_CATEGORY3,sum(rd.TOTAL_QTY)[RctQty]
      from ils..RECEIPT_DETAIL rd inner join ils..RECEIPT_HEADER rh on rd.INTERNAL_RECEIPT_NUM = rh.INTERNAL_RECEIPT_NUM
      group by rd.Item,rd.DATE_TIME_STAMP,rh.RECEIPT_DATE,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rh.RECEIPT_TYPE,rd.ITEM_CATEGORY3
    union all select rd.Item,rd.DATE_TIME_STAMP,rh.RECEIPT_DATE,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rh.RECEIPT_TYPE,rd.ITEM_CATEGORY3,sum(rd.TOTAL_QTY)[RctQty]
      from ils..ar_RECEIPT_DETAIL rd inner join ils..ar_RECEIPT_HEADER rh on rd.INTERNAL_RECEIPT_NUM = rh.INTERNAL_RECEIPT_NUM
      group by rd.Item,rd.DATE_TIME_STAMP,rh.RECEIPT_DATE,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rh.RECEIPT_TYPE,rd.ITEM_CATEGORY3
    union all select rd.Item,rd.DATE_TIME_STAMP,rh.RECEIPT_DATE,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rh.RECEIPT_TYPE,rd.ITEM_CATEGORY3,sum(rd.TOTAL_QTY)[RctQty]
      from ar_ils..ar_RECEIPT_DETAIL rd inner join ar_ils..ar_RECEIPT_HEADER rh on rd.INTERNAL_RECEIPT_NUM = rh.INTERNAL_RECEIPT_NUM
      group by rd.Item,rd.DATE_TIME_STAMP,rh.RECEIPT_DATE,rh.CLOSE_DATE,rh.RECEIPT_ID,rh.SHIP_FROM,rh.RECEIPT_TYPE,rd.ITEM_CATEGORY3
)
,pos as(
    select pd.Item,ph.CREATED_DATE_TIME,ph.PURCHASE_ORDER_ID,ph.SHIP_FROM,ph.RECEIPT_TYPE,pd.ITEM_CATEGORY3,sum(pd.TOTAL_QUANTITY)[PoQty]
      from ils..PURCHASE_ORDER_DETAIL pd inner join ils..PURCHASE_ORDER_HEADER ph on pd.PURCHASE_ORDER_ID = ph.PURCHASE_ORDER_ID
      group by pd.Item,ph.CREATED_DATE_TIME,ph.PURCHASE_ORDER_ID,ph.SHIP_FROM,ph.RECEIPT_TYPE,pd.ITEM_CATEGORY3
    -- There's no call to ils..ar_PURCHASE_ORDER_% tables because data doesn't get saved there. For some reason.
    union all select pd.Item,ph.CREATED_DATE_TIME,ph.PURCHASE_ORDER_ID,ph.SHIP_FROM,ph.RECEIPT_TYPE,pd.ITEM_CATEGORY3,sum(pd.TOTAL_QUANTITY)[PoQty]
      from ar_ils..ar_PURCHASE_ORDER_DETAIL pd inner join ar_ils..ar_PURCHASE_ORDER_HEADER ph on pd.PURCHASE_ORDER_ID = ph.PURCHASE_ORDER_ID
      group by pd.Item,ph.CREATED_DATE_TIME,ph.PURCHASE_ORDER_ID,ph.SHIP_FROM,ph.RECEIPT_TYPE,pd.ITEM_CATEGORY3
)
select md.Item
    ,coalesce(r.Item_Category3,p.Item_Category3)[SchID]
    ,case when md.InvQ <= md.WaveQ then 0 else md.InvQ-md.WaveQ end [Qty]
    ,cast(case when md.WaveQ + md.ProgQ = 0 then '3 - Scale Inv' else '4 - Waved Inv' end as varchar(20))[Status]
    ,md.FirstDate[LastDate]
    ,cast(coalesce(r.Receipt_ID,'no rct') as varchar(20))[Notes1]
    ,cast(coalesce(r.SHIP_FROM,p.SHIP_FROM) as varchar(20))[Notes2]
    ,coalesce(r.Receipt_Type,p.Receipt_Type)[Notes3]
into #PipelineInv
from #PoolCheck md
    outer apply( --find the receipt with the most recent create date (aka Receipt_Date) before the inventory's "received date"
        select top 1 rc.RECEIPT_ID,rc.SHIP_FROM,rc.ITEM_CATEGORY3,rc.RECEIPT_TYPE
            -- ,datediff(HH,md.FirstDate,coalesce(rc.CLOSE_DATE,rc.DATE_TIME_STAMP))/24.0[DaysDiff]
            ,datediff(HH,md.FirstDate,rc.RECEIPT_DATE)/24.0[DaysDiff]
        from rcts rc
        where md.ITEM = rc.ITEM --and rc.CLOSE_DATE is not null
        -- order by abs(datediff(HH,md.FirstDate,coalesce(rc.CLOSE_DATE,rc.DATE_TIME_STAMP)))
        order by abs(datediff(HH,md.FirstDate,rc.RECEIPT_DATE))
    )r
    outer apply( --find the PO with the most recent create date before the inventory's "received date", in case no receipts exist
        select top 1 po.PURCHASE_ORDER_ID,po.SHIP_FROM,po.ITEM_CATEGORY3,po.RECEIPT_TYPE
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
    ,ph.Receipt_Type[Notes3]
from ils..PURCHASE_ORDER_HEADER ph with(nolock)
    inner join ils..PURCHASE_ORDER_DETAIL pd with(nolock) on ph.PURCHASE_ORDER_ID = pd.PURCHASE_ORDER_ID 
	-- TODO: Make sure PO hasn't been deleted from Dips. Because that happens. And Scale doesn't get updated! :D Also, don't accidentally drop HPR% POs.
	-- inner join ReportsView..vw_PurchaseOrders po with(nolock) on right(ph.PURCHASE_ORDER_ID,6) collate database_default = po.PONumber 
    --     and right('00000000000000000000' + pd.Item,20) collate database_default = po.ItemCode
where pd.PURCHASE_ORDER_ID not in (select substring(RECEIPT_ID,0,LEN(RECEIPT_ID)-2) from ils..RECEIPT_DETAIL with(nolock)
                                   union select substring(RECEIPT_ID,0,LEN(RECEIPT_ID)-2) from ils..AR_RECEIPT_DETAIL with(nolock) )
    -- Only POs created in the last YEAR, if NO receipts have been created
    and ph.CREATED_DATE_TIME >= DATEADD(DD,-366,getdate()) 
    and pd.COMPANY in ('HPB','TTB') 
    -- janky avoidance of POs created to create item codes only
    and pd.TOTAL_QUANTITY > 1
group by pd.Item
    ,pd.ITEM_CATEGORY3
    ,ph.Receipt_Type 
    

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
    ,ph.Receipt_Type[Notes3]
from ils..PURCHASE_ORDER_HEADER ph  with(nolock)
    inner join ils..PURCHASE_ORDER_DETAIL pd with(nolock) on ph.PURCHASE_ORDER_ID = pd.PURCHASE_ORDER_ID 
where pd.COMPANY in ('HPB','TTB')
    -- janky avoidance of POs created to create item codes only
    and pd.TOTAL_QUANTITY > 1										
    and exists (select RECEIPT_ID from ils..RECEIPT_HEADER where pd.PURCHASE_ORDER_ID = substring(RECEIPT_ID,0,LEN(RECEIPT_ID)-2) 
                and coalesce(CLOSE_DATE,CREATION_DATE_TIME_STAMP) > DATEADD(DD,-180,getdate()) )	
    and not exists (select ITEM from ils..RECEIPT_DETAIL where ITEM=pd.ITEM and PURCHASE_ORDER_ID=pd.PURCHASE_ORDER_ID
                    union select ITEM from ils..AR_RECEIPT_DETAIL where ITEM=pd.ITEM and PURCHASE_ORDER_ID=pd.PURCHASE_ORDER_ID
                    union select ITEM from ar_ils..AR_RECEIPT_DETAIL where ITEM=pd.ITEM and PURCHASE_ORDER_ID=pd.PURCHASE_ORDER_ID )	
group by pd.Item
    ,pd.ITEM_CATEGORY3
    ,ph.Receipt_Type 
   

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
    ,rh.Receipt_Type[Notes3]
from ils..RECEIPT_HEADER rh with(nolock) 
    inner join ils..RECEIPT_DETAIL rd with(nolock) on rh.INTERNAL_RECEIPT_NUM=rd.INTERNAL_RECEIPT_NUM
where rd.TOTAL_QTY=rd.OPEN_QTY 
    and rh.CLOSE_DATE is null
    and rd.COMPANY in ('HPB','TTB')
    and not exists (select Item,Notes1 from #PipelineInv p where p.Status in ('3 - Scale Inv','4 - Waved Inv') and p.Item = rd.Item and p.Notes1 = rd.RECEIPT_ID)
group by rd.Item
    ,rd.ITEM_CATEGORY3
    ,rh.Receipt_Type


---- Scale inv without a receipt was adjusted into inventory, instead of being received into inventory. 
-- This happens either because folks wanted an item under a different company, like with a bunch of product from April 2020;
-- or because we don't have an actual item code for the product, like what happens with "straggler" product sent to us that wasn't on the PO. 
-- It's cheaper for us process it instead of trying to send it back. Mostly.
-- Since there's no reliably consistent/systematic way (at least that anyone uses) to cancel a PO, nor to create items withOUT a PO, 
-- we're left with a bunch of "junk" POs in the system we're never going to see inventory from.
-- This is another step in trying to filter out some of that stuff, for when the item code conventiently doesn't change. 
-- The "pd.TOTAL_QUANTITY > 1" criteria when adding to the #PipelineInv table was another step to catch "used only to create items" POs.
-- There's another step below that looks for matching ISBN's or Titles on #PipelineInv lines, along with specific statuses.
--    drop table #unduped
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
    ,pl.Notes3
    -- ,count(*) over(partition by pl.Item)[NumStss]
into #unduped
from #PipelineInv pl
    inner join ils..item it on pl.item = it.item
    left join adjs aj on pl.ITEM = aj.item 
where aj.Notes1 is null or aj.Notes1 = pl.Notes1
-- To see what's excluded...
-- where aj.Notes1 is not null and isnull(aj.Notes1,'') <> pl.Notes1


select * 
    ,left(u.Status,1)[StatusID]
from #unduped u 




/* -- temp table cleanup----------------

drop table #unduped
drop table #PipelineInv
drop table #PoolCheck

*/