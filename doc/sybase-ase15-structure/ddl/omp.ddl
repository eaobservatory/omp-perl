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
-- -S SYB_JAC -I /opt2/sybase/ase-15.0/interfaces -P*** -U sa -O ddl/omp.ddl -L omp.progress.2017-1206-0938 -T DB -N omp 
-- at 12/06/17 9:38:18 HST


USE master
go


PRINT "<<<< CREATE DATABASE omp>>>>"
go


IF EXISTS (SELECT 1 FROM master.dbo.sysdatabases
	   WHERE name = 'omp')
	DROP DATABASE omp
go


IF (@@error != 0)
BEGIN
	PRINT "Error dropping database 'omp'"
	SELECT syb_quit()
END
go


CREATE DATABASE omp
	    ON dev_omp_db_0 = '7168M' -- 3670016 pages
	LOG ON dev_omp_db_0 = '3548M' -- 1816576 pages
WITH OVERRIDE
   , DURABILITY = FULL
go


ALTER DATABASE omp
	    ON dev_omp_db_0 = '2512M' -- 1286144 pages
	LOG ON dev_omp_db_0 = '84M' -- 43008 pages
	     , dev_omp_db_1 = '2168M' -- 1110016 pages
go


ALTER DATABASE omp
	    ON dev_omp_db_1 = '5000M' -- 2560000 pages
	LOG ON dev_omp_db_1 = '6600M' -- 3379200 pages
WITH OVERRIDE
go


ALTER DATABASE omp
	    ON dev_omp_db_1 = '3400M' -- 1740800 pages
	LOG ON dev_omp_db_1 = '13843M' -- 7087616 pages
go


ALTER DATABASE omp
	    ON dev_omp_db_1 = '1757M' -- 899584 pages
	LOG ON dev_omp_log_0 = '3500M' -- 1792000 pages
	     , dev_omp_log_1 = '16384M' -- 8388608 pages
go


use omp
go

exec sp_changedbowner 'sa', true 
go

exec master.dbo.sp_dboption omp, 'select into/bulkcopy/pllsort', true
go

exec master.dbo.sp_dboption omp, 'ddl in tran', true
go

exec master.dbo.sp_dboption omp, 'abort tran on log full', true
go

exec master.dbo.sp_dboption omp, 'full logging for all', true
go

checkpoint
go


-----------------------------------------------------------------------------
-- DDL for User 'casu'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "casu" >>>>>'
go 

exec sp_adduser 'casu' ,'casu' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for User 'datareader'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "datareader" >>>>>'
go 

exec sp_adduser 'datareader' ,'datareader' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for User 'omp_maint'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "omp_maint" >>>>>'
go 

exec sp_adduser 'omp_maint' ,'omp_maint' ,'public'
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
-- DDL for Table 'omp.dbo.devprojuser'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.devprojuser" >>>>>'
go

use omp
go 

setuser 'dbo'
go 

