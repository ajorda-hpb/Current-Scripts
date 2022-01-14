




drop table if exists #IsTiSums
;with IsTiSums as(
    select LocNo
        ,minDt,Yr,Wk
        ,EAN[ISBN-UPC]
        -- ,count(distinct pm.UserChar30)[nCats]
        -- ,max(pm.UserChar30)[max30]
        ,max(pm.Title)[Title]
        -- ,count(distinct fe.ItemCode)[NumItemCodes]
        ,sum(stSoldQty)[CurSldQty]
        ,sum(mdStSoldQty)[CurMdQty]
        ,sum(StRfndQty)[CurRtnQty]
    from ReportsView..ShpSld_fEAN fe with(Nolock)
        inner join ReportsData..ProductMaster pm with(nolock)
            on fe.ItemCode = pm.ItemCode
    where Src = 'BS' 
        -- and pm.UserChar30 <> ' F '
    group by LocNo
        ,minDt,Yr,Wk
        ,EAN
)
select it.*
    ,sum(CurSldQty) over(partition by LocNo,[ISBN-UPC] order by minDt rows unbounded preceding)[TotSldQty]
    ,sum(CurMdQty) over(partition by LocNo,[ISBN-UPC] order by minDt rows unbounded preceding)[TotMdQty]
    ,sum(CurRtnQty) over(partition by LocNo,[ISBN-UPC] order by minDt rows unbounded preceding)[TotRtnQty]
    -- ,min(case when CurSldQty+CurRtnQty > 0 then minDt end) over(partition by LocNo,[ISBN-UPC] order by minDt rows unbounded preceding)[MinSldWk]
    -- ,row_number() over(partition by LocNo,[ISBN-UPC] order by minDt desc rows unbounded preceding)[DescN]
into #IsTiSums
from IsTiSums it 

select *
from #IsTiSums
where minDt >= '2020-05-03' 
    and CurSldQty + CurRtnQty > 0
    -- and LocNo = '00001'
order by LocNo,minDt,CurSldQty desc,Title





