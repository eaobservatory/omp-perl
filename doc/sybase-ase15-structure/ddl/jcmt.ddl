-- Sybase Adaptive Server Enterprise DDL Generator Utility/15.7/EBF 20728 ESD#3/S/1.6.0/ase157esd3/Fri Nov 16 09:14:00 PST 2012


-- Confidential property of Sybase, Inc.
-- Copyright 2001, 2007
-- Sybase, Inc.  All rights reserved.
-- Unpublished rights reserved under U.S. copyright laws.
-- This software contains confidential and trade secret information of Sybase,
-- Inc.   Use,  duplication or disclosure of the software and documentation by
-- the  U.S.  Government  is  subject  to  restrictions set forth in a license
-- agreement  between  the  Government  and  Sybase,  Inc.  or  other  written
-- agreement  specifying  the  Government's rights to use the software and any
-- applicable FAR provisions, for example, FAR 52.227-19.
-- Sybase, Inc. One Sybase Drive, Dublin, CA 94568, USA


-- DDLGen started with the following arguments
-- -S SYB_JAC -I /opt2/sybase/ase-15.0/interfaces -P*** -U sa -O ddl/jcmt.ddl -L jcmt.progress.2017-1206-0938 -T DB -N jcmt 
-- at 12/06/17 9:38:33 HST


USE master
go


PRINT "<<<< CREATE DATABASE jcmt>>>>"
go


IF EXISTS (SELECT 1 FROM master.dbo.sysdatabases
	   WHERE name = 'jcmt')
	DROP DATABASE jcmt
go


IF (@@error != 0)
BEGIN
	PRINT "Error dropping database 'jcmt'"
	SELECT syb_quit()
END
go


CREATE DATABASE jcmt
	    ON dev_jcmt_db_0 = '3072M' -- 1572864 pages
	LOG ON dev_jcmt_db_0 = '20450M' -- 10470400 pages
WITH OVERRIDE
   , DURABILITY = FULL
go


ALTER DATABASE jcmt
	    ON dev_jcmt_db_0 = '4394M' -- 2249728 pages
	LOG ON dev_jcmt_db_0 = '6M' -- 3072 pages
go


ALTER DATABASE jcmt
	    ON dev_jcmt_db_0 = '1478M' -- 756736 pages
	LOG ON dev_jcmt_db_0 = '9512M' -- 4870144 pages
	     , dev_jcmt_db_1 = '488M' -- 249856 pages
go


ALTER DATABASE jcmt
	    ON dev_jcmt_db_1 = '34328M' -- 17575936 pages
	LOG ON dev_jcmt_db_1 = '4096M' -- 2097152 pages
	     , dev_jcmt_log_0 = '5120M' -- 2621440 pages
	     , dev_jcmt_log_1 = '5120M' -- 2621440 pages
WITH OVERRIDE
go


use jcmt
go

exec sp_changedbowner 'sa', true 
go

checkpoint
go


-----------------------------------------------------------------------------
-- DDL for User 'datareader'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "datareader" >>>>>'
go 

exec sp_adduser 'datareader' ,'datareader' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for User 'jcmt'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "jcmt" >>>>>'
go 

exec sp_adduser 'jcmt' ,'jcmt' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for User 'russell'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "russell" >>>>>'
go 

exec sp_adduser 'russell' ,'russell' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for User 'staff'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "staff" >>>>>'
go 

exec sp_adduser 'staff' ,'staff' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.ACSIS'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.ACSIS" >>>>>'
go

use jcmt
go 

setuser 'dbo'
go 