create table devprojuser (
	uniqid                          numeric(9,0)                     identity,
	projectid                       varchar(32)                      not null,
	userid                          varchar(32)                      not null,
	capacity                        varchar(16)                      not null,
	contactable                     bit                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.devprojuser to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompaffiliationalloc'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompaffiliationalloc" >>>>>'
go

setuser 'dbo'
go 

create table ompaffiliationalloc (
	semester                        varchar(32)                      not null,
	affiliation                     varchar(32)                      not null,
	allocation                      real                             not null,
	observed                        real                            DEFAULT  0.0 
  not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'ompaffiliationalloc_sem_aff'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "ompaffiliationalloc_sem_aff" >>>>>'
go 

create unique nonclustered index ompaffiliationalloc_sem_aff 
on omp.dbo.ompaffiliationalloc(semester, affiliation)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfault'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfault" >>>>>'
go

setuser 'dbo'
go 

create table ompfault (
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
	condition                       int                                  null,
	location                        int                                  null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.ompfault to staff Granted by dbo
go
Grant Select on dbo.ompfault to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_faultid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_faultid" >>>>>'
go 

create unique clustered index idx_faultid 
on omp.dbo.ompfault(faultid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfault_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfault_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompfault_20060421 (
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
-- DDL for Index 'idx_uc_faultid_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_uc_faultid_1" >>>>>'
go 

create unique clustered index idx_uc_faultid_1 
on omp.dbo.ompfault_20060421(faultid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfaultassoc'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfaultassoc" >>>>>'
go

setuser 'dbo'
go 

create table ompfaultassoc (
	associd                         numeric(9,0)                     identity,
	faultid                         float(16)                        not null,
	projectid                       varchar(32)                      not null,
 PRIMARY KEY CLUSTERED ( faultid, projectid )  on 'default' 
)
lock allpages
with identity_gap = 1, dml_logging = full
 on 'default'
go 

Grant Select on dbo.ompfaultassoc to staff Granted by dbo
go
Grant Select on dbo.ompfaultassoc to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_associd'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_associd" >>>>>'
go 

create unique nonclustered index idx_associd 
on omp.dbo.ompfaultassoc(associd)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfaultassoc_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfaultassoc_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompfaultassoc_20060421 (
	associd                         numeric(9,0)                     identity,
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
-- DDL for Table 'omp.dbo.ompfaultbody'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfaultbody" >>>>>'
go

setuser 'dbo'
go 

create table ompfaultbody (
	respid                          numeric(9,0)                     identity,
	faultid                         float(16)                        not null,
	date                            datetime                         not null,
	author                          varchar(32)                      not null,
	isfault                         int                              not null,
	text                            text                             not null,
 PRIMARY KEY CLUSTERED ( faultid, date, author )  on 'default' 
)
lock allpages
with identity_gap = 1, dml_logging = full
 on 'default'
go 

sp_placeobject 'default', 'dbo.ompfaultbody.tompfaultbody'
go 

Grant Select on dbo.ompfaultbody to staff Granted by dbo
go
Grant Select on dbo.ompfaultbody to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_ompfaultbody_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_ompfaultbody_1" >>>>>'
go 

create nonclustered index idx_ompfaultbody_1 
on omp.dbo.ompfaultbody(faultid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfaultbody_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfaultbody_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompfaultbody_20060421 (
	respid                          numeric(9,0)                     identity,
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

sp_placeobject 'default', 'dbo.ompfaultbody_20060421.tompfaultbody_20060421'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_faultid_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_faultid_1" >>>>>'
go 

create nonclustered index idx_faultid_1 
on omp.dbo.ompfaultbody_20060421(faultid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfaultbody_compare'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfaultbody_compare" >>>>>'
go

setuser 'dbo'
go 

create table ompfaultbody_compare (
	respid                          numeric(9,0)                     identity,
	faultid                         float(16)                        not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

Grant Select on dbo.ompfaultbody_compare to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfaultbody_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfaultbody_id" >>>>>'
go

setuser 'dbo'
go 

create table ompfaultbody_id (
	respid                          numeric(9,0)                     identity,
	faultid                         float(16)                        not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

Grant Select on dbo.ompfaultbody_id to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfeedback'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfeedback" >>>>>'
go

setuser 'dbo'
go 

create table ompfeedback (
	commid                          numeric(9,0)                     identity,
	projectid                       varchar(32)                      not null,
	author                          varchar(32)                          null,
	date                            datetime                         not null,
	subject                         varchar(128)                         null,
	program                         varchar(50)                      not null,
	sourceinfo                      varchar(60)                      not null,
	status                          int                                  null,
	text                            text                             not null,
	msgtype                         int                                  null,
	entrynum                        numeric(9,0)                    DEFAULT  0 
      null 
)
lock allpages
with identity_gap = 1, dml_logging = full
 on 'default'
go 

sp_placeobject 'default', 'dbo.ompfeedback.tompfeedback'
go 

Grant Select on dbo.ompfeedback to casu Granted by dbo
go
Grant Select on dbo.ompfeedback to staff Granted by dbo
go
Grant Select on dbo.ompfeedback to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_date'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_date" >>>>>'
go 

create nonclustered index idx_date 
on omp.dbo.ompfeedback(date)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'feedback_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "feedback_idx" >>>>>'
go 

create nonclustered index feedback_idx 
on omp.dbo.ompfeedback(projectid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfeedback_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfeedback_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompfeedback_20060421 (
	commid                          numeric(9,0)                     identity,
	entrynum                        numeric(4,0)                     not null,
	projectid                       varchar(32)                      not null,
	author                          varchar(32)                          null,
	date                            datetime                         not null,
	subject                         varchar(128)                         null,
	program                         varchar(50)                      not null,
	sourceinfo                      varchar(60)                      not null,
	status                          int                                  null,
	text                            text                             not null,
	msgtype                         int                                  null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

sp_placeobject 'default', 'dbo.ompfeedback_20060421.tompfeedback_20060421'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfeedback_20060508'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfeedback_20060508" >>>>>'
go

setuser 'dbo'
go 

create table ompfeedback_20060508 (
	commid                          numeric(9,0)                     identity,
	entrynum                        numeric(4,0)                     not null,
	projectid                       varchar(32)                      not null,
	author                          varchar(32)                          null,
	date                            datetime                         not null,
	subject                         varchar(128)                         null,
	program                         varchar(50)                      not null,
	sourceinfo                      varchar(60)                      not null,
	status                          int                                  null,
	text                            text                             not null,
	msgtype                         int                                  null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

sp_placeobject 'default', 'dbo.ompfeedback_20060508.tompfeedback_20060508'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfeedback_cmp'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfeedback_cmp" >>>>>'
go

setuser 'dbo'
go 

create table ompfeedback_cmp (
	commid                          numeric(9,0)                     identity 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompfeedback_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompfeedback_id" >>>>>'
go

setuser 'dbo'
go 

create table ompfeedback_id (
	commid                          numeric(9,0)                     identity 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompkey'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompkey" >>>>>'
go

setuser 'dbo'
go 

create table ompkey (
	keystring                       varchar(64)                      not null,
	expiry                          datetime                         not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

Grant Select on dbo.ompkey to staff Granted by dbo
go
Grant Select on dbo.ompkey to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompmsb'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompmsb" >>>>>'
go

setuser 'dbo'
go 

create table ompmsb (
	msbid                           int                              not null,
	projectid                       varchar(32)                      not null,
	remaining                       int                              not null,
	checksum                        varchar(64)                      not null,
	obscount                        int                              not null,
	taumin                          real                             not null,
	taumax                          real                             not null,
	seeingmin                       real                             not null,
	seeingmax                       real                             not null,
	priority                        int                              not null,
	telescope                       varchar(16)                      not null,
	moonmax                         int                              not null,
	cloudmax                        int                              not null,
	timeest                         real                             not null,
	title                           varchar(255)                         null,
	datemin                         datetime                         not null,
	datemax                         datetime                         not null,
	minel                           real                                 null,
	maxel                           real                                 null,
	approach                        int                                  null,
	moonmin                         int                              not null,
	cloudmin                        int                              not null,
	skymin                          real                             not null,
	skymax                          real                             not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.ompmsb to casu Granted by dbo
go
Grant Select on dbo.ompmsb to staff Granted by dbo
go
Grant Select on dbo.ompmsb to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_msbid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_msbid" >>>>>'
go 

create unique clustered index idx_msbid 
on omp.dbo.ompmsb(msbid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_telescope'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_telescope" >>>>>'
go 

create nonclustered index idx_telescope 
on omp.dbo.ompmsb(telescope)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_datemin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_datemin" >>>>>'
go 

create nonclustered index idx_datemin 
on omp.dbo.ompmsb(datemin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_datemax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_datemax" >>>>>'
go 

create nonclustered index idx_datemax 
on omp.dbo.ompmsb(datemax)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_remaining'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_remaining" >>>>>'
go 

create nonclustered index idx_remaining 
on omp.dbo.ompmsb(remaining)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_obscount'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_obscount" >>>>>'
go 

create nonclustered index idx_obscount 
on omp.dbo.ompmsb(obscount)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_projectid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_projectid" >>>>>'
go 

create nonclustered index idx_projectid 
on omp.dbo.ompmsb(projectid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_timeest'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_timeest" >>>>>'
go 

create nonclustered index idx_timeest 
on omp.dbo.ompmsb(timeest)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_taumax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_taumax" >>>>>'
go 

create nonclustered index idx_taumax 
on omp.dbo.ompmsb(taumax)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_taumin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_taumin" >>>>>'
go 

create nonclustered index idx_taumin 
on omp.dbo.ompmsb(taumin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_skymin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_skymin" >>>>>'
go 

create nonclustered index idx_skymin 
on omp.dbo.ompmsb(skymin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_skymax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_skymax" >>>>>'
go 

create nonclustered index idx_skymax 
on omp.dbo.ompmsb(skymax)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_moonmin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_moonmin" >>>>>'
go 

create nonclustered index idx_moonmin 
on omp.dbo.ompmsb(moonmin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_moonmax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_moonmax" >>>>>'
go 

create nonclustered index idx_moonmax 
on omp.dbo.ompmsb(moonmax)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_cloudmin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_cloudmin" >>>>>'
go 

create nonclustered index idx_cloudmin 
on omp.dbo.ompmsb(cloudmin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_cloudmax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_cloudmax" >>>>>'
go 

create nonclustered index idx_cloudmax 
on omp.dbo.ompmsb(cloudmax)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_seeingmin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_seeingmin" >>>>>'
go 

create nonclustered index idx_seeingmin 
on omp.dbo.ompmsb(seeingmin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_seeingmax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_seeingmax" >>>>>'
go 

create nonclustered index idx_seeingmax 
on omp.dbo.ompmsb(seeingmax)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompmsb_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompmsb_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompmsb_20060421 (
	msbid                           int                              not null,
	projectid                       varchar(32)                      not null,
	remaining                       int                              not null,
	checksum                        varchar(64)                      not null,
	obscount                        int                              not null,
	taumin                          real                             not null,
	taumax                          real                             not null,
	seeingmin                       real                             not null,
	seeingmax                       real                             not null,
	priority                        int                              not null,
	telescope                       varchar(16)                      not null,
	moonmax                         int                              not null,
	cloudmax                        int                              not null,
	timeest                         real                             not null,
	title                           varchar(255)                         null,
	datemin                         datetime                         not null,
	datemax                         datetime                         not null,
	minel                           real                                 null,
	maxel                           real                                 null,
	approach                        int                                  null,
	moonmin                         int                              not null,
	cloudmin                        int                              not null,
	skymin                          real                             not null,
	skymax                          real                             not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_uc_msbid_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_uc_msbid_1" >>>>>'
go 

create unique clustered index idx_uc_msbid_1 
on omp.dbo.ompmsb_20060421(msbid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_telescope'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_telescope" >>>>>'
go 

create nonclustered index idx_telescope 
on omp.dbo.ompmsb_20060421(telescope)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_datemin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_datemin" >>>>>'
go 

create nonclustered index idx_datemin 
on omp.dbo.ompmsb_20060421(datemin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_datemax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_datemax" >>>>>'
go 

create nonclustered index idx_datemax 
on omp.dbo.ompmsb_20060421(datemax)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_remaining'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_remaining" >>>>>'
go 

create nonclustered index idx_remaining 
on omp.dbo.ompmsb_20060421(remaining)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_obscount'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_obscount" >>>>>'
go 

create nonclustered index idx_obscount 
on omp.dbo.ompmsb_20060421(obscount)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_projectid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_projectid" >>>>>'
go 

create nonclustered index idx_projectid 
on omp.dbo.ompmsb_20060421(projectid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_timeest'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_timeest" >>>>>'
go 

create nonclustered index idx_timeest 
on omp.dbo.ompmsb_20060421(timeest)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_taumax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_taumax" >>>>>'
go 

create nonclustered index idx_taumax 
on omp.dbo.ompmsb_20060421(taumax)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_taumin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_taumin" >>>>>'
go 

create nonclustered index idx_taumin 
on omp.dbo.ompmsb_20060421(taumin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_skymin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_skymin" >>>>>'
go 

create nonclustered index idx_skymin 
on omp.dbo.ompmsb_20060421(skymin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_skymax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_skymax" >>>>>'
go 

create nonclustered index idx_skymax 
on omp.dbo.ompmsb_20060421(skymax)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_moonmin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_moonmin" >>>>>'
go 

create nonclustered index idx_moonmin 
on omp.dbo.ompmsb_20060421(moonmin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_moonmax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_moonmax" >>>>>'
go 

create nonclustered index idx_moonmax 
on omp.dbo.ompmsb_20060421(moonmax)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_cloudmin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_cloudmin" >>>>>'
go 

create nonclustered index idx_cloudmin 
on omp.dbo.ompmsb_20060421(cloudmin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_cloudmax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_cloudmax" >>>>>'
go 

create nonclustered index idx_cloudmax 
on omp.dbo.ompmsb_20060421(cloudmax)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_seeingmin'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_seeingmin" >>>>>'
go 

create nonclustered index idx_seeingmin 
on omp.dbo.ompmsb_20060421(seeingmin)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_seeingmax'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_seeingmax" >>>>>'
go 

create nonclustered index idx_seeingmax 
on omp.dbo.ompmsb_20060421(seeingmax)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompmsb_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompmsb_id" >>>>>'
go

setuser 'dbo'
go 

create table ompmsb_id (
	msbid                           int                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompmsb_omp1_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompmsb_omp1_id" >>>>>'
go

setuser 'dbo'
go 

create table ompmsb_omp1_id (
	msbid                           int                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompmsbdone'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompmsbdone" >>>>>'
go

setuser 'dbo'
go 

create table ompmsbdone (
	commid                          numeric(9,0)                     identity,
	checksum                        varchar(64)                      not null,
	status                          int                              not null,
	projectid                       varchar(32)                      not null,
	date                            datetime                         not null,
	target                          varchar(64)                      not null,
	instrument                      varchar(64)                      not null,
	waveband                        varchar(64)                      not null,
	comment                         text                             not null,
	title                           varchar(255)                         null,
	userid                          varchar(32)                          null,
	msbtid                          varchar(32)                          null 
)
lock allpages
with identity_gap = 1, dml_logging = full
 on 'default'
partition by roundrobin 1
go 

sp_placeobject 'default', 'dbo.ompmsbdone.tompmsbdone'
go 

Grant Select on dbo.ompmsbdone to casu Granted by dbo
go
Grant Select on dbo.ompmsbdone to staff Granted by dbo
go
Grant Select on dbo.ompmsbdone to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_ompmsbdone_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_ompmsbdone_1" >>>>>'
go 

create unique nonclustered index idx_ompmsbdone_1 
on omp.dbo.ompmsbdone(commid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'msbdone_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "msbdone_idx" >>>>>'
go 

create nonclustered index msbdone_idx 
on omp.dbo.ompmsbdone(projectid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompmsbdone_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompmsbdone_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompmsbdone_20060421 (
	commid                          numeric(9,0)                     identity,
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

sp_placeobject 'default', 'dbo.ompmsbdone_20060421.tompmsbdone_20060421'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompmsbdone_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompmsbdone_id" >>>>>'
go

setuser 'dbo'
go 

create table ompmsbdone_id (
	commid                          numeric(9,0)                     identity 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompmsbdone_omp1_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompmsbdone_omp1_id" >>>>>'
go

setuser 'dbo'
go 

create table ompmsbdone_omp1_id (
	commid                          numeric(9,0)                     identity 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompobs'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompobs" >>>>>'
go

setuser 'dbo'
go 

create table ompobs (
	msbid                           int                              not null,
	projectid                       varchar(32)                      not null,
	instrument                      varchar(32)                      not null,
	type                            varchar(32)                      not null,
	pol                             bit                              not null,
	wavelength                      real                             not null,
	disperser                       varchar(32)                          null,
	coordstype                      varchar(32)                      not null,
	target                          varchar(32)                      not null,
	ra2000                          real                                 null,
	dec2000                         real                                 null,
	el1                             real                                 null,
	el2                             real                                 null,
	el3                             real                                 null,
	el4                             real                                 null,
	el5                             real                                 null,
	el6                             real                                 null,
	el7                             real                                 null,
	el8                             real                                 null,
	timeest                         real                             not null,
	obsid                           bigint                           identity 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.ompobs to casu Granted by dbo
go
Grant Select on dbo.ompobs to staff Granted by dbo
go
Grant Select on dbo.ompobs to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_instument'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_instument" >>>>>'
go 

create nonclustered index idx_instument 
on omp.dbo.ompobs(instrument)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_msbid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_msbid" >>>>>'
go 

create nonclustered index idx_msbid 
on omp.dbo.ompobs(msbid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompobs_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompobs_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompobs_20060421 (
	obsid                           int                              not null,
	msbid                           int                              not null,
	projectid                       varchar(32)                      not null,
	instrument                      varchar(32)                      not null,
	type                            varchar(32)                      not null,
	pol                             bit                              not null,
	wavelength                      real                             not null,
	disperser                       varchar(32)                          null,
	coordstype                      varchar(32)                      not null,
	target                          varchar(32)                      not null,
	ra2000                          real                                 null,
	dec2000                         real                                 null,
	el1                             real                                 null,
	el2                             real                                 null,
	el3                             real                                 null,
	el4                             real                                 null,
	el5                             real                                 null,
	el6                             real                                 null,
	el7                             real                                 null,
	el8                             real                                 null,
	timeest                         real                             not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_instrument'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_instrument" >>>>>'
go 

create nonclustered index idx_instrument 
on omp.dbo.ompobs_20060421(instrument)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_msbid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_msbid" >>>>>'
go 

create nonclustered index idx_msbid 
on omp.dbo.ompobs_20060421(msbid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompobslog'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompobslog" >>>>>'
go

setuser 'dbo'
go 

create table ompobslog (
	obslogid                        numeric(9,0)                     identity,
	runnr                           int                              not null,
	instrument                      varchar(32)                      not null,
	telescope                       varchar(32)                          null,
	date                            datetime                         not null,
	obsactive                       int                              not null,
	commentdate                     datetime                         not null,
	commentauthor                   varchar(32)                      not null,
	commenttext                     text                                 null,
	commentstatus                   int                              not null,
	obsid                           varchar(48)                          null 
)
lock allpages
with identity_gap = 1, dml_logging = full
 on 'default'
go 

sp_placeobject 'default', 'dbo.ompobslog.tompobslog'
go 

Grant Select on dbo.ompobslog to casu Granted by dbo
go
Grant Select on dbo.ompobslog to staff Granted by dbo
go
Grant Select on dbo.ompobslog to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_ompobslog_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_ompobslog_1" >>>>>'
go 

create unique clustered index idx_ompobslog_1 
on omp.dbo.ompobslog(obslogid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompobslog_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompobslog_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompobslog_20060421 (
	obslogid                        numeric(9,0)                     identity,
	runnr                           int                              not null,
	instrument                      varchar(32)                      not null,
	telescope                       varchar(32)                          null,
	date                            datetime                         not null,
	obsactive                       int                              not null,
	commentdate                     datetime                         not null,
	commentauthor                   varchar(32)                      not null,
	commenttext                     text                                 null,
	commentstatus                   int                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

sp_placeobject 'default', 'dbo.ompobslog_20060421.tompobslog_20060421'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompobslog_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompobslog_id" >>>>>'
go

setuser 'dbo'
go 

create table ompobslog_id (
	obslogid                        numeric(9,0)                     identity 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompobslog_omp1_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompobslog_omp1_id" >>>>>'
go

setuser 'dbo'
go 

create table ompobslog_omp1_id (
	obslogid                        numeric(9,0)                     identity 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompproj'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompproj" >>>>>'
go

setuser 'dbo'
go 

create table ompproj (
	projectid                       varchar(32)                      not null,
	pi                              varchar(32)                      not null,
	title                           varchar(255)                         null,
	semester                        varchar(10)                      not null,
	encrypted                       varchar(20)                      not null,
	allocated                       real                             not null,
	remaining                       real                             not null,
	pending                         real                             not null,
	telescope                       varchar(16)                      not null,
	taumin                          real                             not null,
	taumax                          real                             not null,
	seeingmin                       real                             not null,
	seeingmax                       real                             not null,
	cloudmax                        int                              not null,
	state                           bit                              not null,
	cloudmin                        int                              not null,
	skymin                          real                             not null,
	skymax                          real                             not null 
)
lock allpages
with identity_gap = 1, dml_logging = full
 on 'default'
go 

Grant Select on dbo.ompproj to casu Granted by dbo
go
Grant Select on dbo.ompproj to staff Granted by dbo
go
Grant Select on dbo.ompproj to russell Granted by dbo
go
Grant Select on dbo.ompproj to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_projectid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_projectid" >>>>>'
go 

create unique clustered index idx_projectid 
on omp.dbo.ompproj(projectid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_semester'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_semester" >>>>>'
go 

create nonclustered index idx_semester 
on omp.dbo.ompproj(semester)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_allocated'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_allocated" >>>>>'
go 

create nonclustered index idx_allocated 
on omp.dbo.ompproj(allocated)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_remaining'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_remaining" >>>>>'
go 

create nonclustered index idx_remaining 
on omp.dbo.ompproj(remaining)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_telescope'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_telescope" >>>>>'
go 

create nonclustered index idx_telescope 
on omp.dbo.ompproj(telescope)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_pending'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_pending" >>>>>'
go 

create nonclustered index idx_pending 
on omp.dbo.ompproj(pending)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompproj_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompproj_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompproj_20060421 (
	projectid                       varchar(32)                      not null,
	pi                              varchar(32)                      not null,
	title                           varchar(255)                         null,
	semester                        varchar(10)                      not null,
	encrypted                       varchar(20)                      not null,
	allocated                       real                             not null,
	remaining                       real                             not null,
	pending                         real                             not null,
	telescope                       varchar(16)                      not null,
	taumin                          real                             not null,
	taumax                          real                             not null,
	seeingmin                       real                             not null,
	seeingmax                       real                             not null,
	cloudmax                        int                              not null,
	state                           bit                              not null,
	cloudmin                        int                              not null,
	skymin                          real                             not null,
	skymax                          real                             not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_uc_projectid_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_uc_projectid_1" >>>>>'
go 

create unique clustered index idx_uc_projectid_1 
on omp.dbo.ompproj_20060421(projectid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_semester_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_semester_1" >>>>>'
go 

create nonclustered index idx_semester_1 
on omp.dbo.ompproj_20060421(semester)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_allocated_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_allocated_1" >>>>>'
go 

create nonclustered index idx_allocated_1 
on omp.dbo.ompproj_20060421(allocated)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_remaining_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_remaining_1" >>>>>'
go 

create nonclustered index idx_remaining_1 
on omp.dbo.ompproj_20060421(remaining)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_telescope_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_telescope_1" >>>>>'
go 

create nonclustered index idx_telescope_1 
on omp.dbo.ompproj_20060421(telescope)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_pending_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_pending_1" >>>>>'
go 

create nonclustered index idx_pending_1 
on omp.dbo.ompproj_20060421(pending)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompprojaffiliation'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompprojaffiliation" >>>>>'
go

setuser 'dbo'
go 

create table ompprojaffiliation (
	projectid                       varchar(32)                      not null,
	affiliation                     varchar(32)                      not null,
	fraction                        real                             not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'ompprojaffiliation_proj_aff'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "ompprojaffiliation_proj_aff" >>>>>'
go 

create unique nonclustered index ompprojaffiliation_proj_aff 
on omp.dbo.ompprojaffiliation(projectid, affiliation)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompprojqueue'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompprojqueue" >>>>>'
go

setuser 'dbo'
go 

create table ompprojqueue (
	uniqid                          numeric(9,0)                     identity,
	projectid                       varchar(32)                      not null,
	country                         varchar(32)                      not null,
	tagpriority                     int                              not null,
	isprimary                       bit                              not null,
	tagadj                          int                              not null 
)
lock allpages
with identity_gap = 1, dml_logging = full
 on 'default'
partition by roundrobin 1
go 

Grant Select on dbo.ompprojqueue to casu Granted by dbo
go
Grant Select on dbo.ompprojqueue to staff Granted by dbo
go
Grant Select on dbo.ompprojqueue to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_country'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_country" >>>>>'
go 

create nonclustered index idx_country 
on omp.dbo.ompprojqueue(country)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_tagpriority'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_tagpriority" >>>>>'
go 

create nonclustered index idx_tagpriority 
on omp.dbo.ompprojqueue(tagpriority)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_projectid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_projectid" >>>>>'
go 

create nonclustered index idx_projectid 
on omp.dbo.ompprojqueue(projectid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_tagadj'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_tagadj" >>>>>'
go 

create nonclustered index idx_tagadj 
on omp.dbo.ompprojqueue(tagadj)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompprojqueue_2'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompprojqueue_2" >>>>>'
go

setuser 'dbo'
go 

create table ompprojqueue_2 (
	uniqid                          numeric(9,0)                     identity,
	projectid                       varchar(32)                      not null,
	country                         varchar(32)                      not null,
	tagpriority                     int                              not null,
	isprimary                       bit                              not null,
	tagadj                          int                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompprojqueue_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompprojqueue_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompprojqueue_20060421 (
	uniqid                          numeric(9,0)                     identity,
	projectid                       varchar(32)                      not null,
	country                         varchar(32)                      not null,
	tagpriority                     int                              not null,
	isprimary                       bit                              not null,
	tagadj                          int                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_country'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_country" >>>>>'
go 

create nonclustered index idx_country 
on omp.dbo.ompprojqueue_20060421(country)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_tagpriority'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_tagpriority" >>>>>'
go 

create nonclustered index idx_tagpriority 
on omp.dbo.ompprojqueue_20060421(tagpriority)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_projectid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_projectid" >>>>>'
go 

create nonclustered index idx_projectid 
on omp.dbo.ompprojqueue_20060421(projectid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'idx_tagadj'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_tagadj" >>>>>'
go 

create nonclustered index idx_tagadj 
on omp.dbo.ompprojqueue_20060421(tagadj)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompprojuser'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompprojuser" >>>>>'
go

setuser 'dbo'
go 

create table ompprojuser (
	uniqid                          numeric(9,0)                     identity,
	projectid                       varchar(32)                      not null,
	userid                          varchar(32)                      not null,
	capacity                        varchar(16)                      not null,
	contactable                     bit                              not null,
	capacity_order                  tinyint                         DEFAULT  0 
  not null,
 PRIMARY KEY NONCLUSTERED ( projectid, userid, capacity )  on 'default' 
)
lock allpages
with identity_gap = 1, dml_logging = full
 on 'default'
go 

Grant Select on dbo.ompprojuser to staff Granted by dbo
go
Grant Select on dbo.ompprojuser to russell Granted by dbo
go
Grant Select on dbo.ompprojuser to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_ompprojuser_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_ompprojuser_1" >>>>>'
go 

create unique clustered index idx_ompprojuser_1 
on omp.dbo.ompprojuser(uniqid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompprojuser_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompprojuser_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompprojuser_20060421 (
	uniqid                          numeric(9,0)                     identity,
	projectid                       varchar(32)                      not null,
	userid                          varchar(32)                      not null,
	capacity                        varchar(16)                      not null,
	contactable                     bit                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompprojuser_order'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompprojuser_order" >>>>>'
go

setuser 'dbo'
go 

create table ompprojuser_order (
	uniqid                          numeric(9,0)                     identity,
	projectid                       varchar(32)                      not null,
	userid                          varchar(32)                      not null,
	capacity                        varchar(16)                      not null,
	contactable                     bit                              not null,
	capacity_order                  tinyint                         DEFAULT   0 
  not null,
 PRIMARY KEY NONCLUSTERED ( projectid, userid, capacity )  on 'default' 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_uniqid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_uniqid" >>>>>'
go 

create unique clustered index idx_uniqid 
on omp.dbo.ompprojuser_order(uniqid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompsciprog'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompsciprog" >>>>>'
go

setuser 'dbo'
go 

create table ompsciprog (
	projectid                       varchar(32)                      not null,
	timestamp                       int                              not null,
	sciprog                         text                             not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

sp_placeobject 'default', 'dbo.ompsciprog.tompsciprog'
go 

Grant Select on dbo.ompsciprog to staff Granted by dbo
go
Grant Select on dbo.ompsciprog to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompsciprog_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompsciprog_id" >>>>>'
go

setuser 'dbo'
go 

create table ompsciprog_id (
	projectid                       varchar(32)                      not null,
	timestamp                       int                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompsciprog_omp1_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompsciprog_omp1_id" >>>>>'
go

setuser 'dbo'
go 

create table ompsciprog_omp1_id (
	projectid                       varchar(32)                      not null,
	timestamp                       int                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompshiftlog'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompshiftlog" >>>>>'
go

setuser 'dbo'
go 

create table ompshiftlog (
	shiftid                         numeric(9,0)                     identity,
	date                            datetime                         not null,
	author                          varchar(32)                      not null,
	telescope                       varchar(32)                      not null,
	text                            text                             not null,
 PRIMARY KEY CLUSTERED ( date, author, telescope )  on 'default' 
)
lock allpages
with identity_gap = 1, dml_logging = full
 on 'default'
go 

sp_placeobject 'default', 'dbo.ompshiftlog.tompshiftlog'
go 

Grant Select on dbo.ompshiftlog to casu Granted by dbo
go
Grant Select on dbo.ompshiftlog to staff Granted by dbo
go
Grant Select on dbo.ompshiftlog to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_ompshiftlog_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_ompshiftlog_1" >>>>>'
go 

create unique nonclustered index idx_ompshiftlog_1 
on omp.dbo.ompshiftlog(shiftid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompshiftlog_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompshiftlog_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompshiftlog_20060421 (
	shiftid                         numeric(9,0)                     identity,
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

sp_placeobject 'default', 'dbo.ompshiftlog_20060421.tompshiftlog_20060421'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompshiftlog_id'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompshiftlog_id" >>>>>'
go

setuser 'dbo'
go 

create table ompshiftlog_id (
	shiftid                         numeric(9,0)                     identity 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.omptimeacct'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.omptimeacct" >>>>>'
go

setuser 'dbo'
go 

create table omptimeacct (
	date                            datetime                         not null,
	projectid                       varchar(32)                      not null,
	timespent                       int                              not null,
	confirmed                       bit                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 

Grant Select on dbo.omptimeacct to casu Granted by dbo
go
Grant Select on dbo.omptimeacct to staff Granted by dbo
go
Grant Select on dbo.omptimeacct to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_date_proj'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_date_proj" >>>>>'
go 

create unique nonclustered index idx_date_proj 
on omp.dbo.omptimeacct(date, projectid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.omptimeacct_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.omptimeacct_20060421" >>>>>'
go

setuser 'dbo'
go 

create table omptimeacct_20060421 (
	date                            datetime                         not null,
	projectid                       varchar(32)                      not null,
	timespent                       int                              not null,
	confirmed                       bit                              not null 
)
lock allpages
with dml_logging = full
 on 'default'
partition by roundrobin 1
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.omptle'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.omptle" >>>>>'
go

setuser 'dbo'
go 

create table omptle (
	target                          varchar(32)                      not null,
	el1                             float(16)                        not null,
	el2                             float(16)                        not null,
	el3                             float(16)                        not null,
	el4                             float(16)                        not null,
	el5                             float(16)                        not null,
	el6                             float(16)                        not null,
	el7                             float(16)                        not null,
	el8                             float(16)                        not null,
	retrieved                       datetime                        DEFAULT  getdate() 
  not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.omptle to staff Granted by dbo
go
Grant Select on dbo.omptle to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'tle_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "tle_idx" >>>>>'
go 

create unique clustered index tle_idx 
on omp.dbo.omptle(target)
go 


-----------------------------------------------------------------------------
-- DDL for Trigger 'omp.dbo.retrieved_update'
-----------------------------------------------------------------------------

print '<<<<< CREATING Trigger - "omp.dbo.retrieved_update" >>>>>'
go 

setuser 'dbo'
go 


create trigger retrieved_update on omptle for update as
    update omptle
    set retrieved = getdate()
    from omptle t , inserted i
    where t.target = i.target

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompuser'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompuser" >>>>>'
go

setuser 'dbo'
go 

create table ompuser (
	userid                          varchar(32)                      not null,
	uname                           varchar(255)                     not null,
	email                           varchar(64)                          null,
	alias                           varchar(32)                          null,
	cadcuser                        varchar(20)                          null,
	obfuscated                      bit                             DEFAULT  0

  not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.ompuser to staff Granted by dbo
go
Grant Select on dbo.ompuser to russell Granted by dbo
go
Grant Select on dbo.ompuser to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'idx_ompuser_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "idx_ompuser_1" >>>>>'
go 

create unique clustered index idx_ompuser_1 
on omp.dbo.ompuser(userid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.ompuser_20060421'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.ompuser_20060421" >>>>>'
go

setuser 'dbo'
go 

create table ompuser_20060421 (
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
-- DDL for Table 'omp.dbo.rs_lastcommit'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.rs_lastcommit" >>>>>'
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

Grant Delete Statistics on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Truncate Table on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Update Statistics on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Transfer Table on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant References on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Select on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Insert on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Delete on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Update on dbo.rs_lastcommit to omp_maint Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'rs_lastcommit_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "rs_lastcommit_idx" >>>>>'
go 

create unique clustered index rs_lastcommit_idx 
on omp.dbo.rs_lastcommit(origin)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.rs_threads'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.rs_threads" >>>>>'
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
on omp.dbo.rs_threads(id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.rs_ticket_history'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.rs_ticket_history" >>>>>'
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
Grant Transfer Table on dbo.rs_ticket_history to public Granted by dbo
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
on omp.dbo.rs_ticket_history(cnt)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'omp.dbo.semester_dates'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "omp.dbo.semester_dates" >>>>>'
go

setuser 'dbo'
go 

create table semester_dates (
	semester                        varchar(10)                      not null,
	telescope                       varchar(6)                       not null,
	start_date                      date                             not null,
	end_date                        date                                 null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.semester_dates to staff Granted by dbo
go
Grant Select on dbo.semester_dates to datareader Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'sem_tel_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "sem_tel_idx" >>>>>'
go 

create unique clustered index sem_tel_idx 
on omp.dbo.semester_dates(semester, telescope)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'sem_start_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "sem_start_idx" >>>>>'
go 

create nonclustered index sem_start_idx 
on omp.dbo.semester_dates(start_date)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'sem_end_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "sem_end_idx" >>>>>'
go 

create nonclustered index sem_end_idx 
on omp.dbo.semester_dates(end_date)
go 


-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'omp.dbo.ompfindtarget'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.ompfindtarget" >>>>>'
go 

setuser 'dbo'
go 

create procedure ompfindtarget
(    @ra        varchar(16) = "", 
    @dec        varchar(16) = "",
    @sep        real = 600,
    @proj       varchar(32) = '%',
    @sem        varchar(10) = '%',
    @tel        varchar(16) = '%' )
as
/* 
** Sql to find observations within a radius around a reference Ra-Dec
** position or around targets from a reference project.
** The position must be in J2000. Default radius is 10 arcmin (600") 
**
** Usage:     exec ompfindtarget @ra="hh mm ss",@dec="dd mm ss",@sep=600
**                 [,@proj='%'] [,@sem='%'] [,@tel='%']
**
** Examples:
**            exec ompfindtarget @ra="09 27 46.7", @dec="-06 04 16",
**                               @sep=60, @tel='UKIRT'
**
**            exec ompfindtarget @proj="U/07A/3", @sep=60, @tel='UKIRT', 
**                               @sem='07A'
**
*/
  declare @ra_rad float, @dec_rad float, @hh int, @mm int, @ss real,
          @sign int, @dd int, @am int, @as real, 
          @rdum varchar(16), @ddum varchar(16), @ref varchar(22),
          @sep_rad real, @HPI real, @deg2rad real

  select @HPI = 2.0*atan(1.0), @deg2rad = 4.0*atan(1.0)/180.0

  select @sep_rad = @sep/3600*@deg2rad

  if (@proj = '%')
    begin 

      if (@ra = "" or @dec = "")
      begin
        print "ERROR: ra and/or dec invalid"
        return(-1)
      end

      select @rdum = ltrim(@ra), @ddum = ltrim(@dec), @sign = 1
 
      if (charindex("-",@ddum) = 1) 
      begin
        select @sign = -1, @ddum = substring(@ddum, 2, char_length(@ddum)-1)
      end

      select @hh = convert(int,substring(@rdum, 1, charindex(" ",@rdum)-1)), 
         @rdum = substring(@rdum, charindex(" ",@rdum)+1, char_length(@rdum)),
         @dd = convert(int,substring(@ddum, 1, charindex(" ",@ddum)-1)), 
         @ddum = substring(@ddum, charindex(" ",@ddum)+1, char_length(@ddum))
      select @mm = convert(int,substring(@rdum, 1, charindex(" ",@rdum)-1)), 
         @rdum = substring(@rdum, charindex(" ",@rdum)+1, char_length(@rdum)),
         @am = convert(int,substring(@ddum, 1, charindex(" ",@ddum)-1)), 
         @ddum = substring(@ddum, charindex(" ",@ddum)+1, char_length(@ddum))
      select @ss = convert(real,@rdum), @as = convert(real,@ddum)
      select @sep_rad = @sep/3600*@deg2rad

      select @ra_rad  = 15.0* (@hh+@mm/60.0+@ss/3600.0)*@deg2rad,
            @dec_rad = @sign*(@dd+@am/60.0+@as/3600.0)*@deg2rad

      select @ref = substring(convert(char(24),@ra_rad),1,10) + " " +
                    substring(convert(char(24),@dec_rad),1,11)

      SELECT distinct reference = @ref, P.projectid, target2 = Q.target, 
           separation =
           3600.0/@deg2rad*abs(acos(round(
             cos(@HPI-@dec_rad)*cos(@HPI-dec2000)+
             sin(@HPI-@dec_rad)*sin(@HPI-dec2000)*cos(@ra_rad-ra2000),
           12))),
           Q.ra2000, Q.dec2000, Q.instrument
         from ompproj P, ompmsb M, ompobs Q
         where P.projectid not like '%EC%'
         and M.projectid = P.projectid
         and M.msbid = Q.msbid
         and P.telescope like @tel
         and P.semester like @sem
         and coordstype = 'RADEC' and state=1
         and abs(acos(round(
             cos(@HPI-@dec_rad)*cos(@HPI-dec2000)+
             sin(@HPI-@dec_rad)*sin(@HPI-dec2000)*cos(@ra_rad-ra2000),
           12))) < @sep_rad
         order by Q.target

    end
  else
    begin

      if (@proj = "")
      begin
        print "ERROR: projectid string empty"
        return(-1)
      end

      SELECT distinct reference = convert(varchar(24),Q2.target), P.projectid,
           target = Q.target, separation = 
           3600.0/@deg2rad*abs(acos(round(
             cos(@HPI-Q2.dec2000)*cos(@HPI-Q.dec2000)+
             sin(@HPI-Q2.dec2000)*sin(@HPI-Q.dec2000)*cos(Q2.ra2000-Q.ra2000),
           12))),
         Q.ra2000, Q.dec2000, Q.instrument
         from ompproj P, ompmsb M, ompobs Q,
              ompproj P2, ompmsb M2, ompobs Q2
         where P2.projectid like @proj
         and M2.projectid = P2.projectid
         and Q2.msbid = M2.msbid
         and P2.telescope like @tel
         and P2.semester like @sem
         and Q2.coordstype = 'RADEC'
         and P.projectid not like P2.projectid
         and P.projectid not like '%EC%'
         and M.projectid = P.projectid
         and Q.msbid = M.msbid
         and P.telescope like @tel
         and P.semester like @sem
         and Q.coordstype = 'RADEC' and P.state=1
         and abs(acos(round(
             cos(@HPI-Q2.dec2000)*cos(@HPI-Q.dec2000)+
             sin(@HPI-Q2.dec2000)*sin(@HPI-Q.dec2000)*cos(Q2.ra2000-Q.ra2000),
           12))) < @sep_rad
         order by Q2.target

    end

  return(0)

go 

Grant Execute on dbo.ompfindtarget to public Granted by dbo
go

sp_procxmode 'ompfindtarget', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'omp.dbo.rs_check_repl_stat'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.rs_check_repl_stat" >>>>>'
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

Grant Execute on dbo.rs_check_repl_stat to public Granted by dbo
go

sp_procxmode 'rs_check_repl_stat', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'omp.dbo.rs_get_lastcommit'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.rs_get_lastcommit" >>>>>'
go 

setuser 'dbo'
go 


/* Create the procedure to get the last commit for all origins. */
create procedure rs_get_lastcommit
as
	select origin, origin_qid, secondary_qid
		from rs_lastcommit
 
go 

Grant Execute on dbo.rs_get_lastcommit to omp_maint Granted by dbo
go

sp_procxmode 'rs_get_lastcommit', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'omp.dbo.rs_initialize_threads'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.rs_initialize_threads" >>>>>'
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
-- DDL for Stored Procedure 'omp.dbo.rs_marker'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.rs_marker" >>>>>'
go 

setuser 'dbo'
go 


/* Create the procedure which marks the log when a subscription is created. */

create procedure rs_marker 
	@rs_api varchar(16383)
as
	/* Setup the bit that reflects a SQL Server replicated object. */
	declare	@rep_constant	smallint
	select @rep_constant = -32768

	/* First make sure that this procedure is marked as replicated! */
	if not exists (select sysstat
			from sysobjects
			where name = 'rs_marker'
				and type = 'P'
				and sysstat & @rep_constant != 0)
	begin
		print "Have your DBO execute 'sp_setreplicate' on the procedure 'rs_marker'"
		return(1)
	end

	/*
	** There is nothing else to do in this procedure. It's execution
	** should have been logged into the transaction log and picked up
	** by the SQL Server LTM.
	*/
 
go 

Grant Execute on dbo.rs_marker to public Granted by dbo
go

sp_procxmode 'rs_marker', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'omp.dbo.rs_send_repserver_cmd'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.rs_send_repserver_cmd" >>>>>'
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
-- DDL for Stored Procedure 'omp.dbo.rs_ticket'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.rs_ticket" >>>>>'
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
** rs_ticket parameter Canonical Form:
**   rs_ticket_param ::= <stamp> | <rs_ticket_param>;<stamp>
**   stamp           ::= <tag>=<value> | <tag>(info)=<value>
**   tag             ::= V | H | PDB | EXEC | B | DIST | DSI | RDB | ...
**   info            ::= Spid | PDB name
**   value           ::= integer | string | mm/dd/yy hh:mm:ss.ddd
**
** rs_ticket tag:
**   V:     Version number. Version 2 adds date and a few other tags.
**   Hx:    Headers for identifying one or a set of tickets.
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
**   1. Don't mark rs_ticket for replication.
**   2. Headers must be 10 character or less.
**   3. For more than 4 headers, passing something like
**        "four;H5=five;H6=six..."
**   4. Don't pass too many headers. rs_ticket_param must be less 1024.
**   5. Use only [A-Za-z0-9;:._]. Never use ['"] in ticket.
**   6. Repserver accepts tickets with any version number.
**   7. Version > 1 ticket will include date information.
**   8. Version > 1 ticket will include RSI information.
**   9. Version > 1 ticket will include Repserver names.
**  10. Version > 1 ticket will include DSI_T and DSI_C tag.
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
-- DDL for Stored Procedure 'omp.dbo.rs_ticket_report'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.rs_ticket_report" >>>>>'
go 

setuser 'dbo'
go 


/*
** Name: rs_ticket_report
**   Append PDB timestamp to rs_ticket_param.
**   Repserver rs_ticket_report function string can be modified
**	to call this stored proceudre to process ticket.
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
	@c_time	 datetime

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
-- DDL for Stored Procedure 'omp.dbo.rs_ticket_v1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.rs_ticket_v1" >>>>>'
go 

setuser 'dbo'
go 


/*
** Name: rs_ticket_v1
**   Version one rs_ticket
**
** Parameter
**   head1: the first header. Default is "ticket"
**   head2: the second header. Default is null.
**   head3: the third header. Default is null.
**   head4: the last header. Default is null.
**
** Note:
**   1. Use rs_ticket_v1 to issue version one ticket.
**   2. Repserver accepts tickets with any version number.
**   3. Version one ticket will not have date information.
**   4. Version one ticket will not have RSI information.
**   5. Version one ticket will not have Repserver names.
**   6. Version one ticket will not have DSI_T and DSI_C tag.
*/
create procedure rs_ticket_v1
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
-- DDL for Stored Procedure 'omp.dbo.rs_update_lastcommit'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.rs_update_lastcommit" >>>>>'
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

Grant Execute on dbo.rs_update_lastcommit to public Granted by dbo
go

sp_procxmode 'rs_update_lastcommit', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'omp.dbo.rs_update_threads'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "omp.dbo.rs_update_threads" >>>>>'
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
use omp
go 

sp_addthreshold omp, 'logsegment', 1680352, sp_thresholdaction
go 

sp_addthreshold omp, 'logsegment', 1336320, sp_thresholdaction
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
Grant Execute on dbo.ompfindtarget to public Granted by dbo
go
Grant Select on dbo.rs_threads to public Granted by dbo
go
Grant Execute on dbo.rs_update_lastcommit to public Granted by dbo
go
Grant Execute on dbo.rs_update_threads to public Granted by dbo
go
Grant Execute on dbo.rs_initialize_threads to public Granted by dbo
go
Grant Execute on dbo.rs_marker to public Granted by dbo
go
Grant Execute on dbo.rs_check_repl_stat to public Granted by dbo
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
Grant Transfer Table on dbo.rs_ticket_history to public Granted by dbo
go
Grant Execute on dbo.rs_ticket to public Granted by dbo
go
Grant Execute on dbo.rs_ticket_v1 to public Granted by dbo
go
Grant Execute on dbo.rs_ticket_report to public Granted by dbo
go
Grant Select on dbo.ompmsb to casu Granted by dbo
go
Grant Select on dbo.ompmsbdone to casu Granted by dbo
go
Grant Select on dbo.ompobs to casu Granted by dbo
go
Grant Select on dbo.ompobslog to casu Granted by dbo
go
Grant Select on dbo.ompproj to casu Granted by dbo
go
Grant Select on dbo.ompshiftlog to casu Granted by dbo
go
Grant Select on dbo.omptimeacct to casu Granted by dbo
go
Grant Select on dbo.ompprojqueue to casu Granted by dbo
go
Grant Select on dbo.ompfeedback to casu Granted by dbo
go
Grant Select on dbo.ompfaultbody_id to datareader Granted by dbo
go
Grant Select on dbo.ompkey to datareader Granted by dbo
go
Grant Select on dbo.devprojuser to datareader Granted by dbo
go
Grant Select on dbo.ompsciprog to datareader Granted by dbo
go
Grant Select on dbo.omptle to datareader Granted by dbo
go
Grant Select on dbo.semester_dates to datareader Granted by dbo
go
Grant Select on dbo.ompfaultbody_compare to datareader Granted by dbo
go
Grant Select on dbo.ompfault to datareader Granted by dbo
go
Grant Select on dbo.ompfaultassoc to datareader Granted by dbo
go
Grant Select on dbo.ompfaultbody to datareader Granted by dbo
go
Grant Select on dbo.ompmsb to datareader Granted by dbo
go
Grant Select on dbo.ompmsbdone to datareader Granted by dbo
go
Grant Select on dbo.ompobs to datareader Granted by dbo
go
Grant Select on dbo.ompobslog to datareader Granted by dbo
go
Grant Select on dbo.ompproj to datareader Granted by dbo
go
Grant Select on dbo.ompshiftlog to datareader Granted by dbo
go
Grant Select on dbo.omptimeacct to datareader Granted by dbo
go
Grant Select on dbo.ompuser to datareader Granted by dbo
go
Grant Select on dbo.ompprojqueue to datareader Granted by dbo
go
Grant Select on dbo.ompprojuser to datareader Granted by dbo
go
Grant Select on dbo.ompfeedback to datareader Granted by dbo
go
Grant References on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Select on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Insert on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Delete on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Update on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Delete Statistics on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Truncate Table on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Update Statistics on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Transfer Table on dbo.rs_lastcommit to omp_maint Granted by dbo
go
Grant Execute on dbo.rs_get_lastcommit to omp_maint Granted by dbo
go
Grant Select on dbo.ompproj to russell Granted by dbo
go
Grant Select on dbo.ompuser to russell Granted by dbo
go
Grant Select on dbo.ompprojuser to russell Granted by dbo
go
Grant Select on dbo.ompkey to staff Granted by dbo
go
Grant Select on dbo.ompsciprog to staff Granted by dbo
go
Grant Select on dbo.omptle to staff Granted by dbo
go
Grant Select on dbo.semester_dates to staff Granted by dbo
go
Grant Select on dbo.ompfault to staff Granted by dbo
go
Grant Select on dbo.ompfaultassoc to staff Granted by dbo
go
Grant Select on dbo.ompfaultbody to staff Granted by dbo
go
Grant Select on dbo.ompmsb to staff Granted by dbo
go
Grant Select on dbo.ompmsbdone to staff Granted by dbo
go
Grant Select on dbo.ompobs to staff Granted by dbo
go
Grant Select on dbo.ompobslog to staff Granted by dbo
go
Grant Select on dbo.ompproj to staff Granted by dbo
go
Grant Select on dbo.ompshiftlog to staff Granted by dbo
go
Grant Select on dbo.omptimeacct to staff Granted by dbo
go
Grant Select on dbo.ompuser to staff Granted by dbo
go
Grant Select on dbo.ompprojqueue to staff Granted by dbo
go
Grant Select on dbo.ompprojuser to staff Granted by dbo
go
Grant Select on dbo.ompfeedback to staff Granted by dbo
go
exec sp_addalias 'omp', 'dbo'
go 

exec sp_addalias 'jcmtmd_maint', 'dbo'
go 



-- DDLGen Completed
-- at 12/06/17 9:38:26 HST