-- Old Scratch----------------------------------
/*
declare @thisWk date = '10/4/20'
select LocNo
    ,@thisWk[CurWk]
    ,EAN
	,pm.Title
	,sum(case when minDt = @thisWk then stSoldQty else 0 end)[CurSldQty]
	,sum(case when minDt = @thisWk then mdStSoldQty else 0 end)[CurMdSoldQty]
	,sum(stSoldQty)[TotSldQty]
	,sum(mdStSoldQty)[TotMdSoldQty]
    ,max(case when StSoldQty+StRfndQty > 0 then minDt end)[LastSldWk]
from ReportsView..ShpSld_fEAN fe with(Nolock)
	inner join ReportsData..ProductMaster pm with(nolock)
		on fe.ItemCode = pm.ItemCode
where Src = 'BS'
    and minDt < '10/11/20'
group by LocNo
    ,EAN
	,pm.Title
-- having sum(case when minDt = @thisWk then stSoldQty else 0 end) <> 0
having sum(stSoldQty) > 0



drop table if exists #rItWkLocTots
select LocNo
    ,minDt
    ,Yr
    ,Wk
    ,EAN
    ,pm.Title
    ,stSoldQty[CurSldQty]
    ,mdStSoldQty[CurMdQty]
    ,StRfndQty[CurRtnQty]
    ,sum(stSoldQty) over(partition by LocNo,EAN,pm.Title order by minDt rows unbounded preceding)[TotSldQty]
    ,sum(mdStSoldQty) over(partition by LocNo,EAN,pm.Title order by minDt rows unbounded preceding)[TotMdQty]
    ,sum(StRfndQty) over(partition by LocNo,EAN,pm.Title order by minDt rows unbounded preceding)[TotRtnQty]
    ,max(case when StSoldQty+StRfndQty > 0 then minDt end) over(partition by LocNo,EAN,pm.Title order by minDt rows unbounded preceding)[LastSldWk]
into #rItWkLocTots 
from ReportsView..ShpSld_fEAN fe with(Nolock)
    inner join ReportsData..ProductMaster pm with(nolock)
        on fe.ItemCode = pm.ItemCode
where Src = 'BS'

select *
from #rItWkLocTots
where Yr >= 2020
    and Wk between 19 and 42
    and CurSldQty + CurRtnQty + TotSldQty + TotRtnQty > 0
    and LocNo = '00001'
order by LocNo,minDt,CurSldQty desc,Title


select EAN,count(distinct fe.ItemCode)[NumIts] 
    ,count(distinct pm.UserChar30)[Num30s]
    ,max(pm.UserChar30)[max30]
from ReportsView..ShpSld_fEAN fe with(Nolock)
        inner join ReportsData..ProductMaster pm with(nolock)
            on fe.ItemCode = pm.ItemCode
group by EAN
order by NumIts desc




select Locn,EAN
    ,min(case when stSoldQty+StRfndQty > 0 then minDt end)[MinSldWk]
from ReportsView..ShpSld_fEAN fe with(Nolock)
where EAN = '9781250118875'
    and LocNo = '00001'
    and minDt <= '2020-05-03'





select top 1000*
from ReportsView..ShpSld_InvShSc
where RordGrp = 'BS'

drop table if exists #WkLocInvQs
select LocNo,minDt,Yr,Wk
    ,sum(UnqIts)[InvIts]
    ,sum(EndInvQty)[InvQty]
    ,sum(i.TotCost)[InvCost]
into #WkLocInvQs
from ReportsView..ShpSld_InvShSc i
where RordGrp = 'BS'
group by LocNo,minDt,Yr,Wk




-- Store Weekly Totals incl same week last year
select c.LocNo
    ,c.minDt,c.Yr,c.Wk
    ,i.InvIts,i.InvQty
    ,c.NumISBNs,c.NumIts
    ,c.ShpQty,c.RcvQty
    ,c.SldQty,c.MdQty,c.RtnQty
    ,isnull(p.NumISBNs,0)[LyNumISBNs]
    ,isnull(p.NumIts,0)[LyNumIts]
    ,isnull(p.ShpQty,0)[LyShpQty]
    ,isnull(p.RcvQty,0)[LyRcvQty]
    ,isnull(p.SldQty,0)[LySldQty]
    ,isnull(p.MdQty,0)[LyMdQty]
    ,isnull(p.RtnQty,0)[LyRtnQty]
from #WkLocTots c 
    left join #WkLocTots p on c.LocNo = p.LocNo and c.Wk = p.Wk and c.Yr = p.Yr+1
    left join #WkLocInvQs i on c.LocNo = i.LocNo and c.Wk = i.Wk+1 and c.yr = i.Yr
where c.minDt >= '5/31/2020'
order by c.LocNo
    ,c.minDt










select isbn,*
from ReportsView..vw_DistributionProductMaster pm with(nolock)
where title like 'Testaments (Atwood)%'

select *
from ReportsView..ShpSld_fEAN fe with(Nolock)
where ean = '9780525562627'
    and minDt = '10/4/20'
order by minDt

select *
from ReportsView..ShpSld_fEAN fe with(Nolock)
where ean = '9780385543781'
    and minDt = '10/4/20'
order by minDt


select shh.EndDate,l.LocationNo,sih.*
from HPB_SALES..SIH2020 sih with(nolock)
    inner join HPB_SALES..SHH2020 shh with(nolock)
        on sih.SalesXactionId = shh.SalesXactionId and sih.LocationID = shh.LocationID 
    inner join ReportsData..locations l with(nolock) on sih.LocationID = l.LocationID
where ItemCode in ('00000000000010242519','00000000000010239660','00000000000010250794','00000000000010250063','00000000000001910214')
    and sih.BusinessDate >= '10/4/2020'
    and sih.BusinessDate < '10/11/2020'
order by shh.EndDate

select l.locationNo,l.*
from ReportsData..locations l with(nolock)
order by l.LocationNo


select *
from ReportsView..ShpSld_fEAN fe with(Nolock)
where ean = '9780689815812'
    and minDt = '10/4/20'







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


select pm.ItemCode
    ,pm.ISBN
    ,pm.UPC
    ,coalesce(nullif(pm.ISBN,''),nullif(substring(pm.UPC,1,13),''))[EAN]
	,case when pm.ProductType in ('HBF ','PBF ','TRF ') then 'BS' else 'Frln' end[Src]
	,case when pm.VendorID in ('IDB&TDISTR','IDINGRAMDI') then 'Rord' else 'Init' end[Prog]
into #fEAN_items
from ReportsView..vw_DistributionProductMaster pm with(nolock)
    left join #excludes ex on pm.ItemCode = ex.ItemCode
where pm.ProductType in ('BDGF','CALF','HBF ','LPF ','NBAF','NBJF','PBF ','TOYF','TRF ','VGF ')
    and ltrim(rtrim(pm.UserChar30)) = 'F'
    and ex.ItemCode is null

*/


