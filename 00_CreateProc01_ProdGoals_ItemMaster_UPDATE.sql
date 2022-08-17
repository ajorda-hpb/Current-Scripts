SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[ProdGoals_ItemMaster_UPDATE]
as
SET XACT_ABORT, NOCOUNT ON;
----build list of Rord vendors
drop table if exists #vendors
select ltrim(rtrim(vm.VendorID))[VendorID]
	,(case when (vm.UserChar30 = 'TTBReorder' or vm.VendorID = 'IDTEXASBOO')then 'TRO' else 'HRO' end)[RordGrp]
into #vendors
from ReportsData..VendorMaster vm with(nolock)
where ltrim(rtrim(vm.VendorID)) in (
		--Currently Active TTB Vendors
		'TEXASBKMNA','TEXASBKMNB','TEXASBKNON','TEXASSTATI','TEXASBKPUZ','TEXASBKUPC'
		--Retired HPB Reorder Vendors
		--,'IDPARRAGON','IDPARRAGOA','IDPARRAGOB','ID2020VISI','IDHOORAYFO'
		--Currently Active HPB Reorder Vendors
		,'IDAURORA','IDBENDONPU','IDBKSALESI','IDBOOKDEPO','IDBRYBELLY','IDCRAZART','IDCROWNB&C','IDCROWNPOI','IDCUDDLEBA','IDC&DVISIO'
		,'IDEUROGRA','IDFOUNDIMG','IDIGLOOBOO','IDKALANLPT','IDKIKKERLA','IDLBMAYASS','IDMELISSA&','IDMODERNPU','IDNOSTIMAG','IDOUTOFPRI'
		,'IDPEEPERS','IDSALESCOR','IDTOYSMITH','IDUNEMPLOY','IDUSPLAYIN','IDWISHPETS','IFDISCONFO','IFPROPERRE')
insert into #vendors
values ('CDC','CDC'), ('BS-i','BS'), ('BS-r','BS'),('Inac','HRO')

----all TTB vendors that've ever existed
drop table if exists #TTBVendors
select ltrim(rtrim(vm.VendorID))[VendorID]
into #TTBVendors
from ReportsData..VendorMaster vm with(nolock)
where ltrim(rtrim(vm.VendorID)) in ('TEXASBKMNA','TEXASBKMNB','IDTEXASBOO','IDTXBKAUDI'
	,'IDTXBKSOFT','IDTXBKSTAP','IDTXBMARKD','TEXASBKNON','TEXASSTATI','TEXASBKPUZ','TEXASBKUPC')


----List of DIPS itemCode excludes
drop table if exists #excludes
select pm.ItemCode
into #excludes
from ReportsView..vw_DistributionProductMaster pm with(nolock)
    inner join ReportsData..ProductTypes pt on pm.ProductType = pt.ProductType
where (pm.ItemCode in ('00000000000010058656','00000000000010058657','00000000000010058658'  --Misc Used not in the BaseInv table (MediaPlayer,Tablet,Phone)
					  ,'00000000000010017201','00000000000010017202','00000000000010041275'  --More Used  (Boardgames,Puzzles,Electronics)
					  ,'00000000000010017203','00000000000010017200','00000000000010041274'	 --& more Used (GameSystem,Textbooks,eReaders)
					  ,'00000000000010051490','00000000000010196953','00000000000010200047'  --Sticker King & Bag Charges
					  ,'00000000000010205940','00000000000010205941','00000000000010205942'  --Recently-created BBY Item Codes
					  ,'00000000000010205943','00000000000010211475','00000000000010211476'  --Last BBY code & wtf more used media codes
					  ,'00000000000010200074','00000000000010200073','00000000000010200072'  --omfg more used codes not in BaseInv WHYYYYY
					  ,'00000000000010200071','00000000000010199947','00000000000010199946'
					  ,'00000000000010199945','00000000000010199944','00000000000010199943'
					  ,'00000000000010199942','00000000000010199941','00000000000010199940'
					  ,'00000000000010199939','00000000000010199938','00000000000010044333','00000000000010044334')  
		or pm.ItemCode in (select distinct ItemCode from ReportsData..BaseInventory with(nolock))
		or pm.ProductType in ('HPBP', 'PRMO','CHA ','PGC ','EGC ')
		or pm.UserChar15 = 'SUP'
        or (pt.PTypeClass <> 'NEW' and pm.VendorID = 'IDCDCSPECU') -- covers a bunch of BBYs
		or pm.PurchaseFromVendorID = 'WHPBSUPPLY')
	--Tote bags are the bane of my existence
	and ltrim(rtrim(pm.PurchaseFromVendorID)) <> 'IDTXBKSTAP' 
	and ltrim(rtrim(pm.VendorID)) <> 'IDTXBKSTAP'