create table ACSIS (
	obsid_subsysnr                  varchar(50)                      not null,
	obsid                           varchar(48)                      not null,
	max_subscan                     int                              not null,
	obsend                          int                                  null,
	molecule                        varchar(70)                          null,
	transiti                        varchar(70)                          null,
	tempscal                        varchar(70)                          null,
	drrecipe                        varchar(70)                          null,
	bwmode                          varchar(70)                          null,
	subsysnr                        int                                  null,
	subbands                        varchar(70)                          null,
	nsubband                        int                                  null,
	subrefp1                        int                                  null,
	subrefp2                        int                                  null,
	nchnsubs                        int                                  null,
	refchan                         int                                  null,
	ifchansp                        float(16)                            null,
	fft_win                         varchar(70)                          null,
	bedegfac                        float(16)                            null,
	msroot                          varchar(70)                          null,
	sb_mode                         varchar(70)                          null,
	iffreq                          float(16)                            null,
	n_mix                           int                                  null,
	obs_sb                          varchar(70)                          null,
	lofreqs                         float(16)                            null,
	lofreqe                         float(16)                            null,
	recptors                        varchar(70)                          null,
	refrecep                        varchar(70)                          null,
	medtsys                         float(16)                            null,
	doppler                         varchar(70)                          null,
	ssysobs                         varchar(16)                          null,
	skyrefx                         varchar(70)                          null,
	skyrefy                         varchar(70)                          null,
	num_nods                        int                                  null,
	ncalstep                        int                                  null,
	nrefstep                        int                                  null,
	stbetref                        int                                  null,
	stbetcal                        int                                  null,
	freq_sig_lower                  float(16)                            null,
	freq_sig_upper                  float(16)                            null,
	freq_img_lower                  float(16)                            null,
	freq_img_upper                  float(16)                            null,
	zsource                         float(16)                            null,
	restfreq                        float(16)                            null,
	nchannels                       int                                  null,
	ssyssrc                         varchar(16)                          null,
	medtrx                          float(16)                            null,
	specid                          tinyint                              null,
	asn_id                          varchar(32)                          null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.ACSIS to public Granted by dbo
go
Grant Insert on dbo.ACSIS to jcmt Granted by dbo
go
Grant Delete on dbo.ACSIS to jcmt Granted by dbo
go
Grant Update on dbo.ACSIS to jcmt Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_uc_ACSIS_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_uc_ACSIS_1" >>>>>'
go 

create unique clustered index idx_uc_ACSIS_1 
on jcmt.dbo.ACSIS(obsid_subsysnr)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_ACSIS_2'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_ACSIS_2" >>>>>'
go 

create nonclustered index idx_ACSIS_2 
on jcmt.dbo.ACSIS(obsid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'assoc_acsis_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "assoc_acsis_idx" >>>>>'
go 

create nonclustered index assoc_acsis_idx 
on jcmt.dbo.ACSIS(asn_id)
go 


-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.acsis_delete'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.acsis_delete" >>>>>'
go 

setuser 'dbo'
go 

create trigger acsis_delete
on ACSIS
for delete
as
    update COMMON set c.last_modified=dateadd( second, 30, getdate() )
    from COMMON c, deleted d
    where ( ( c.obsid = d.obsid )
        and ( datediff( second, getdate(), c.last_modified ) < 0 ) )

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.acsis_insert'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.acsis_insert" >>>>>'
go 

setuser 'dbo'
go 

create trigger acsis_insert
on ACSIS
for insert
as
    update COMMON set last_modified = dateadd( second, 30, getdate() )
    from COMMON c, inserted i
    where ( ( c.obsid = i.obsid )
         and ( datediff( second, getdate(), c.last_modified ) < 0 ) )

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.acsis_update'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.acsis_update" >>>>>'
go 

setuser 'dbo'
go 

create trigger acsis_update
on ACSIS
for update
as
    update COMMON set c.last_modified=dateadd( second, 30, getdate() )
    from COMMON c, deleted d
    where ( ( c.obsid = d.obsid )
        and ( datediff( second, getdate(), c.last_modified ) < 0 ) )

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.COMMON'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.COMMON" >>>>>'
go

setuser 'dbo'
go 

create table COMMON (
	obsid                           varchar(48)                      not null,
	telescop                        varchar(6)                           null,
	origin                          varchar(60)                          null,
	obsgeo_x                        float(16)                            null,
	obsgeo_y                        float(16)                            null,
	obsgeo_z                        float(16)                            null,
	alt_obs                         float(16)                            null,
	lat_obs                         float(16)                            null,
	long_obs                        float(16)                            null,
	etal                            float(16)                            null,
	project                         varchar(32)                          null,
	recipe                          varchar(70)                          null,
	drgroup                         int                                  null,
	msbid                           varchar(40)                      not null,
	survey                          varchar(10)                          null,
	rmtagent                        varchar(10)                          null,
	agentid                         varchar(70)                          null,
	object                          varchar(70)                          null,
	standard                        int                                  null,
	obsnum                          int                                  null,
	utdate                          int                                  null,
	date_obs                        datetime                         not null,
	date_end                        datetime                         not null,
	instap                          varchar(8)                           null,
	instap_x                        float(16)                            null,
	instap_y                        float(16)                            null,
	amstart                         float(16)                            null,
	amend                           float(16)                            null,
	azstart                         float(16)                            null,
	azend                           float(16)                            null,
	elstart                         float(16)                            null,
	elend                           float(16)                            null,
	hststart                        datetime                             null,
	hstend                          datetime                             null,
	lststart                        float(16)                            null,
	lstend                          float(16)                            null,
	int_time                        float(16)                            null,
	atstart                         float(16)                            null,
	atend                           float(16)                            null,
	humstart                        float(16)                            null,
	humend                          float(16)                            null,
	bpstart                         float(16)                            null,
	bpend                           float(16)                            null,
	wndspdst                        float(16)                            null,
	wndspden                        float(16)                            null,
	wnddirst                        float(16)                            null,
	wnddiren                        float(16)                            null,
	tau225st                        float(16)                            null,
	tau225en                        float(16)                            null,
	taudatst                        datetime                             null,
	taudaten                        datetime                             null,
	tausrc                          varchar(16)                          null,
	wvmtaust                        float(16)                            null,
	wvmtauen                        float(16)                            null,
	wvmdatst                        datetime                             null,
	wvmdaten                        datetime                             null,
	seeingst                        float(16)                            null,
	seeingen                        float(16)                            null,
	seedatst                        datetime                             null,
	seedaten                        datetime                             null,
	frlegtst                        float(16)                            null,
	frlegten                        float(16)                            null,
	bklegtst                        float(16)                            null,
	bklegten                        float(16)                            null,
	sam_mode                        varchar(8)                           null,
	sw_mode                         varchar(8)                           null,
	obs_type                        varchar(10)                          null,
	chop_crd                        varchar(12)                          null,
	chop_frq                        float(16)                            null,
	chop_pa                         float(16)                            null,
	chop_thr                        float(16)                            null,
	jigl_cnt                        int                                  null,
	jigl_nam                        varchar(70)                          null,
	jigl_pa                         float(16)                            null,
	jigl_crd                        varchar(12)                          null,
	map_hght                        float(16)                            null,
	map_pa                          float(16)                            null,
	map_wdth                        float(16)                            null,
	locl_crd                        varchar(12)                          null,
	map_x                           float(16)                            null,
	map_y                           float(16)                            null,
	scan_crd                        varchar(12)                          null,
	scan_vel                        float(16)                            null,
	scan_dy                         float(16)                            null,
	scan_pa                         float(16)                            null,
	scan_pat                        varchar(28)                          null,
	align_dx                        float(16)                            null,
	align_dy                        float(16)                            null,
	focus_dz                        float(16)                            null,
	daz                             float(16)                            null,
	del                             float(16)                            null,
	uaz                             float(16)                            null,
	uel                             float(16)                            null,
	steptime                        float(16)                            null,
	num_cyc                         int                                  null,
	jos_mult                        int                                  null,
	jos_min                         int                                  null,
	startidx                        int                                  null,
	focaxis                         char(1)                              null,
	nfocstep                        int                                  null,
	focstep                         float(16)                            null,
	ocscfg                          varchar(70)                          null,
	status                          varchar(8)                           null,
	pol_conn                        int                                  null,
	pol_mode                        varchar(9)                           null,
	rotafreq                        float(16)                            null,
	instrume                        varchar(8)                           null,
	backend                         varchar(8)                           null,
	release_date                    datetime                             null,
	last_modified                   datetime                             null,
	obsra                           float(16)                            null,
	obsdec                          float(16)                            null,
	obsratl                         float(16)                            null,
	obsrabl                         float(16)                            null,
	obsratr                         float(16)                            null,
	obsrabr                         float(16)                            null,
	obsdectl                        float(16)                            null,
	obsdecbl                        float(16)                            null,
	obsdectr                        float(16)                            null,
	obsdecbr                        float(16)                            null,
	dut1                            float(16)                            null,
	msbtid                          varchar(32)                          null,
	jig_scal                        float(16)                            null,
	inbeam                          varchar(64)                          null,
	inbeam_orig                     varchar(64)                          null,
	moving_target                   bit                             DEFAULT  0

  not null,
	last_caom_mod                   datetime                             null,
	req_mintau                      float(16)                            null,
	req_maxtau                      float(16)                            null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.COMMON to public Granted by dbo
go
Grant Insert on dbo.COMMON to jcmt Granted by dbo
go
Grant Delete on dbo.COMMON to jcmt Granted by dbo
go
Grant Update on dbo.COMMON to jcmt Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_uc_COMMON_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_uc_COMMON_1" >>>>>'
go 

create unique clustered index idx_uc_COMMON_1 
on jcmt.dbo.COMMON(obsid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_jcmt_COMMON_date_end'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_jcmt_COMMON_date_end" >>>>>'
go 

create unique nonclustered index idx_jcmt_COMMON_date_end 
on jcmt.dbo.COMMON(date_obs)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_jcmt_COMMON_date_obs'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_jcmt_COMMON_date_obs" >>>>>'
go 

create unique nonclustered index idx_jcmt_COMMON_date_obs 
on jcmt.dbo.COMMON(date_end)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_jcmt_COMMON_proj'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_jcmt_COMMON_proj" >>>>>'
go 

create nonclustered index idx_jcmt_COMMON_proj 
on jcmt.dbo.COMMON(project)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_jcmt_COMMON_inst'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_jcmt_COMMON_inst" >>>>>'
go 

create nonclustered index idx_jcmt_COMMON_inst 
on jcmt.dbo.COMMON(instrume)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'caom_mod_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "caom_mod_idx" >>>>>'
go 

create nonclustered index caom_mod_idx 
on jcmt.dbo.COMMON(last_caom_mod)
go 


-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.common_delete'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.common_delete" >>>>>'
go 

setuser 'dbo'
go 


create trigger common_delete
on COMMON
for delete
as
    update COMMON set c.last_modified=dateadd( second, 30, getdate() )
    from COMMON c, deleted d
    where ( ( c.obsid = d.obsid )
        and ( datediff( second, getdate(), c.last_modified ) < 0 ) )

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.common_insert'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.common_insert" >>>>>'
go 

setuser 'dbo'
go 


create trigger common_insert
on COMMON
for insert
as
    update COMMON set last_modified = dateadd( second, 30, getdate() )
    from COMMON c, inserted i
    where ( ( c.obsid = i.obsid )
         and ( datediff( second, getdate(), c.last_modified ) < 0 )
  )

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.common_update'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.common_update" >>>>>'
go 

setuser 'dbo'
go 


create trigger common_update
on COMMON
for update
as
    update COMMON set c.last_modified=dateadd( second, 30, getdate() )
    from COMMON c, deleted d
    where ( ( c.obsid = d.obsid )
        and ( datediff( second, getdate(), c.last_modified ) < 0 ) )

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.FILES'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.FILES" >>>>>'
go

setuser 'dbo'
go 

create table FILES (
	file_id                         varchar(70)                      not null,
	obsid                           varchar(48)                      not null,
	subsysnr                        int                              not null,
	nsubscan                        int                              not null,
	obsid_subsysnr                  varchar(50)                      not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.FILES to public Granted by dbo
go
Grant Insert on dbo.FILES to jcmt Granted by dbo
go
Grant Delete on dbo.FILES to jcmt Granted by dbo
go
Grant Update on dbo.FILES to jcmt Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'pri_FILES_obsidss_fileid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "pri_FILES_obsidss_fileid" >>>>>'
go 

create unique clustered index pri_FILES_obsidss_fileid 
on jcmt.dbo.FILES(obsid_subsysnr, file_id)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'obsid_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "obsid_idx" >>>>>'
go 

create nonclustered index obsid_idx 
on jcmt.dbo.FILES(obsid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'fileid_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "fileid_idx" >>>>>'
go 

create nonclustered index fileid_idx 
on jcmt.dbo.FILES(file_id)
go 


-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.files_delete'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.files_delete" >>>>>'
go 

setuser 'dbo'
go 


create trigger files_delete
on FILES
for delete
as
    update COMMON set c.last_modified=dateadd( second, 30, getdate() )
    from COMMON c, deleted d
    where ( ( c.obsid = d.obsid )
        and ( datediff( second, getdate(), c.last_modified ) < 0 ) )
 

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.files_insert'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.files_insert" >>>>>'
go 

setuser 'dbo'
go 

create trigger files_insert
on FILES
for insert
as
    update COMMON set last_modified = dateadd( second, 30, getdate() )
    from COMMON c, inserted i
    where ( ( c.obsid = i.obsid )
         and ( datediff( second, getdate(), c.last_modified ) < 0 ) )
                                                                                                                                                                                                                                                              

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.files_update'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.files_update" >>>>>'
go 

setuser 'dbo'
go 

create trigger files_update
on FILES
for update
as
    update COMMON set c.last_modified=dateadd( second, 30, getdate() )
    from COMMON c, deleted d
    where ( ( c.obsid = d.obsid )
        and ( datediff( second, getdate(), c.last_modified ) < 0 ) )
 

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.SCUBA2'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.SCUBA2" >>>>>'
go

setuser 'dbo'
go 

create table SCUBA2 (
	obsid_subsysnr                  varchar(50)                      not null,
	filter                          varchar(10)                      not null,
	subarray_a                      bit                             DEFAULT  0   
  not null,
	subarray_b                      bit                             DEFAULT  0   
  not null,
	subarray_c                      bit                             DEFAULT  0   
  not null,
	subarray_d                      bit                             DEFAULT  0   
  not null,
	arrayid_a                       varchar(32)                          null,
	arrayid_b                       varchar(32)                          null,
	arrayid_c                       varchar(32)                          null,
	arrayid_d                       varchar(32)                          null,
	max_subscan                     int                              not null,
	wavelen                         float(8)                         not null,
	shutter                         float(8)                         not null,
	bandwid                         float(8)                         not null,
	bbheat                          float(8)                         not null,
	basetemp                        float(8)                             null,
	pixheat_a                       int                                  null,
	pixheat_b                       int                                  null,
	pixheat_c                       int                                  null,
	pixheat_d                       int                                  null,
	bias_a                          int                                  null,
	bias_b                          int                                  null,
	bias_c                          int                                  null,
	bias_d                          int                                  null,
	flat_a                          varchar(32)                          null,
	flat_b                          varchar(32)                          null,
	flat_c                          varchar(32)                          null,
	flat_d                          varchar(32)                          null,
	obsid                           varchar(48)                     DEFAULT  '' 
  not null,
	asn_id                          varchar(6)                           null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.SCUBA2 to public Granted by dbo
go
Grant Insert on dbo.SCUBA2 to jcmt Granted by dbo
go
Grant Delete on dbo.SCUBA2 to jcmt Granted by dbo
go
Grant Update on dbo.SCUBA2 to jcmt Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'obsidss_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "obsidss_idx" >>>>>'
go 

create unique clustered index obsidss_idx 
on jcmt.dbo.SCUBA2(obsid_subsysnr)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'filter_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "filter_idx" >>>>>'
go 

create nonclustered index filter_idx 
on jcmt.dbo.SCUBA2(filter)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'obsid_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "obsid_idx" >>>>>'
go 

create nonclustered index obsid_idx 
on jcmt.dbo.SCUBA2(obsid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'assoc_scuba2_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "assoc_scuba2_idx" >>>>>'
go 

create nonclustered index assoc_scuba2_idx 
on jcmt.dbo.SCUBA2(asn_id)
go 


-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.scuba2_delete'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.scuba2_delete" >>>>>'
go 

setuser 'dbo'
go 

CREATE TRIGGER scuba2_delete
ON SCUBA2
FOR DELETE
AS
    UPDATE COMMON SET c.last_modified = dateadd( SECOND, 30, getdate() )
    FROM COMMON c, deleted d
    WHERE ( ( c.obsid = d.obsid )
        AND ( datediff( SECOND, getdate(), c.last_modified ) < 0 ) )


go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.scuba2_insert'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.scuba2_insert" >>>>>'
go 

setuser 'dbo'
go 

CREATE TRIGGER scuba2_insert
ON SCUBA2
FOR INSERT
AS
    UPDATE COMMON SET last_modified = dateadd( SECOND, 30, getdate() )
    FROM COMMON c, inserted i
    WHERE ( ( c.obsid = i.obsid )
         AND ( datediff( SECOND, getdate(), c.last_modified ) < 0 ) )


go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Trigger 'jcmt.dbo.scuba2_update'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "jcmt.dbo.scuba2_update" >>>>>'
go 

setuser 'dbo'
go 

CREATE TRIGGER scuba2_update
ON SCUBA2
FOR UPDATE
AS
    UPDATE COMMON SET c.last_modified = dateadd( SECOND, 30, getdate() )
    FROM COMMON c, deleted d
    WHERE ( ( c.obsid = d.obsid )
        AND ( datediff( SECOND, getdate(), c.last_modified ) < 0 ) )


go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.TILES'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.TILES" >>>>>'
go

setuser 'dbo'
go 

create table TILES (
	obsid                           varchar(48)                      not null,
	tile                            int                              not null,
	uniqid                          numeric(9,0)                     identity 
)
lock allpages
with identity_gap = 5, dml_logging = full
 on 'default'
go 

Grant Select on dbo.TILES to public Granted by dbo
go
Grant Delete Statistics on dbo.TILES to jcmt Granted by dbo
go
Grant Truncate Table on dbo.TILES to jcmt Granted by dbo
go
Grant Update Statistics on dbo.TILES to jcmt Granted by dbo
go
Grant Transfer Table on dbo.TILES to jcmt Granted by dbo
go
Grant References on dbo.TILES to jcmt Granted by dbo
go
Grant Insert on dbo.TILES to jcmt Granted by dbo
go
Grant Delete on dbo.TILES to jcmt Granted by dbo
go
Grant Update on dbo.TILES to jcmt Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_osb_tile'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_osb_tile" >>>>>'
go 

create unique nonclustered index idx_osb_tile 
on jcmt.dbo.TILES(obsid, tile)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.keep_in_hilo'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.keep_in_hilo" >>>>>'
go

setuser 'dbo'
go 

create table keep_in_hilo (
	project                         varchar(32)                      not null,
	comment                         varchar(200)                         null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_keepproj'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_keepproj" >>>>>'
go 

create unique nonclustered index idx_keepproj 
on jcmt.dbo.keep_in_hilo(project)
with ignore_dup_key 
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.keep_in_hilo_obs'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.keep_in_hilo_obs" >>>>>'
go

setuser 'dbo'
go 

create table keep_in_hilo_obs (
	obsid                           varchar(48)                      not null,
	project                         varchar(32)                      not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_keepoid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_keepoid" >>>>>'
go 

create unique nonclustered index idx_keepoid 
on jcmt.dbo.keep_in_hilo_obs(obsid)
with ignore_dup_key 
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.ompfaultassoc'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.ompfaultassoc" >>>>>'
go

setuser 'dbo'
go 

create table ompfaultassoc (
	associd                         numeric(9,0)                     not null,
	faultid                         float(16)                        not null,
	projectid                       varchar(32)                      not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.ompfaultbodypub'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.ompfaultbodypub" >>>>>'
go

setuser 'dbo'
go 

create table ompfaultbodypub (
	respid                          numeric(9,0)                     not null,
	faultid                         float(16)                        not null,
	date                            datetime                         not null,
	author                          varchar(32)                      not null,
	isfault                         int                              not null,
	text                            text                             not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

sp_placeobject 'default', 'dbo.ompfaultbodypub.tompfaultbodypub'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.ompfaultpub'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.ompfaultpub" >>>>>'
go

setuser 'dbo'
go 

create table ompfaultpub (
	faultid                         float(16)                        not null,
	category                        varchar(32)                      not null,
	subject                         varchar(128)                         null,
	faultdate                       datetime                             null,
	type                            int                              not null,
	fsystem                         int                              not null,
	status                          int                              not null,
	urgency                         int                              not null,
	timelost                        real                             not null,
	entity                          varchar(64)                          null,
	condition                       int                                  null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.ompmsbdone'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.ompmsbdone" >>>>>'
go

setuser 'dbo'
go 

create table ompmsbdone (
	commid                          numeric(9,0)                     not null,
	checksum                        varchar(64)                      not null,
	status                          int                              not null,
	projectid                       varchar(32)                      not null,
	date                            datetime                         not null,
	target                          varchar(64)                      not null,
	instrument                      varchar(64)                      not null,
	waveband                        varchar(64)                      not null,
	comment                         text                             not null,
	title                           varchar(255)                         null,
	userid                          varchar(32)                          null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

sp_placeobject 'default', 'dbo.ompmsbdone.tompmsbdone'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.ompobslog'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.ompobslog" >>>>>'
go

setuser 'dbo'
go 

create table ompobslog (
	obslogid                        numeric(9,0)                     not null,
	runnr                           int                              not null,
	instrument                      varchar(32)                      not null,
	telescope                       varchar(32)                          null,
	date                            datetime                         not null,
	obsactive                       int                              not null,
	commentdate                     datetime                         not null,
	commenttext                     text                                 null,
	commentstatus                   int                              not null,
	obsid                           varchar(48)                          null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

sp_placeobject 'default', 'dbo.ompobslog.tompobslog'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.ompshiftlog'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.ompshiftlog" >>>>>'
go

setuser 'dbo'
go 

create table ompshiftlog (
	shiftid                         numeric(9,0)                     not null,
	date                            datetime                         not null,
	author                          varchar(32)                      not null,
	telescope                       varchar(32)                      not null,
	text                            text                             not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

sp_placeobject 'default', 'dbo.ompshiftlog.tompshiftlog'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.ompuser'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.ompuser" >>>>>'
go

setuser 'dbo'
go 

create table ompuser (
	userid                          varchar(32)                      not null,
	uname                           varchar(255)                     not null,
	email                           varchar(64)                          null,
	alias                           varchar(32)                          null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.rs_lastcommit'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.rs_lastcommit" >>>>>'
go

setuser 'dbo'
go 

create table rs_lastcommit (
	origin                          int                              not null,
	origin_qid                      binary(36)                       not null,
	secondary_qid                   binary(36)                       not null,
	origin_time                     datetime                         not null,
	dest_commit_time                datetime                         not null,
	pad1                            binary(255)                      not null,
	pad2                            binary(255)                      not null,
	pad3                            binary(255)                      not null,
	pad4                            binary(255)                      not null,
	pad5                            binary(4)                        not null,
	pad6                            binary(4)                        not null,
	pad7                            binary(4)                        not null,
	pad8                            binary(4)                        not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'rs_lastcommit_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "rs_lastcommit_idx" >>>>>'
go 

create unique clustered index rs_lastcommit_idx 
on jcmt.dbo.rs_lastcommit(origin)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.rs_threads'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.rs_threads" >>>>>'
go

setuser 'dbo'
go 

create table rs_threads (
	id                              int                              not null,
	seq                             int                              not null,
	pad1                            char(255)                        not null,
	pad2                            char(255)                        not null,
	pad3                            char(255)                        not null,
	pad4                            char(255)                        not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.rs_threads to public Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'rs_threads_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "rs_threads_idx" >>>>>'
go 

create unique clustered index rs_threads_idx 
on jcmt.dbo.rs_threads(id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.rs_ticket_history'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.rs_ticket_history" >>>>>'
go

setuser 'dbo'
go 

create table rs_ticket_history (
	cnt                             numeric(8,0)                     identity,
	h1                              varchar(10)                      not null,
	h2                              varchar(10)                      not null,
	h3                              varchar(10)                      not null,
	h4                              varchar(50)                      not null,
	pdb                             varchar(30)                      not null,
	prs                             varchar(30)                      not null,
	rrs                             varchar(30)                      not null,
	rdb                             varchar(30)                      not null,
	pdb_t                           datetime                         not null,
	exec_t                          datetime                         not null,
	dist_t                          datetime                         not null,
	rsi_t                           datetime                         not null,
	dsi_t                           datetime                         not null,
	rdb_t                           datetime                        DEFAULT  getdate()
  not null,
	exec_b                          numeric(22,0)                    not null,
	rsi_b                           numeric(22,0)                    not null,
	dsi_tnx                         numeric(22,0)                    not null,
	dsi_cmd                         numeric(22,0)                    not null,
	ticket                          varchar(1024)                    not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Delete Statistics on dbo.rs_ticket_history to public Granted by dbo
go
Grant Truncate Table on dbo.rs_ticket_history to public Granted by dbo
go
Grant Update Statistics on dbo.rs_ticket_history to public Granted by dbo
go
Grant References on dbo.rs_ticket_history to public Granted by dbo
go
Grant Select on dbo.rs_ticket_history to public Granted by dbo
go
Grant Insert on dbo.rs_ticket_history to public Granted by dbo
go
Grant Delete on dbo.rs_ticket_history to public Granted by dbo
go
Grant Update on dbo.rs_ticket_history to public Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'rs_ticket_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "rs_ticket_idx" >>>>>'
go 

create unique clustered index rs_ticket_idx 
on jcmt.dbo.rs_ticket_history(cnt)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.transfer'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.transfer" >>>>>'
go

setuser 'dbo'
go 

create table transfer (
	file_id                         varchar(70)                      not null,
	status                          char(1)                              null,
	created                         datetime                        DEFAULT   getdate() 
  not null,
	modified                        datetime                        DEFAULT  getdate()   
      null,
	location                        varchar(200)                         null,
	error                           bit                             DEFAULT  0           

  not null,
	comment                         varchar(250)                         null,
	keep_jac                        bit                             DEFAULT  0

  not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.transfer to public Granted by dbo
go
Grant Insert on dbo.transfer to jcmt Granted by dbo
go
Grant Update on dbo.transfer to jcmt Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'xfer_file_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "xfer_file_idx" >>>>>'
go 

create unique clustered index xfer_file_idx 
on jcmt.dbo.transfer(file_id)
with ignore_dup_key 
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt.dbo.transfer_state'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt.dbo.transfer_state" >>>>>'
go

setuser 'dbo'
go 

create table transfer_state (
	state                           char(1)                              null,
	descr                           varchar(30)                          null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.transfer_state to public Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'status_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "status_idx" >>>>>'
go 

create unique nonclustered index status_idx 
on jcmt.dbo.transfer_state(state)
go 


-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt.dbo.rs_check_repl_stat'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt.dbo.rs_check_repl_stat" >>>>>'
go 

setuser 'dbo'
go 


/* Create the procedure which checks replicate status */
create procedure rs_check_repl_stat 
	@rs_repl_name varchar(255)
as
	declare @current_status smallint
	select @current_status = sysstat
		from sysobjects
		where id=object_id(@rs_repl_name)
	if (@current_status & -32768) = -32768
		select 1
	else
		select 0


go 


sp_procxmode 'rs_check_repl_stat', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt.dbo.rs_get_lastcommit'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt.dbo.rs_get_lastcommit" >>>>>'
go 

setuser 'dbo'
go 


/* Create the procedure to get the last commit for all origins. */
create procedure rs_get_lastcommit
as
	select origin, origin_qid, secondary_qid
		from rs_lastcommit

go 


sp_procxmode 'rs_get_lastcommit', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt.dbo.rs_initialize_threads'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt.dbo.rs_initialize_threads" >>>>>'
go 

setuser 'dbo'
go 

/* Create the procedure to update the table. */
create procedure rs_initialize_threads
        @rs_id          int
as
	delete from rs_threads where id = @rs_id
	insert into rs_threads values (@rs_id, 0, "", "", "", "")

go 

Grant Execute on dbo.rs_initialize_threads to public Granted by dbo
go

sp_procxmode 'rs_initialize_threads', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt.dbo.rs_marker'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt.dbo.rs_marker" >>>>>'
go 

setuser 'dbo'
go 

create procedure rs_marker
@rs_api	varchar(16383)
as
/* Setup the bit that reflects a SQL Server replicated object. */
declare	@rep_constant	smallint
select @rep_constant = -32768

/* First make sure that this procedure is marked as replicated! */
if not exists (select sysstat
	from sysobjects
	where name = 'rs_marker'
		and type ='P'
		and sysstat & @rep_constant != 0)
begin
	print "Have your DBO execute 'sp_setreplicate' on the procedure 'rs_marker'"
	return (1)
end

/*
** There is nothing else to do in this procedure. It's execution
** should have been logged into the transaction log and picked up
** by the SQL Server LTM.
*/
 
go 


sp_procxmode 'rs_marker', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt.dbo.rs_send_repserver_cmd'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt.dbo.rs_send_repserver_cmd" >>>>>'
go 

setuser 'dbo'
go 

create procedure rs_send_repserver_cmd
        @rs_api varchar (16370)
as
begin
declare @cmd varchar (16384)

/* Make sure the Repserver Command Language does not contain keyword 'rs_rcl' */
if (patindex("%rs_rcl%", lower(@rs_api)) > 0)
begin
        print "The Replication Server command should not contain the keyword 'rs_rcl'"
        return(1)
end

/* Build the command into a format recognized by the Replication Server,
** replacing each single quotes with two single quotes.
*/
select @cmd = "rs_rcl '" + STR_REPLACE(@rs_api, "'", "''") + "' rs_rcl"

/* If the last few characters are not "rs_rcl", the input must be too long */
if (compare ("rs_rcl", substring (@cmd, datalength(@cmd) - 5, 6)) != 0)
begin
        print "The Replication Server command is too long."
        print "Please split it into two or more commands"
        return (1)
end
        exec rs_marker @cmd
end
 
go 


sp_procxmode 'rs_send_repserver_cmd', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt.dbo.rs_ticket'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt.dbo.rs_ticket" >>>>>'
go 

setuser 'dbo'
go 

create procedure rs_ticket
	@head1 varchar(10) = "ticket",
	@head2 varchar(10) = null,
	@head3 varchar(10) = null,
	@head4 varchar(50) = null
	as
	begin
	set nocount on

	declare @cmd	varchar(255),
		@c_time	datetime

	select @cmd = "V=2;H1=" + @head1
	if @head2 != null select @cmd = @cmd + ";H2=" + @head2
	if @head3 != null select @cmd = @cmd + ";H3=" + @head3
	if @head4 != null select @cmd = @cmd + ";H4=" + @head4

	-- @cmd = "rs_ticket 'V=2;H1=ticket;PDB(name)=mm/dd/yy hh:mm:ss.ddd'"
	select @c_time = getdate()
	select @cmd = "rs_ticket '" + @cmd + ";PDB(" + db_name() + ")="
		    + convert(varchar(8),@c_time,1) + " "
		    + convert(varchar(8),@c_time,8) + "." + right("00"
		    + convert(varchar(3),datepart(ms,@c_time)),3) + "'"

	-- print "exec rs_marker %1!", @cmd
	exec rs_marker @cmd
	end
go 

Grant Execute on dbo.rs_ticket to public Granted by dbo
go

sp_procxmode 'rs_ticket', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt.dbo.rs_ticket_report'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt.dbo.rs_ticket_report" >>>>>'
go 

setuser 'dbo'
go 


/*
** Name: rs_ticket_report
**   Append PDB timestamp to rs_ticket_param.
**   Repserver rs_ticket_report function string can be modified
**      to call this stored proceudre to process ticket.
**
** Parameter
**   rs_ticket_param: rs_ticket parameter in canonical form.
**
** rs_ticket parameter Canonical Form:
**   rs_ticket_param ::= <stamp> | <rs_ticket_param>;<stamp>
**   stamp           ::= <tag>=<value> | <tag>(info)=<value>
**   tag             ::= V | H | PDB | EXEC | B | DIST | DSI | RDB | ...
**   info            ::= Spid | PDB name
**   value           ::= integer | string | mm/dd/yy hh:mm:ss.ddd
**
** rs_ticket tag:
**   V:     Version number.
**   Hx:    Headers for identifying one or one set of tickets.
**   PDB:   Time stamp when ticket passing PDB.
**   EXEC:  Time stamps when ticket passing EXEC module.
**   DIST:  Time stamps when ticket passing DIST module.
**   RSI:   Time stamps when ticket passing RSI module.
**   DSI:   Time stamps when ticket passing DSI module.
**   RDB:   Time stamps when ticket passing RDB.
**   B:     Total bytes EXEC received from RepAgent.
**   RSI_B: Total bytes RSI sent to downstream Repserver.
**   DSI_T: Total transaction DSI sent to RDB.
**   DSI_C: Total commands DSI sent to RDB.
**   PRS:   Primary Repserver name.
**   RRS:   Replicate Repserver name.
**
** Note:
**   1. Don't mark rs_ticket_report for replication.
**   2. DSI will call rs_ticket_report iff DSI_RS_TICKET_REPORT in on.
**   3. This is an example stored procedure that demonstrates how to
**      add RDB timestamp to rs_ticket_param.
**   4. One should customize this function for parsing and inserting
**      timestamp to a table.
*/
create procedure rs_ticket_report
@rs_ticket_param varchar(255)
as
begin
set nocount on

declare @n_param varchar(255),
        @c_time  datetime

-- @n_param = "@rs_ticket_param;RDB(name)=mm/dd/yy hh:mm:ss.ddd"
select @c_time = getdate()
select @n_param = @rs_ticket_param + ";RDB(" + db_name() + ")="
                + convert(varchar(8),@c_time, 1) + " "
                + convert(varchar(8), @c_time, 8) + "." + right("00"
                + convert(varchar(3),datepart(ms,@c_time)) ,3)

-- print @n_param
end
 
go 

Grant Execute on dbo.rs_ticket_report to public Granted by dbo
go

sp_procxmode 'rs_ticket_report', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt.dbo.rs_ticket_v1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt.dbo.rs_ticket_v1" >>>>>'
go 

setuser 'dbo'
go 


/*
** Name: rs_ticket
**   Form rs_ticket parameter in canonical format and call
**        rs_marker "rs_ticket 'rs_ticket_param'"
**
** Parameter
**   head1: the first header. Default is "ticket"
**   head2: the second header. Default is null.
**   head3: the third header. Default is null.
**   head4: the last header. Default is null.
**
** rs_ticket parameter Canonical Form
**   rs_ticket_param ::= <section> | <rs_ticket_param>;<section>
**   section         ::= <tagxxx>=<value>
**   tag             ::= V | H | PDB | EXEC | B | DIST | DSI | RDB | ...
**   Version value   ::= integer
**   Header value    ::= string of varchar(10)
**   DB value        ::= database name
**   Byte value      ::= integer
**   Time value      ::= hh:mm:ss.ddd
**
** Note:
**   1. Don't mark rs_ticket for replication.
**   2. Headers must be 10 character or less.
**   3. For more than 4 headers, passing something like
**        "four;H5=five;H6=six..."
**   4. Don't pass too many headers. rs_ticket_param must be less 255.
**   5. Don't put any single or double quotation mark in header.
**   6. Keep header simple to avoid confusing Repserver parser.
*/
create procedure rs_ticket
@head1 varchar(10) = "ticket",
@head2 varchar(10) = null,
@head3 varchar(10) = null,
@head4 varchar(50) = null
as
begin
set nocount on

declare @cmd	varchar(255),
	@c_time	datetime

select @cmd = "V=1;H1=" + @head1
if @head2 != null select @cmd = @cmd + ";H2=" + @head2
if @head3 != null select @cmd = @cmd + ";H3=" + @head3
if @head4 != null select @cmd = @cmd + ";H4=" + @head4

-- @cmd = "rs_ticket 'V=1;H1=ticket;PDB(name)=hh:mm:ss.ddd'"
select @c_time = getdate()
select @cmd = "rs_ticket '" + @cmd + ";PDB(" + db_name() + ")="
	    + convert(varchar(8),@c_time,8) + "." + right("00"
	    + convert(varchar(3),datepart(ms,@c_time)),3) + "'"

-- print "exec rs_marker %1!", @cmd
exec rs_marker @cmd
end

go 

Grant Execute on dbo.rs_ticket_v1 to public Granted by dbo
go

sp_procxmode 'rs_ticket_v1', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt.dbo.rs_update_lastcommit'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt.dbo.rs_update_lastcommit" >>>>>'
go 

setuser 'dbo'
go 

/* Create the procedure to update the table. */
create procedure rs_update_lastcommit
	@origin		int,
	@origin_qid	binary(36),
	@secondary_qid	binary(36),
	@origin_time	datetime
as
	update rs_lastcommit
		set origin_qid = @origin_qid, secondary_qid = @secondary_qid,
			origin_time = @origin_time,
			dest_commit_time = getdate()
		where origin = @origin
	if (@@rowcount = 0)
	begin
		insert rs_lastcommit (origin, origin_qid, secondary_qid,
				origin_time, dest_commit_time,
				pad1, pad2, pad3, pad4, pad5, pad6, pad7, pad8)
			values (@origin, @origin_qid, @secondary_qid,
				@origin_time, getdate(),
				0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
	end

go 


sp_procxmode 'rs_update_lastcommit', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt.dbo.rs_update_threads'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt.dbo.rs_update_threads" >>>>>'
go 

setuser 'dbo'
go 

/* Create the procedure to update the table. */
create procedure rs_update_threads
        @rs_id          int,
        @rs_seq         int
as
        update rs_threads set seq = @rs_seq where id = @rs_id

go 

Grant Execute on dbo.rs_update_threads to public Granted by dbo
go

sp_procxmode 'rs_update_threads', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- Dependent DDL for Object(s)
-----------------------------------------------------------------------------
use jcmt
go 

sp_addthreshold jcmt, 'logsegment', 1631720, sp_thresholdaction
go 

sp_addthreshold jcmt, 'logsegment', 322560, sp_thresholdaction
go 

Grant Select on dbo.sysobjects(name,id,uid,type,userstat,sysstat,indexdel,schemacnt,sysstat2,crdate,expdate,deltrig,instrig,updtrig,seltrig,ckfirst,cache,objspare,versionts,loginame,identburnmax,spacestate,erlchgts,sysstat3,lobcomp_lvl) to public Granted by dbo
go
Grant Select on dbo.sysindexes to public Granted by dbo
go
Grant Select on dbo.syscolumns to public Granted by dbo
go
Grant Select on dbo.systypes to public Granted by dbo
go
Grant Select on dbo.sysprocedures to public Granted by dbo
go
Grant Select on dbo.syscomments to public Granted by dbo
go
Grant Select on dbo.syssegments to public Granted by dbo
go
Grant Select on dbo.syslogs to public Granted by dbo
go
Grant Select on dbo.sysprotects to public Granted by dbo
go
Grant Select on dbo.sysusers to public Granted by dbo
go
Grant Select on dbo.sysalternates to public Granted by dbo
go
Grant Select on dbo.sysdepends to public Granted by dbo
go
Grant Select on dbo.syskeys to public Granted by dbo
go
Grant Select on dbo.sysusermessages to public Granted by dbo
go
Grant Select on dbo.sysreferences to public Granted by dbo
go
Grant Select on dbo.sysconstraints to public Granted by dbo
go
Grant Select on dbo.systhresholds to public Granted by dbo
go
Grant Select on dbo.sysroles to public Granted by dbo
go
Grant Select on dbo.sysattributes to public Granted by dbo
go
Grant Select on dbo.sysslices to public Granted by dbo
go
Grant Select on dbo.systabstats to public Granted by dbo
go
Grant Select on dbo.sysstatistics to public Granted by dbo
go
Grant Select on dbo.sysxtypes to public Granted by dbo
go
Grant Select on dbo.sysjars to public Granted by dbo
go
Grant Select on dbo.sysqueryplans to public Granted by dbo
go
Grant Select on dbo.syspartitions to public Granted by dbo
go
Grant Select on dbo.syspartitionkeys to public Granted by dbo
go
Grant Select on dbo.TILES to public Granted by dbo
go
Grant Select on dbo.COMMON to public Granted by dbo
go
Grant Select on dbo.ACSIS to public Granted by dbo
go
Grant Select on dbo.FILES to public Granted by dbo
go
Grant Select on dbo.SCUBA2 to public Granted by dbo
go
Grant Select on dbo.transfer to public Granted by dbo
go
Grant Select on dbo.transfer_state to public Granted by dbo
go
Grant Select on dbo.rs_threads to public Granted by dbo
go
Grant Execute on dbo.rs_update_threads to public Granted by dbo
go
Grant Execute on dbo.rs_initialize_threads to public Granted by dbo
go
Grant Execute on dbo.rs_ticket_v1 to public Granted by dbo
go
Grant References on dbo.rs_ticket_history to public Granted by dbo
go
Grant Select on dbo.rs_ticket_history to public Granted by dbo
go
Grant Insert on dbo.rs_ticket_history to public Granted by dbo
go
Grant Delete on dbo.rs_ticket_history to public Granted by dbo
go
Grant Update on dbo.rs_ticket_history to public Granted by dbo
go
Grant Delete Statistics on dbo.rs_ticket_history to public Granted by dbo
go
Grant Truncate Table on dbo.rs_ticket_history to public Granted by dbo
go
Grant Update Statistics on dbo.rs_ticket_history to public Granted by dbo
go
Grant Execute on dbo.rs_ticket_report to public Granted by dbo
go
Grant Execute on dbo.rs_ticket to public Granted by dbo
go
Grant References on dbo.TILES to jcmt Granted by dbo
go
Grant Insert on dbo.TILES to jcmt Granted by dbo
go
Grant Delete on dbo.TILES to jcmt Granted by dbo
go
Grant Update on dbo.TILES to jcmt Granted by dbo
go
Grant Delete Statistics on dbo.TILES to jcmt Granted by dbo
go
Grant Truncate Table on dbo.TILES to jcmt Granted by dbo
go
Grant Update Statistics on dbo.TILES to jcmt Granted by dbo
go
Grant Transfer Table on dbo.TILES to jcmt Granted by dbo
go
Grant Insert on dbo.COMMON to jcmt Granted by dbo
go
Grant Delete on dbo.COMMON to jcmt Granted by dbo
go
Grant Update on dbo.COMMON to jcmt Granted by dbo
go
Grant Insert on dbo.ACSIS to jcmt Granted by dbo
go
Grant Delete on dbo.ACSIS to jcmt Granted by dbo
go
Grant Update on dbo.ACSIS to jcmt Granted by dbo
go
Grant Insert on dbo.FILES to jcmt Granted by dbo
go
Grant Delete on dbo.FILES to jcmt Granted by dbo
go
Grant Update on dbo.FILES to jcmt Granted by dbo
go
Grant Insert on dbo.SCUBA2 to jcmt Granted by dbo
go
Grant Delete on dbo.SCUBA2 to jcmt Granted by dbo
go
Grant Update on dbo.SCUBA2 to jcmt Granted by dbo
go
Grant Insert on dbo.transfer to jcmt Granted by dbo
go
Grant Update on dbo.transfer to jcmt Granted by dbo
go
Grant Create Table to jcmt Granted by dbo
go
Grant Create View to jcmt Granted by dbo
go
Grant Create Procedure to jcmt Granted by dbo
go
Grant Create Default to jcmt Granted by dbo
go
Grant Create Rule to jcmt Granted by dbo
go
Grant Create Function to jcmt Granted by dbo
go
alter table jcmt.dbo.transfer
add constraint state_check FOREIGN KEY (status) REFERENCES jcmt.dbo.transfer_state(state)
go



-- DDLGen Completed
-- at 12/06/17 9:38:37 HST