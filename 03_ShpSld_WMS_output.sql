----WMS Gadget query for pulling Cruise Control data
----replicated as a view by Joey, the VIEW has no restriction on Frontline items,
----which is why it's commented out here
------------------------------------------------------------------
----7/13/16 Edits for Q3 2016-------------------------------------
----Product Type tracking is OUT. All Section tracking is IN.
----The query's been refactored to reflect the change.
------------------------------------------------------------------
----10/13/16 New saved version for Q4 2016. No changes as of yet.
------------------------------------------------------------------
----10/20/16 Added Store totals count for current week to
----enable confirmation that all stores' shipments have closed.
------------------------------------------------------------------
----6/15/17(???) Reconfigured Section Detail tracking to...
----accomodate newly expanded tracked section list
----allow running weekly totals tracking similar to the old 'Cruise Control' Q4 tracking
----It's less about visualisations, more about simple numbers.
------------------------------------------------------------------
----8/11/17 Reordered output.
----1st, number of stores with closed shipments this week
----2nd, CapSecn ship totals by week for the section detail tab
----3rd, week rollup total for the overview tab
----4th, infreq. used store shipment totals by week
------------------------------------------------------------------
----5/12/18 Production Goals Reshuffled.
----Prod Goals now are only for NGQ-CDC product (Assortments, HPB Titles. NO TTB of any kind, No reorders.)
----A few quality of life changes (week and year designations for this current 7yr era)
------------------------------------------------------------------
----5/18/18 Output cleanup to match the streamlined ShpSld workbook-in-progress
------------------------------------------------------------------
----8/3/18 Added Complete breakdown of CDC Work to add context to Push Production tracking.
------------------------------------------------------------------
----8/24/18 Adjusted the weekly total production sums to properly exclude SNL product.
------------------------------------------------------------------
----4/2/19 Trimmed out a bunch of extraneous crap, leaving only the outputs used in ShpSld.
------------------------------------------------------------------
----5/26/20 Added separate category for TTB Retail sales (Whsl-Rtl), separate from 'Wholesale'
------------------------------------------------------------------
----10/29/20 Took out all but the weekly program rollups for ShpSldScale_src
------------------------------------------------------------------
----1/12/21 Moved scripts over to Sage to use wms_ils & DayCalendar to get rid of YrWk mastications.

--    select DATEADD(wk, DATEDIFF(wk,0,getdate()), -1)
----Set start & end dates
declare @sDate smalldatetime, @eDate smalldatetime
set @eDate = DATEADD(wk, DATEDIFF(wk,0,getdate()), -1)
set @sDate = DATEADD(wk, -26, @eDate)


----Comprehensive Breakdown of CDC Work-----
--------------------------------------------
--   declare @sDate smalldatetime set @sDate = '12/31/17' declare @eDate smalldatetime set @eDate = getdate()
--      drop table #stuff2
select dc.shpsld_year[Yr]
    ,dc.shpsld_week[Wk]
    ,isnull(ltrim(rtrim(gcs.User1Value)),'NON') [Cap]
    ,(case when isnull(gcs.User1Value,'NON') in ('A','B','SNL')  or item.item_category1 = 'KITS'
			then ltrim(rtrim(item.item_category1))
			else isnull(ltrim(rtrim(gcs.User1Value)),'NON') end)[GoalGrp]
	,gcs.User1Value+'-'+ltrim(rtrim(item.item_category1))[bnfg]
	--CDC Work Categorization-------------------
		  ----Basic Push Production
	,case when sd.order_type in ('ASSORTMENT','ASSORTMENTS','HPB Assortment','HPB Assortment by Ship','HPB Titles','HPB Titles2','TITLES') 
				and ltrim(rtrim(item.item_category1)) not in ('Blank','Booklight','Bookmark','Eyeglasses','Headphones','Metalsigns','Notecards','Puzzles') 
				and ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) not in ('HPBP','PRMO','SUP','HBF','PBF','TRF') 
				and isnull(gcs.User1Value,'NON') <> 'SNL'
				and sd.Customer = 'HPB' then 'Push'
		  --Seasonal/Misc Production (technically push but not factored into goals)
		  when sd.order_type in ('ASSORTMENT','ASSORTMENTS','HPB Assortment','HPB Assortment by Ship','HPB Titles','HPB Titles2','TITLES') 
				and (isnull(gcs.User1Value,'NON') = 'SNL' 
					or ltrim(rtrim(item.item_category1)) in ('Blank','Booklight','Bookmark','Eyeglasses','Headphones','Metalsigns','Notecards','Puzzles') 
					or ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) in ('HPBP','PRMO','SUP','HBF','PBF','TRF') )
				and sd.Customer = 'HPB' then 'Snl&MiscPush'
		  --TTB Push Production (technically push but not factored into goals)
		  when sd.order_type in ('TTB Initial') and sd.Company = 'TTB' and sd.Customer = 'HPB' then 'Init&Shorts' 
		  --TTB Pull Production (to Stores)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','WEBORDER BP','TTB Reorders','TTB Reorders BP') 
				and sd.Customer = 'HPB' then 'Pull-TTB' 
		  --Wholesale Retail Production (to HPB Customers)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','WEBORDER BP','TTB Reorders','TTB Reorders BP') 
				and sd.Customer = 'RETAIL' then 'Whsl-Rtl' 
		  --HPB Pull Production (to Stores)
		  when sd.order_type in ('HPB REORDERS') and sd.Company = 'HPB' and sd.Customer = 'HPB' then 'Pull-HPB'  
		  --Supplies Production
		  when (sd.order_type in ('SUPPLIES','Store Order') or sd.Company = 'SUP')
				and sd.Customer = 'HPB' then 'Supplies'
		  --Wholesale Production (not to stores)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','REPLENISHMENT','WEBORDER BP','TTB Reorders') 
				and sd.Customer <> 'HPB' then 'Wholesale'
		  else sd.Order_Type+ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) end[Dir]
       ,sum(sd.total_qty)[ShipQ]
	   ,sum(item.USER_DEF4*sd.TOTAL_QTY)[ShipC]