-------------------------------------------------------------------------
----List of ALL DIPS item codes, minus the ones we don't care about
drop table if exists #allitems_prep
select case when (rtrim(ltrim(pm.ReportItemCode))= '' or pm.ReportItemCode is null) then pm.itemcode else pm.ReportItemCode end[ItemCode]
	,pm.itemcode [ItemOrUPC]
into #allitems_prep
from ReportsView..vw_DistributionProductMaster pm with(nolock) 
where pm.ItemCode not in (select distinct ItemCode from #excludes)

----Correcting un-updated old UPC ReportItemCode's....
--these UPC originally point to an item code which has a different ReportItemCode
drop table if exists #allitems
select ap2.ItemCode,ap1.ItemOrUPC
into #allitems
from #allitems_prep ap1 
	inner join #allitems_prep ap2 on ap1.ItemCode = ap2.itemOrUPC
drop table #allitems_prep

----Adding VendorID info to it.ItemCodes for centralizing Vendor categorization in one spot
drop table if exists #allitems_vndrs_prep
select it.*
	,(case --when ltrim(rtrim(pm.PurchaseFromVendorID)) in (select distinct VendorID from #TTBvendors) then isnull(ltrim(rtrim(pm.PurchaseFromVendorID))) --Old method
		   when pm.UserChar15 = 'TTB' then case when ltrim(rtrim(pm.PurchaseFromVendorID)) in ('TEXASBKMNA','TEXASBKMNB','TEXASBKNON','TEXASSTATI','TEXASBKPUZ','TEXASBKUPC') 
												then ltrim(rtrim(pm.PurchaseFromVendorID)) else coalesce(sv.TTBVendor,'TEXASBKMNA') end --TRO's
		   when ltrim(rtrim(pm.PurchaseFromVendorID)) in (select distinct VendorID from #vendors where RordGrp = 'HRO') then ltrim(rtrim(pm.PurchaseFromVendorID)) --HRO's that were turned on
		   --when ltrim(rtrim(pm.VendorID)) in (select distinct VendorID from #vendors where RordGrp = 'HRO') then ltrim(rtrim(pm.VendorID)) --HRO's that were NEVER turned on
		   when ltrim(rtrim(pm.ProductType)) in ('HBF','TRF','PBF') and ltrim(rtrim(pm.VendorID)) in ('IDB&TDISTR','IDINGRAMDI') then 'BS-r'  --B&T & Ingram BS's
		   when ltrim(rtrim(pm.ProductType)) in ('HBF','TRF','PBF') then 'BS-i'   --publisher BS's
		   when 'Y' in (pm.Reorderable,pm.ReorderableItem) and pm.PurchaseFromVendorID <> 'IDCDCSPECU' then 'Inac' -- retired, no longer tracked HRO items, except if vendor is IDCDCSPECU, ie "reorderable" CDC.
		   else 'CDC' end)[VendorID]
into #allitems_vndrs_prep
from #allitems it
	inner join ReportsView..vw_DistributionProductMaster pm with(nolock) on it.ItemCode = pm.ItemCode
	left outer join ReportsView..ShpSld_SbjScnCapMap sv with(nolock) on ltrim(rtrim(pm.SectionCode)) = sv.Section
drop table #allitems

--Add RordGrp to the list of all item codes
--USE THIS to recreate ProductMaster entirely.!
drop table if exists #allitems_vndrs
select avp.*
	,vr.RordGrp
into #allitems_vndrs
from #allitems_vndrs_prep avp
	left outer join #vendors vr
		on avp.VendorID = vr.VendorID
create index ix_aiv_ItemOrUPC on #allitems_vndrs (ItemOrUPC)
drop table #allitems_vndrs_prep


--Ok srsly, prepping data for upserting ProdGoals_ItemMaster...
--Just items that would be new...
drop table if exists #newits
select ai.ItemOrUPC[ItemCode]
	,ai.ItemCode[Item]
	,ai.VendorID[ngqVendor]
	,ai.RordGrp
into #newits
from #allitems_vndrs ai
	left join ReportsView..ProdGoals_ItemMaster im
		on ai.ItemOrUPC = im.ItemCode
where isnumeric(ai.ItemOrUPC) = 1
	and im.ItemCode is null


--Just items being updated...
drop table if exists #updateits
select ai.ItemOrUPC[ItemCode]
	,ai.ItemCode[Item]
	,ai.VendorID[ngqVendor]
	,ai.RordGrp
into #updateits
from #allitems_vndrs ai
	inner join ReportsView..ProdGoals_ItemMaster im
		on ai.ItemOrUPC = im.ItemCode
where isnumeric(ai.ItemOrUPC) = 1
	and ai.VendorID <> im.NGQVendor



----Transaction 1--------------------------------
--Add new items to NGQ_ItemMaster----------------[
-----------------------------------------------[
BEGIN TRY
	begin transaction

	insert into ReportsView.dbo.ProdGoals_ItemMaster
	select ni.*
	from #newits ni

	commit transaction
END TRY
BEGIN CATCH
	if @@trancount > 0 rollback transaction
	declare @msg1 nvarchar(2048) = error_message()  
	raiserror (@msg1, 16, 1)
END CATCH
-----------------------------------------------]
------------------------------------------------]


----Transaction 2--------------------------------
--Update Existing Items via #updateIts-----------[
-----------------------------------------------[
BEGIN TRY
	begin transaction

	update im
	set NGQVendor = ui.ngqVendor
		,RordGrp = ui.RordGrp
	--    select *
	from ReportsView..ProdGoals_ItemMaster im
		inner join #updateits ui
			on im.ItemCode = ui.ItemCode
	where ui.ngqVendor <> im.ngqVendor

	commit transaction
END TRY
BEGIN CATCH
	if @@trancount > 0 rollback transaction
	declare @msg2 nvarchar(2048) = error_message()  
	raiserror (@msg2, 16, 1)
END CATCH
-----------------------------------------------]
------------------------------------------------]


----Transaction 3--------------------------------
--Delete Existing Items in #excludes-------------[
-----------------------------------------------[
BEGIN TRY
	begin transaction

	delete im
	from ReportsView..ProdGoals_ItemMaster im
		inner join #excludes e
			on im.ItemCode = e.ItemCode

	commit transaction
END TRY
BEGIN CATCH
	if @@trancount > 0 rollback transaction
	declare @msg3 nvarchar(2048) = error_message()  
	raiserror (@msg3, 16, 1)
END CATCH
-----------------------------------------------]
------------------------------------------------]

-- Cleanup-------------------------------------
drop table if exists #updateits
drop table if exists #newits
drop table if exists #allitems_vndrs
drop table if exists #allitems_vndrs_prep
drop table if exists #allitems
drop table if exists #allitems_prep
drop table if exists #excludes
drop table if exists #TTBVendors
drop table if exists #vendors

GO