into #stuff2
from wms_ils..shipment_header sh WITH(NOLOCK) 
    inner join wms_ils..shipment_detail sd WITH(NOLOCK) 
        on sh.internal_shipment_num = sd.internal_shipment_num 
	inner join ReportsView..DayCalendar dc WITH(NOLOCK)
		on cast(sh.actual_ship_date_time as date) = dc.calendar_date
    inner join wms_ils..item WITH(NOLOCK) 
        on sd.item = item.item
    left outer join wms_ils..CDC_TTB_Items cti with(nolock)
        on sd.item = cti.ItemCode
    left outer join wms_ils..GENERIC_CONFIG_DETAIL gcs with(nolock)
        on gcs.Record_Type = 'Section_Codes'
            and ltrim(rtrim(item.Item_Category1)) = gcs.IDENTIFIER

where sh.actual_ship_date_time >= @sDate 
	and sh.actual_ship_date_time <= @eDate

group by dc.shpsld_year
    ,dc.shpsld_week
    ,isnull(ltrim(rtrim(gcs.User1Value)),'NON')
    ,(case when isnull(gcs.User1Value,'NON') in ('A','B','SNL')  or item.item_category1 = 'KITS'
			then ltrim(rtrim(item.item_category1))
			else isnull(ltrim(rtrim(gcs.User1Value)),'NON') end)
	,gcs.User1Value+'-'+ltrim(rtrim(item.item_category1))
	,case when sd.order_type in ('ASSORTMENT','ASSORTMENTS','HPB Assortment','HPB Assortment by Ship','HPB Titles','HPB Titles2','TITLES') 
				and ltrim(rtrim(item.item_category1)) not in ('Blank','Booklight','Bookmark','Eyeglasses','Headphones','Metalsigns','Notecards','Puzzles') 
				and ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) not in ('HPBP','PRMO','SUP','HBF','PBF','TRF') 
				and isnull(gcs.User1Value,'NON') <> 'SNL'
				and sd.Customer = 'HPB' then 'Push'
		  --Seasonal/Misc Production (technically push but not factored into goals)
		  when sd.order_type in ('ASSORTMENT','ASSORTMENTS','HPB Assortment','HPB Assortment by Ship','HPB Titles','HPB Titles2','TITLES') 
				and (isnull(gcs.User1Value,'NON') = 'SNL' 
					or ltrim(rtrim(item.item_category1)) in ('Blank','Booklight','Bookmark','Eyeglasses','Headphones','Metalsigns','Notecards','Puzzles') 
					or ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) in ('HPBP','PRMO','SUP','HBF','PBF','TRF') )
				and sd.Customer = 'HPB' then 'Snl&MiscPush'
		  --TTB Push Production (technically push but not factored into goals)
		  when sd.order_type in ('TTB Initial') and sd.Company = 'TTB' and sd.Customer = 'HPB' then 'Init&Shorts' 
		  --TTB Pull Production (to Stores)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','WEBORDER BP','TTB Reorders','TTB Reorders BP') 
				and sd.Customer = 'HPB' then 'Pull-TTB' 
		  --Wholesale Retail Production (to HPB Customers)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','WEBORDER BP','TTB Reorders','TTB Reorders BP') 
				and sd.Customer = 'RETAIL' then 'Whsl-Rtl' 
		  --HPB Pull Production (to Stores)
		  when sd.order_type in ('HPB REORDERS') and sd.Company = 'HPB' and sd.Customer = 'HPB' then 'Pull-HPB'  
		  --Supplies Production
		  when (sd.order_type in ('SUPPLIES','Store Order') or sd.Company = 'SUP')
				and sd.Customer = 'HPB' then 'Supplies'
		  --Wholesale Production (not to stores)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','REPLENISHMENT','WEBORDER BP','TTB Reorders') 
				and sd.Customer <> 'HPB' then 'Wholesale'
		  else sd.Order_Type+ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) end
order by Yr desc,Wk desc,Cap,GoalGrp


--Total ShipQty's by Week & Program--------
-------------------------------------------
select st.Yr,st.Wk,st.Dir
	,sum(st.ShipQ)[ShipQ]
	-- ,sum(st.ShipC)[ShipC]
from #stuff2 st
group by st.Yr,st.Wk,st.Dir
order by st.Yr,st.Wk,st.Dir



/*--Old Stuff-----------------------------------------------------

----base data for DynamicGoals --------
---------------------------------------
--    drop table #stuff
select (case when datepart(WEEK, sh.actual_ship_date_time) = 53 and datepart(YEAR, sh.actual_ship_date_time) >= 2017 then datepart(YEAR, sh.actual_ship_date_time)+1 
			 when datepart(WEEK, sh.actual_ship_date_time) = 1 and datepart(YEAR, sh.actual_ship_date_time) < 2017 then datepart(YEAR, sh.actual_ship_date_time)-1 
			 else datepart(YEAR, sh.actual_ship_date_time) end)[Yr]
       ,(case when datepart(WEEK, sh.actual_ship_date_time) = 53 and datepart(YEAR, sh.actual_ship_date_time) >= 2017 then 1 
			 when datepart(WEEK, sh.actual_ship_date_time) = 1 and datepart(YEAR, sh.actual_ship_date_time) < 2017 then 52 
			 else datepart(WEEK, sh.actual_ship_date_time) - case when datepart(YEAR, sh.actual_ship_date_time) < 2017 then 1 else 0 end end)[Wk]
       ,isnull(ltrim(rtrim(gcs.User1Value)),'NON') [Cap]
       ,(case when isnull(gcs.User1Value,'NON') in ('A','B','SNL') or item.item_category1 = 'KITS'
			then ltrim(rtrim(item.item_category1))
            else isnull(ltrim(rtrim(gcs.User1Value)),'NON') end)[GoalGrp]
		,count(distinct sd.customer)[NumCusts]
       ,sum(sd.total_qty)[ShipQ]

into #stuff
from shipment_header sh WITH(NOLOCK) 
       inner join shipment_detail sd WITH(NOLOCK) 
              on sh.internal_shipment_num = sd.internal_shipment_num 
       inner join item WITH(NOLOCK) 
              on sd.item = item.item
       left outer join CDC_TTB_Items cti with(nolock)
              on sd.item = cti.ItemCode
       left outer join GENERIC_CONFIG_DETAIL gcs with(nolock)
              on gcs.Record_Type = 'Section_Codes'
                     and ltrim(rtrim(item.Item_Category1)) = gcs.IDENTIFIER

where sd.order_type in ('ASSORTMENT','ASSORTMENTS','HPB Assortment','HPB Assortment by Ship','HPB Titles','HPB Titles2','TITLES')
       and sh.actual_ship_date_time >= @sDate 
	   and sh.actual_ship_date_time <= getdate()
       and ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) not in ('HPBP','PRMO','SUP','HBF','PBF','TRF')
	   and sd.Company = 'HPB'
		--ignore pull sections
       and ltrim(rtrim(item.item_category1)) not in ('Blank','Booklight','Bookmark','Eyeglasses','Headphones','Metalsigns','Notecards','Puzzles')

group by (case when datepart(WEEK, sh.actual_ship_date_time) = 53 and datepart(YEAR, sh.actual_ship_date_time) >= 2017 then datepart(YEAR, sh.actual_ship_date_time)+1 
			 when datepart(WEEK, sh.actual_ship_date_time) = 1 and datepart(YEAR, sh.actual_ship_date_time) < 2017 then datepart(YEAR, sh.actual_ship_date_time)-1 
			 else datepart(YEAR, sh.actual_ship_date_time) end)
       ,(case when datepart(WEEK, sh.actual_ship_date_time) = 53 and datepart(YEAR, sh.actual_ship_date_time) >= 2017 then 1 
			 when datepart(WEEK, sh.actual_ship_date_time) = 1 and datepart(YEAR, sh.actual_ship_date_time) < 2017 then 52 
			 else datepart(WEEK, sh.actual_ship_date_time) - case when datepart(YEAR, sh.actual_ship_date_time) < 2017 then 1 else 0 end end)
       ,isnull(ltrim(rtrim(gcs.User1Value)),'NON')
       ,(case when isnull(gcs.User1Value,'NON') in ('A','B','SNL') or item.item_category1 = 'KITS'
			then ltrim(rtrim(item.item_category1))
            else isnull(ltrim(rtrim(gcs.User1Value)),'NON') end)
order by Yr desc,Wk desc,Cap,GoalGrp

--Details for DynamicGoals tab---------
---------------------------------------
select *
	--Week is determined by the week the shipments close.
	--E.g. week n's product starts going into the FPAs in week n-1
	--Odd week are A weeks; Even weeks are B weeks
	,case when Wk%2 = 1 then 'A' else 'B' end[WkCap]
	,case when Cap in ('NON','SNL',case when Wk%2 = 1 then 'A' else 'B' end) then Wk 
		else (case when Wk = 1 then 52 else Wk-1 end) end[CapWk]
from #stuff
order by Yr,Wk,Cap,GoalGrp


-- Wholesale Focus...


----Comprehensive Breakdown of CDC Work-----
--------------------------------------------
--   declare @sDate smalldatetime set @sDate = '12/31/17' declare @eDate smalldatetime set @eDate = getdate()
--      drop table #stuff2
select (case when datepart(WEEK, sh.actual_ship_date_time) = 53 and datepart(YEAR, sh.actual_ship_date_time) >= 2017 then datepart(YEAR, sh.actual_ship_date_time)+1 
			when datepart(WEEK, sh.actual_ship_date_time) = 1 and datepart(YEAR, sh.actual_ship_date_time) < 2017 then datepart(YEAR, sh.actual_ship_date_time)-1 
			else datepart(YEAR, sh.actual_ship_date_time) end)[Yr]
    ,(case when datepart(WEEK, sh.actual_ship_date_time) = 53 and datepart(YEAR, sh.actual_ship_date_time) >= 2017 then 1 
			when datepart(WEEK, sh.actual_ship_date_time) = 1 and datepart(YEAR, sh.actual_ship_date_time) < 2017 then 52 
			else datepart(WEEK, sh.actual_ship_date_time) - case when datepart(YEAR, sh.actual_ship_date_time) < 2017 then 1 else 0 end end)[Wk]
	--CDC Work Categorization-------------------
		  ----Basic Push Production
	,case when sd.order_type in ('ASSORTMENT','ASSORTMENTS','HPB Assortment','HPB Assortment by Ship','HPB Titles','HPB Titles2','TITLES') 
				and ltrim(rtrim(item.item_category1)) not in ('Blank','Booklight','Bookmark','Eyeglasses','Headphones','Metalsigns','Notecards','Puzzles') 
				and ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) not in ('HPBP','PRMO','SUP','HBF','PBF','TRF') 
				and isnull(gcs.User1Value,'NON') <> 'SNL'
				and sd.Customer = 'HPB' then 'Push'
		  --Seasonal/Misc Production (technically push but not factored into goals)
		  when sd.order_type in ('ASSORTMENT','ASSORTMENTS','HPB Assortment','HPB Assortment by Ship','HPB Titles','HPB Titles2','TITLES') 
				and (isnull(gcs.User1Value,'NON') = 'SNL' 
					or ltrim(rtrim(item.item_category1)) in ('Blank','Booklight','Bookmark','Eyeglasses','Headphones','Metalsigns','Notecards','Puzzles') 
					or ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) in ('HPBP','PRMO','SUP','HBF','PBF','TRF') )
				and sd.Customer = 'HPB' then 'Snl&MiscPush'
		  --TTB Push Production (technically push but not factored into goals)
		  when sd.order_type in ('TTB Initial') and sd.Company = 'TTB' and sd.Customer = 'HPB' then 'Init&Shorts' 
		  --TTB Pull Production (to Stores)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','WEBORDER BP','TTB Reorders','TTB Reorders BP') 
				and sd.Customer = 'HPB' then 'Pull-TTB' 
		  --Wholesale Retail Production (to HPB Customers)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','WEBORDER BP','TTB Reorders','TTB Reorders BP') 
				and sd.Customer = 'RETAIL' then 'Whsl-Rtl' 
		  --HPB Pull Production (to Stores)
		  when sd.order_type in ('HPB REORDERS') and sd.Company = 'HPB' and sd.Customer = 'HPB' then 'Pull-HPB'  
		  --Supplies Production
		  when (sd.order_type in ('SUPPLIES','Store Order') or sd.Company = 'SUP')
				and sd.Customer = 'HPB' then 'Supplies'
		  --Wholesale Production (not to stores)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','REPLENISHMENT','WEBORDER BP','TTB Reorders') 
				and sd.Customer <> 'HPB' then 'Wholesale'
		  else sd.Order_Type+ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) end[Dir]
	,sh.CUSTOMER[Customer]
	,sh.SHIP_TO[ShpTo]
	,count(distinct sh.SHIPMENT_ID)[NumShpts]
    ,count(distinct sd.Item)[NumIts]
	,sum(sd.total_qty)[ShipQ]
	,sum(item.USER_DEF4*sd.TOTAL_QTY)[ShipC]

-- into #stuff3
from wms_ils..shipment_header sh WITH(NOLOCK) 
    inner join wms_ils..shipment_detail sd WITH(NOLOCK) 
            on sh.internal_shipment_num = sd.internal_shipment_num 
    inner join item WITH(NOLOCK) 
            on sd.item = item.item
    left outer join CDC_TTB_Items cti with(nolock)
            on sd.item = cti.ItemCode
    left outer join GENERIC_CONFIG_DETAIL gcs with(nolock)
            on gcs.Record_Type = 'Section_Codes'
                    and ltrim(rtrim(item.Item_Category1)) = gcs.IDENTIFIER

where sh.actual_ship_date_time >= @sDate 
	and sh.actual_ship_date_time <= @eDate
	and sh.CUSTOMER <> 'HPB'

group by (case when datepart(WEEK, sh.actual_ship_date_time) = 53 and datepart(YEAR, sh.actual_ship_date_time) >= 2017 then datepart(YEAR, sh.actual_ship_date_time)+1 
			when datepart(WEEK, sh.actual_ship_date_time) = 1 and datepart(YEAR, sh.actual_ship_date_time) < 2017 then datepart(YEAR, sh.actual_ship_date_time)-1 
			else datepart(YEAR, sh.actual_ship_date_time) end)
    ,(case when datepart(WEEK, sh.actual_ship_date_time) = 53 and datepart(YEAR, sh.actual_ship_date_time) >= 2017 then 1 
			when datepart(WEEK, sh.actual_ship_date_time) = 1 and datepart(YEAR, sh.actual_ship_date_time) < 2017 then 52 
			else datepart(WEEK, sh.actual_ship_date_time) - case when datepart(YEAR, sh.actual_ship_date_time) < 2017 then 1 else 0 end end)
    ,sh.CUSTOMER
	,sh.SHIP_TO
	,case when sd.order_type in ('ASSORTMENT','ASSORTMENTS','HPB Assortment','HPB Assortment by Ship','HPB Titles','HPB Titles2','TITLES') 
				and ltrim(rtrim(item.item_category1)) not in ('Blank','Booklight','Bookmark','Eyeglasses','Headphones','Metalsigns','Notecards','Puzzles') 
				and ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) not in ('HPBP','PRMO','SUP','HBF','PBF','TRF') 
				and isnull(gcs.User1Value,'NON') <> 'SNL'
				and sd.Customer = 'HPB' then 'Push'
		  --Seasonal/Misc Production (technically push but not factored into goals)
		  when sd.order_type in ('ASSORTMENT','ASSORTMENTS','HPB Assortment','HPB Assortment by Ship','HPB Titles','HPB Titles2','TITLES') 
				and (isnull(gcs.User1Value,'NON') = 'SNL' 
					or ltrim(rtrim(item.item_category1)) in ('Blank','Booklight','Bookmark','Eyeglasses','Headphones','Metalsigns','Notecards','Puzzles') 
					or ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) in ('HPBP','PRMO','SUP','HBF','PBF','TRF') )
				and sd.Customer = 'HPB' then 'Snl&MiscPush'
		  --TTB Push Production (technically push but not factored into goals)
		  when sd.order_type in ('TTB Initial') and sd.Company = 'TTB' and sd.Customer = 'HPB' then 'Init&Shorts' 
		  --TTB Pull Production (to Stores)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','WEBORDER BP','TTB Reorders','TTB Reorders BP') 
				and sd.Customer = 'HPB' then 'Pull-TTB' 
		  --Wholesale Retail Production (to HPB Customers)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','WEBORDER BP','TTB Reorders','TTB Reorders BP') 
				and sd.Customer = 'RETAIL' then 'Whsl-Rtl' 
		  --HPB Pull Production (to Stores)
		  when sd.order_type in ('HPB REORDERS') and sd.Company = 'HPB' and sd.Customer = 'HPB' then 'Pull-HPB'  
		  --Supplies Production
		  when (sd.order_type in ('SUPPLIES','Store Order') or sd.Company = 'SUP')
				and sd.Customer = 'HPB' then 'Supplies'
		  --Wholesale Production (not to stores)
		  when sd.order_type in ('TTB WHOLESALE','WEBORDER','TTB WHOLESALE BP','REPLENISHMENT','WEBORDER BP','TTB Reorders') 
				and sd.Customer <> 'HPB' then 'Wholesale'
		  else sd.Order_Type+ltrim(rtrim(isnull(cti.ProdType,item.Item_Category2))) end
order by Yr desc,Wk desc






----Older Stuff---------------------------------------------------

-- Finding the identifiers for Retail Sales direct from TTB-------
------------------------------------------------------------------
select sd.order_type
    ,sd.CUSTOMER
    ,sum(sd.total_qty)[ShipQ]
from wms_ils..shipment_header sh WITH(NOLOCK) 
    inner join wms_ils..shipment_detail sd WITH(NOLOCK) 
            on sh.internal_shipment_num = sd.internal_shipment_num 
where sh.actual_ship_date_time >= '3/1/20' 
	and sh.actual_ship_date_time <= '5/27/20'
group by sd.order_type
    ,sd.CUSTOMER
order by ShipQ


--Total ShipQty's by Week-------------------
--Only A/B/NON Caps count towards Push goals
--------------------------------------------
select st.Yr
	,st.Wk
	,sum(st.ShipQ)[ShipQ]
from #stuff st
where Cap <> 'SNL'
group by st.Yr
	,st.Wk
order by st.Yr,st.Wk desc



--Stuff shipped so far this week...
-----------------------------------
select sd.order_type,sum(sd.TOTAL_QTY)[ShipQty]
from shipment_header sh WITH(NOLOCK) 
    inner join shipment_detail sd WITH(NOLOCK) 
            on sh.internal_shipment_num = sd.internal_shipment_num  
where sh.actual_ship_date_time >= dateadd(DD,-4,getdate()) 
group by sd.order_type


--Sample join for obtaining wave information...
-----------------------------------------------
select ls.Launch_Name[WaveDesc]
	,ls.LAUNCH_FLOW[WaveType]
	,ls.INTERNAL_LAUNCH_NUM[WaveNo]
	,sd.order_type
	,min(sd.DATE_TIME_STAMP)[minShpDt]
	,max(sd.DATE_TIME_STAMP)[maxShpDt]
	,sum(sd.TOTAL_QTY)[ShipQty]
from shipment_header sh WITH(NOLOCK) 
    inner join shipment_detail sd WITH(NOLOCK) 
            on sh.internal_shipment_num = sd.internal_shipment_num  
	left join wms_ils..LAUNCH_STATISTICS ls with(nolock)
		on sh.LAUNCH_NUM = ls.INTERNAL_LAUNCH_NUM
where sh.actual_ship_date_time is null
	and sd.DATE_TIME_STAMP >= dateadd(DD,-4,getdate()) 
group by ls.Launch_Name
	,ls.LAUNCH_FLOW
	,ls.INTERNAL_LAUNCH_NUM
	,sd.order_type
order by Order_Type,WaveDesc

*/