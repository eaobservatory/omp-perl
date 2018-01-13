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
-- -S SYB_JAC -I /opt2/sybase/ase-15.0/interfaces -P*** -U sa -O ddl/ukirt.ddl -L ukirt.progress.2017-1206-0938 -T DB -N ukirt 
-- at 12/06/17 9:38:27 HST


USE master
go


PRINT "<<<< CREATE DATABASE ukirt>>>>"
go


IF EXISTS (SELECT 1 FROM master.dbo.sysdatabases
	   WHERE name = 'ukirt')
	DROP DATABASE ukirt
go


IF (@@error != 0)
BEGIN
	PRINT "Error dropping database 'ukirt'"
	SELECT syb_quit()
END
go


CREATE DATABASE ukirt
	    ON dev_ukirt_db_0 = '6000M' -- 3072000 pages
	LOG ON dev_ukirt_db_0 = '600M' -- 307200 pages
WITH OVERRIDE
   , DURABILITY = FULL
go


ALTER DATABASE ukirt
	    ON dev_ukirt_db_0 = '3640M' -- 1863680 pages
	     , dev_ukirt_db_1 = '3072M' -- 1572864 pages
	     , dev_ukirt_log_0 = '88M' -- 45056 pages
	     , dev_ukirt_log_0 = '612M' -- 313344 pages
go


use ukirt
go

exec sp_changedbowner 'sa', true 
go

exec master.dbo.sp_dboption ukirt, 'abort tran on log full', true
go

checkpoint
go


-----------------------------------------------------------------------------
-- DDL for User 'guest'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "guest" >>>>>'
go 

exec sp_adduser 'guest'
go 


-----------------------------------------------------------------------------
-- DDL for User 'arc'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "arc" >>>>>'
go 

exec sp_adduser 'arc' ,'arc' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for User 'datareader'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "datareader" >>>>>'
go 

exec sp_adduser 'datareader' ,'datareader' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for User 'staff'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "staff" >>>>>'
go 

exec sp_adduser 'staff' ,'staff' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for User 'ukirt_arch'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "ukirt_arch" >>>>>'
go 

exec sp_adduser 'ukirt_arch' ,'ukirt_arch' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for User 'visitor'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "visitor" >>>>>'
go 

exec sp_adduser 'visitor' ,'visitor' ,'public'
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.CGS4'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.CGS4" >>>>>'
go

use ukirt
go 

setuser 'dbo'
go 

create table CGS4 (
	idkey                           numeric(18,0)                    not null,
	CLOCK0                          float(16)                            null,
	CLOCK1                          float(16)                            null,
	CLOCK2                          float(16)                            null,
	CLOCK3                          float(16)                            null,
	CLOCK4                          float(16)                            null,
	CLOCK5                          float(16)                            null,
	CLOCK6                          float(16)                            null,
	VSLEW                           float(16)                            null,
	VDET                            float(16)                            null,
	DET_BIAS                        float(16)                            null,
	VDDUC                           float(16)                            null,
	VDETGATE                        float(16)                            null,
	VGG_A                           float(16)                            null,
	VGG_INA                         float(16)                            null,
	VDDOUT                          float(16)                            null,
	V3                              float(16)                            null,
	VLCLR                           float(16)                            null,
	VLD_A                           float(16)                            null,
	VLD_INA                         float(16)                            null,
	WFREQ                           float(16)                            null,
	RESET_DL                        float(16)                            null,
	CHOP_DEL                        float(16)                            null,
	READ_INT                        float(16)                            null,
	NEXP_PH                         int                                  null,
	RDOUT_X1                        int                                  null,
	RDOUT_X2                        int                                  null,
	RDOUT_Y1                        int                                  null,
	RDOUT_Y2                        int                                  null,
	CHOPDIFF                        varchar(70)                          null,
	IF_SHARP                        varchar(70)                          null,
	LINEAR                          varchar(70)                          null,
	DETINCR                         float(16)                            null,
	DETNINCR                        float(16)                            null,
	WPLANGLE                        float(16)                            null,
	SANGLE                          float(16)                            null,
	SLIT                            varchar(70)                          null,
	SLENGTH                         float(16)                            null,
	SWIDTH                          float(16)                            null,
	DENCBASE                        int                                  null,
	DFOCUS                          float(16)                            null,
	GRATING                         varchar(70)                          null,
	GLAMBDA                         float(16)                            null,
	GANGLE                          float(16)                            null,
	GORDER                          int                                  null,
	GDISP                           float(16)                            null,
	CNFINDEX                        int                                  null,
	CVF                             varchar(70)                          null,
	CLAMBDA                         float(16)                            null,
	IRTANGLE                        float(16)                            null,
	LAMP                            varchar(70)                          null,
	BBTEMP                          float(16)                            null,
	CALAPER                         float(16)                            null,
	THLEVEL                         float(16)                            null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.CGS4 to public Granted by dbo
go
Grant Delete Statistics on dbo.CGS4 to arc Granted by dbo
go
Grant Truncate Table on dbo.CGS4 to arc Granted by dbo
go
Grant Update Statistics on dbo.CGS4 to arc Granted by dbo
go
Grant References on dbo.CGS4 to arc Granted by dbo
go
Grant Insert on dbo.CGS4 to arc Granted by dbo
go
Grant Delete on dbo.CGS4 to arc Granted by dbo
go
Grant Update on dbo.CGS4 to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'index_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_1" >>>>>'
go 

create unique clustered index index_1 
on ukirt.dbo.CGS4(idkey)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.COMMON'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.COMMON" >>>>>'
go

setuser 'dbo'
go 

create table COMMON (
	idkey                           numeric(18,0)                    not null,
	TELESCOP                        varchar(70)                          null,
	INSTRUME                        varchar(70)                      not null,
	OBSERVER                        varchar(70)                      not null,
	OBSREF                          varchar(70)                          null,
	DETECTOR                        varchar(70)                          null,
	OBJECT                          varchar(70)                      not null,
	OBSTYPE                         varchar(70)                          null,
	INTTYPE                         varchar(70)                          null,
	MODE                            varchar(70)                          null,
	UTDATE                          varchar(70)                          null,
	GRPNUM                          int                                  null,
	RUN                             int                              not null,
	EXPOSED                         float(16)                            null,
	OBJCLASS                        int                                  null,
	EQUINOX                         float(16)                            null,
	MEANRA                          float(16)                            null,
	MEANDEC                         float(16)                            null,
	RABASE                          float(16)                            null,
	DECBASE                         float(16)                            null,
	RAOFF                           float(16)                            null,
	DECOFF                          float(16)                            null,
	DROWS                           int                                  null,
	DCOLUMNS                        int                                  null,
	DEXPTIME                        float(16)                            null,
	DEPERDN                         float(16)                            null,
	IDATE                           int                                  null,
	OBSNUM                          int                                  null,
	NEXP                            int                                  null,
	AMSTART                         float(16)                            null,
	AMEND                           float(16)                            null,
	RUTSTART                        float(16)                            null,
	RUTEND                          float(16)                            null,
	FILTER                          varchar(70)                          null,
	FILTERS                         varchar(70)                          null,
	raj2000                         float(16)                            null,
	decj2000                        float(16)                            null,
	raj2000_int                     int                              not null,
	decj2000_int                    int                              not null,
	ut_dmf                          int                              not null,
	filename                        varchar(70)                      not null,
	UT_DATE                         datetime                             null,
	MSBID                           varchar(70)                          null,
	PROJECT                         varchar(70)                          null,
	STANDARD                        char(1)                              null,
	OBSID                           varchar(48)                          null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.COMMON to public Granted by dbo
go
Grant Delete Statistics on dbo.COMMON to arc Granted by dbo
go
Grant Truncate Table on dbo.COMMON to arc Granted by dbo
go
Grant Update Statistics on dbo.COMMON to arc Granted by dbo
go
Grant References on dbo.COMMON to arc Granted by dbo
go
Grant Insert on dbo.COMMON to arc Granted by dbo
go
Grant Delete on dbo.COMMON to arc Granted by dbo
go
Grant Update on dbo.COMMON to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'index_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_1" >>>>>'
go 

create unique clustered index index_1 
on ukirt.dbo.COMMON(idkey)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'index_2'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_2" >>>>>'
go 

create unique nonclustered index index_2 
on ukirt.dbo.COMMON(filename, INSTRUME)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'index_3'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_3" >>>>>'
go 

create nonclustered index index_3 
on ukirt.dbo.COMMON(ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'index_4'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_4" >>>>>'
go 

create nonclustered index index_4 
on ukirt.dbo.COMMON(decj2000_int)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'index_5'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_5" >>>>>'
go 

create nonclustered index index_5 
on ukirt.dbo.COMMON(raj2000_int)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'index_6'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_6" >>>>>'
go 

create nonclustered index index_6 
on ukirt.dbo.COMMON(IDATE)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'UT_DATE_in'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "UT_DATE_in" >>>>>'
go 

create nonclustered index UT_DATE_in 
on ukirt.dbo.COMMON(UT_DATE)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.IRCAM3'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.IRCAM3" >>>>>'
go

setuser 'dbo'
go 

create table IRCAM3 (
	idkey                           numeric(18,0)                    not null,
	CLOCK0                          float(16)                            null,
	CLOCK1                          float(16)                            null,
	CLOCK2                          float(16)                            null,
	CLOCK3                          float(16)                            null,
	CLOCK4                          float(16)                            null,
	CLOCK5                          float(16)                            null,
	CLOCK6                          float(16)                            null,
	VSLEW                           float(16)                            null,
	VDET                            float(16)                            null,
	DET_BIAS                        float(16)                            null,
	VDDUC                           float(16)                            null,
	VDETGATE                        float(16)                            null,
	VGG_A                           float(16)                            null,
	VGG_INA                         float(16)                            null,
	VDDOUT                          float(16)                            null,
	V3                              float(16)                            null,
	VLCLR                           float(16)                            null,
	VLD_A                           float(16)                            null,
	VLD_INA                         float(16)                            null,
	WFREQ                           float(16)                            null,
	RESET_DL                        float(16)                            null,
	CHOP_DEL                        float(16)                            null,
	READ_INT                        float(16)                            null,
	NEXP_PH                         int                                  null,
	RDOUT_X1                        int                                  null,
	RDOUT_X2                        int                                  null,
	RDOUT_Y1                        int                                  null,
	RDOUT_Y2                        int                                  null,
	CHOPDIFF                        varchar(70)                          null,
	IF_SHARP                        varchar(70)                          null,
	LINEAR                          varchar(70)                          null,
	FILTER1                         varchar(70)                          null,
	FILTER2                         varchar(70)                          null,
	MAGNIFIE                        varchar(70)                          null,
	PIXELSIZ                        float(16)                            null,
	DFOCUS                          float(16)                            null,
	STREDUCE                        varchar(70)                          null,
	DENCBASE                        int                                  null,
	DETINCR                         float(16)                            null,
	DETNINCR                        int                                  null,
	WPLANGLE                        float(16)                            null,
	CROTA2                          float(16)                            null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.IRCAM3 to public Granted by dbo
go
Grant Delete Statistics on dbo.IRCAM3 to arc Granted by dbo
go
Grant Truncate Table on dbo.IRCAM3 to arc Granted by dbo
go
Grant Update Statistics on dbo.IRCAM3 to arc Granted by dbo
go
Grant References on dbo.IRCAM3 to arc Granted by dbo
go
Grant Insert on dbo.IRCAM3 to arc Granted by dbo
go
Grant Delete on dbo.IRCAM3 to arc Granted by dbo
go
Grant Update on dbo.IRCAM3 to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'index_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_1" >>>>>'
go 

create unique clustered index index_1 
on ukirt.dbo.IRCAM3(idkey)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.MICHELLE'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.MICHELLE" >>>>>'
go

setuser 'dbo'
go 

create table MICHELLE (
	idkey                           numeric(18,0)                    not null,
	GRPMEM                          int                                  null,
	RDOUT_X1                        int                                  null,
	RDOUT_X2                        int                                  null,
	RDOUT_Y1                        int                                  null,
	RDOUT_Y2                        int                                  null,
	RECIPE                          varchar(70)                          null,
	INSTMODE                        varchar(70)                          null,
	GRISM                           varchar(70)                          null,
	GRISM1                          varchar(70)                          null,
	GRISM2                          varchar(70)                          null,
	SLITNAME                        varchar(70)                          null,
	LAMP                            varchar(70)                          null,
	CALAPER                         varchar(70)                          null,
	WAVEFORM                        varchar(70)                          null,
	USERID                          varchar(70)                          null,
	CTYPE1                          varchar(70)                          null,
	CTYPE2                          varchar(70)                          null,
	FILTER1                         varchar(70)                          null,
	FILTER2                         varchar(70)                          null,
	DATE_OBS                        varchar(70)                          null,
	DATE_END                        varchar(70)                          null,
	STANDARD                        char(1)                              null,
	POLARISE                        char(1)                              null,
	AIRTEMP                         float(16)                            null,
	TRUSSENE                        float(16)                            null,
	TRUSSWSW                        float(16)                            null,
	DOMETEMP                        float(16)                            null,
	HUMIDITY                        float(16)                            null,
	WINDSPD                         float(16)                            null,
	WINDDIR                         float(16)                            null,
	BBTEMP                          float(16)                            null,
	CAMLENS                         varchar(70)                          null,
	PIXLSIZE                        float(16)                            null,
	WPLANGLE                        float(16)                            null,
	CRVAL1                          float(16)                            null,
	CRVAL2                          float(16)                            null,
	CDELT1                          float(16)                            null,
	CDELT2                          float(16)                            null,
	CRPIX1                          float(16)                            null,
	CRPIX2                          float(16)                            null,
	GRATORD                         int                                  null,
	DETNINCR                        int                                  null,
	GRATNAME                        varchar(70)                          null,
	SAMPLING                        varchar(70)                          null,
	OBSTIME                         float(16)                            null,
	GRATPOS                         float(16)                            null,
	GRATDISP                        float(16)                            null,
	SLITANG                         float(16)                            null,
	IRDEG                           float(16)                            null,
	DETINCR                         float(16)                            null,
	CROTA2                          float(16)                            null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.MICHELLE to public Granted by dbo
go
Grant Delete Statistics on dbo.MICHELLE to arc Granted by dbo
go
Grant Truncate Table on dbo.MICHELLE to arc Granted by dbo
go
Grant Update Statistics on dbo.MICHELLE to arc Granted by dbo
go
Grant References on dbo.MICHELLE to arc Granted by dbo
go
Grant Insert on dbo.MICHELLE to arc Granted by dbo
go
Grant Delete on dbo.MICHELLE to arc Granted by dbo
go
Grant Update on dbo.MICHELLE to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'index_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_1" >>>>>'
go 

create unique clustered index index_1 
on ukirt.dbo.MICHELLE(idkey)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.UFTI'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.UFTI" >>>>>'
go

setuser 'dbo'
go 

create table UFTI (
	idkey                           numeric(18,0)                    not null,
	RDOUT_X1                        int                                  null,
	RDOUT_X2                        int                                  null,
	RDOUT_Y1                        int                                  null,
	RDOUT_Y2                        int                                  null,
	FP_X                            int                                  null,
	FP_Y                            int                                  null,
	FP_Z                            int                                  null,
	NAXIS                           int                                  null,
	GRPMEM                          int                                  null,
	SIMPLE                          int                                  null,
	GRPMAX                          int                                  null,
	NAXIS1                          int                                  null,
	NAXIS2                          int                                  null,
	BITPIX                          int                                  null,
	BLACKLEV                        int                                  null,
	EXTEND                          int                                  null,
	DCS_GAIN                        int                                  null,
	ORIGIN                          varchar(70)                          null,
	USERID                          varchar(70)                          null,
	SPD_GAIN                        varchar(70)                          null,
	BUNIT                           varchar(70)                          null,
	FILTER1                         varchar(70)                          null,
	FILTER2                         varchar(70)                          null,
	CUNIT1                          varchar(70)                          null,
	CUNIT2                          varchar(70)                          null,
	CTYPE1                          varchar(70)                          null,
	CTYPE2                          varchar(70)                          null,
	RECIPE                          varchar(70)                          null,
	DATE                            varchar(70)                          null,
	DATE_OBS                        varchar(70)                          null,
	DATE_END                        varchar(70)                          null,
	WPLANGLE                        float(16)                            null,
	TFOCUS                          float(16)                            null,
	BZERO                           float(16)                            null,
	BSCALE                          float(16)                            null,
	CRPIX1                          float(16)                            null,
	CRPIX2                          float(16)                            null,
	CRVAL1                          float(16)                            null,
	CRVAL2                          float(16)                            null,
	CDELT1                          float(16)                            null,
	CDELT2                          float(16)                            null,
	USPPIXEL                        float(16)                            null,
	INT_TIME                        float(16)                            null,
	TEMP_TAB                        float(16)                            null,
	DOMETEMP                        float(16)                            null,
	TEMP_ARR                        float(16)                            null,
	TEMP_ST1                        float(16)                            null,
	TEMP_ST2                        float(16)                            null,
	HUMIDITY                        float(16)                            null,
	WIND_SPD                        float(16)                            null,
	AIR_TEMP                        float(16)                            null,
	TRUSSENE                        float(16)                            null,
	TRUSSWSW                        float(16)                            null,
	WIND_DIR                        float(16)                            null,
	DCSSPEED                        float(16)                            null,
	CROTA2                          float(16)                            null,
	V1                              float(16)                            null,
	V2                              float(16)                            null,
	V3                              float(16)                            null,
	V4                              float(16)                            null,
	V5                              float(16)                            null,
	V6                              float(16)                            null,
	V7                              float(16)                            null,
	V8                              float(16)                            null,
	V13                             float(16)                            null,
	V15                             float(16)                            null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.UFTI to public Granted by dbo
go
Grant Delete Statistics on dbo.UFTI to arc Granted by dbo
go
Grant Truncate Table on dbo.UFTI to arc Granted by dbo
go
Grant Update Statistics on dbo.UFTI to arc Granted by dbo
go
Grant References on dbo.UFTI to arc Granted by dbo
go
Grant Insert on dbo.UFTI to arc Granted by dbo
go
Grant Delete on dbo.UFTI to arc Granted by dbo
go
Grant Update on dbo.UFTI to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'index_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_1" >>>>>'
go 

create unique clustered index index_1 
on ukirt.dbo.UFTI(idkey)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.UIST'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.UIST" >>>>>'
go

setuser 'dbo'
go 

create table UIST (
	idkey                           numeric(18,0)                    not null,
	GRPMEM                          int                                  null,
	RDOUT_X1                        int                                  null,
	RDOUT_X2                        int                                  null,
	RDOUT_Y1                        int                                  null,
	RDOUT_Y2                        int                                  null,
	RECIPE                          varchar(70)                          null,
	INSTMODE                        varchar(70)                          null,
	GRISM                           varchar(70)                          null,
	GRISM1                          varchar(70)                          null,
	GRISM2                          varchar(70)                          null,
	SLITNAME                        varchar(70)                          null,
	LAMP                            varchar(70)                          null,
	CALAPER                         varchar(70)                          null,
	WAVEFORM                        varchar(70)                          null,
	USERID                          varchar(70)                          null,
	CTYPE1                          varchar(70)                          null,
	CTYPE2                          varchar(70)                          null,
	FILTER1                         varchar(70)                          null,
	FILTER2                         varchar(70)                          null,
	DATE_OBS                        varchar(70)                          null,
	DATE_END                        varchar(70)                          null,
	STANDARD                        char(1)                              null,
	POLARISE                        char(1)                              null,
	AIRTEMP                         float(16)                            null,
	TRUSSENE                        float(16)                            null,
	TRUSSWSW                        float(16)                            null,
	DOMETEMP                        float(16)                            null,
	HUMIDITY                        float(16)                            null,
	WINDSPD                         float(16)                            null,
	WINDDIR                         float(16)                            null,
	BBTEMP                          float(16)                            null,
	CAMLENS                         varchar(70)                          null,
	PIXLSIZE                        float(16)                            null,
	WPLANGLE                        float(16)                            null,
	CRVAL1                          float(16)                            null,
	CRVAL2                          float(16)                            null,
	CDELT1                          float(16)                            null,
	CDELT2                          float(16)                            null,
	CRPIX1                          float(16)                            null,
	CRPIX2                          float(16)                            null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.UIST to public Granted by dbo
go
Grant Delete Statistics on dbo.UIST to arc Granted by dbo
go
Grant Truncate Table on dbo.UIST to arc Granted by dbo
go
Grant Update Statistics on dbo.UIST to arc Granted by dbo
go
Grant References on dbo.UIST to arc Granted by dbo
go
Grant Insert on dbo.UIST to arc Granted by dbo
go
Grant Delete on dbo.UIST to arc Granted by dbo
go
Grant Update on dbo.UIST to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'index_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_1" >>>>>'
go 

create unique clustered index index_1 
on ukirt.dbo.UIST(idkey)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.WFCAM'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.WFCAM" >>>>>'
go

setuser 'dbo'
go 

create table WFCAM (
	idkey                           numeric(18,0)                    not null,
	FOC_I                           int                                  null,
	FOC_OFF                         float(16)                            null,
	DHSVER                          varchar(70)                          null,
	HDTFILE                         varchar(70)                          null,
	HDTFILE2                        varchar(70)                          null,
	USERID                          varchar(70)                          null,
	SURVEY                          varchar(70)                          null,
	SURVEY_I                        varchar(70)                          null,
	OBJECT                          varchar(70)                          null,
	RECIPE                          varchar(70)                      not null,
	GRPMEM                          bit                              not null,
	TILENUM                         int                                  null,
	STANDARD                        bit                              not null,
	NJITTER                         int                                  null,
	JITTER_I                        int                                  null,
	JITTER_X                        float(16)                            null,
	JITTER_Y                        float(16)                            null,
	NUSTEP                          int                                  null,
	USTEP_I                         int                                  null,
	USTEP_X                         float(16)                            null,
	USTEP_Y                         float(16)                            null,
	NFOC                            int                                  null,
	NFOSCAN                         int                                  null,
	DATE_OBS                        varchar(70)                          null,
	DATE_END                        varchar(70)                          null,
	MJD_OBS                         varchar(70)                          null,
	WCSAXES                         int                                  null,
	RADESYS                         varchar(9)                           null,
	CTYPE1                          varchar(9)                           null,
	CTYPE2                          varchar(9)                           null,
	CRPIX1                          float(16)                            null,
	CRPIX2                          float(16)                            null,
	CRVAL1                          float(16)                            null,
	CRVAL2                          float(16)                            null,
	CRUNIT1                         varchar(9)                           null,
	CRUNIT2                         varchar(9)                           null,
	CD1_1                           float(16)                            null,
	CD1_2                           float(16)                            null,
	CD2_1                           float(16)                            null,
	CD2_2                           float(16)                            null,
	PV2_1                           float(16)                            null,
	PV2_2                           float(16)                            null,
	PV2_3                           float(16)                            null,
	TRAOFF                          float(16)                            null,
	TDECOFF                         float(16)                            null,
	TELRA                           float(16)                            null,
	TELDEC                          float(16)                            null,
	GSRA                            float(16)                            null,
	GSDEC                           float(16)                            null,
	DETECTID                        varchar(9)                           null,
	NINT                            int                                  null,
	RDOUT_X1                        int                                  null,
	RDOUT_X2                        int                                  null,
	RDOUT_Y1                        int                                  null,
	RDOUT_Y2                        int                                  null,
	PIXLSIZE                        float(16)                            null,
	PCSYSID                         varchar(9)                           null,
	SDSUID                          varchar(9)                           null,
	READMODE                        varchar(9)                           null,
	CAPPLICN                        varchar(18)                          null,
	CAMROLE                         varchar(9)                           null,
	READOUT                         varchar(9)                           null,
	EXP_TIME                        float(16)                            null,
	READINT                         float(16)                            null,
	NREADS                          int                                  null,
	GAIN                            float(16)                            null,
	FOC_ZERO                        float(16)                            null,
	FOC_OFFS                        float(16)                            null,
	AIRTEMP                         float(16)                            null,
	BARPRESS                        float(16)                            null,
	DEWPOINT                        float(16)                            null,
	DOMETEMP                        float(16)                            null,
	HUMIDITY                        float(16)                            null,
	MIRRBSW                         float(16)                            null,
	MIRRNE                          float(16)                            null,
	MIRRNW                          float(16)                            null,
	MIRRSE                          float(16)                            null,
	MIRRSW                          float(16)                            null,
	MIRRBTNW                        float(16)                            null,
	MIRRTPNW                        float(16)                            null,
	SECONDAR                        float(16)                            null,
	TOPAIRNW                        float(16)                            null,
	TRUSSENE                        float(16)                            null,
	TRUSSWSW                        float(16)                            null,
	WIND_DIR                        float(16)                            null,
	WIND_SPD                        float(16)                            null,
	CSOTAU                          float(16)                            null,
	TAUDATE                         varchar(16)                          null,
	TAUSRC                          varchar(9)                           null,
	CNFINDEX                        int                                  null,
	DET_TEMP                        float(16)                            null,
	CAMNUM                          smallint                             null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.WFCAM to public Granted by dbo
go
Grant Delete Statistics on dbo.WFCAM to arc Granted by dbo
go
Grant Truncate Table on dbo.WFCAM to arc Granted by dbo
go
Grant Update Statistics on dbo.WFCAM to arc Granted by dbo
go
Grant References on dbo.WFCAM to arc Granted by dbo
go
Grant Insert on dbo.WFCAM to arc Granted by dbo
go
Grant Delete on dbo.WFCAM to arc Granted by dbo
go
Grant Update on dbo.WFCAM to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'index_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_1" >>>>>'
go 

create unique clustered index index_1 
on ukirt.dbo.WFCAM(idkey)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.WFCAM_OLD'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.WFCAM_OLD" >>>>>'
go

setuser 'dbo'
go 

create table WFCAM_OLD (
	idkey                           numeric(18,0)                    not null,
	FOC_I                           int                                  null,
	FOC_OFF                         float(16)                            null,
	DHSVER                          varchar(70)                          null,
	HDTFILE                         varchar(70)                          null,
	HDTFILE2                        varchar(70)                          null,
	USERID                          varchar(70)                          null,
	SURVEY                          varchar(70)                          null,
	SURVEY_I                        varchar(70)                          null,
	OBJECT                          varchar(70)                          null,
	RECIPE                          varchar(70)                      not null,
	GRPMEM                          bit                              not null,
	TILENUM                         int                                  null,
	STANDARD                        bit                              not null,
	NJITTER                         int                                  null,
	JITTER_I                        int                                  null,
	JITTER_X                        float(16)                            null,
	JITTER_Y                        float(16)                            null,
	NUSTEP                          int                                  null,
	USTEP_I                         int                                  null,
	USTEP_X                         float(16)                            null,
	USTEP_Y                         float(16)                            null,
	NFOC                            int                                  null,
	NFOSCAN                         int                                  null,
	DATE_OBS                        varchar(70)                          null,
	DATE_END                        varchar(70)                          null,
	MJD_OBS                         varchar(70)                          null,
	WCSAXES                         int                                  null,
	RADESYS                         varchar(9)                           null,
	CTYPE1                          varchar(9)                           null,
	CTYPE2                          varchar(9)                           null,
	CRPIX1                          float(16)                            null,
	CRPIX2                          float(16)                            null,
	CRVAL1                          float(16)                            null,
	CRVAL2                          float(16)                            null,
	CRUNIT1                         varchar(9)                           null,
	CRUNIT2                         varchar(9)                           null,
	CD1_1                           float(16)                            null,
	CD1_2                           float(16)                            null,
	CD2_1                           float(16)                            null,
	CD2_2                           float(16)                            null,
	PV2_1                           float(16)                            null,
	PV2_2                           float(16)                            null,
	PV2_3                           float(16)                            null,
	TRAOFF                          float(16)                            null,
	TDECOFF                         float(16)                            null,
	TELRA                           float(16)                            null,
	TELDEC                          float(16)                            null,
	GSRA                            float(16)                            null,
	GSDEC                           float(16)                            null,
	DETECTID                        varchar(9)                           null,
	NINT                            int                                  null,
	RDOUT_X1                        int                                  null,
	RDOUT_X2                        int                                  null,
	RDOUT_Y1                        int                                  null,
	RDOUT_Y2                        int                                  null,
	PIXLSIZE                        float(16)                            null,
	PCSYSID                         varchar(9)                           null,
	SDSUID                          varchar(9)                           null,
	READMODE                        varchar(9)                           null,
	CAPPLICN                        varchar(18)                          null,
	CAMROLE                         varchar(9)                           null,
	READOUT                         varchar(9)                           null,
	EXP_TIME                        float(16)                            null,
	READINT                         float(16)                            null,
	NREADS                          int                                  null,
	GAIN                            float(16)                            null,
	FOC_ZERO                        float(16)                            null,
	FOC_OFFS                        float(16)                            null,
	AIRTEMP                         float(16)                            null,
	BARPRESS                        float(16)                            null,
	DEWPOINT                        float(16)                            null,
	DOMETEMP                        float(16)                            null,
	HUMIDITY                        float(16)                            null,
	MIRRBSW                         float(16)                            null,
	MIRRNE                          float(16)                            null,
	MIRRNW                          float(16)                            null,
	MIRRSE                          float(16)                            null,
	MIRRSW                          float(16)                            null,
	MIRRBTNW                        float(16)                            null,
	MIRRTPNW                        float(16)                            null,
	SECONDAR                        float(16)                            null,
	TOPAIRNW                        float(16)                            null,
	TRUSSENE                        float(16)                            null,
	TRUSSWSW                        float(16)                            null,
	WIND_DIR                        float(16)                            null,
	WIND_SPD                        float(16)                            null,
	CSOTAU                          float(16)                            null,
	TAUDATE                         varchar(16)                          null,
	TAUSRC                          varchar(9)                           null,
	CNFINDEX                        int                                  null,
	DET_TEMP                        float(16)                            null,
	CAMNUM                          smallint                             null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.WFCAM_OLD to public Granted by dbo
go
Grant Delete Statistics on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Truncate Table on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Update Statistics on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant References on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Insert on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Delete on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Update on dbo.WFCAM_OLD to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.full'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.full" >>>>>'
go

setuser 'dbo'
go 

create table full (
	Name                            varchar(35)                      not null,
	Config_val                      int                              not null,
	System_val                      int                              not null,
	Total_val                       int                              not null,
	Num_free                        int                              not null,
	Num_active                      int                              not null,
	Pct_act                         char(6)                          not null,
	Max_Used                        int                              not null,
	Reuse_cnt                       int                              not null,
	Date                            varchar(30)                      not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.requests'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.requests" >>>>>'
go

setuser 'dbo'
go 

create table requests (
	request_id                      int                              not null,
	request_date                    int                              not null,
	processed                       int                              not null,
	first_name                      varchar(70)                      not null,
	last_name                       varchar(70)                      not null,
	institution                     varchar(70)                      not null,
	email                           varchar(70)                      not null,
	datasets                        text                             not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

sp_placeobject 'default', 'dbo.requests.trequests'
go 

Grant Select on dbo.requests to public Granted by dbo
go
Grant Delete Statistics on dbo.requests to arc Granted by dbo
go
Grant Truncate Table on dbo.requests to arc Granted by dbo
go
Grant Update Statistics on dbo.requests to arc Granted by dbo
go
Grant References on dbo.requests to arc Granted by dbo
go
Grant Insert on dbo.requests to arc Granted by dbo
go
Grant Delete on dbo.requests to arc Granted by dbo
go
Grant Update on dbo.requests to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.rs_lastcommit'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.rs_lastcommit" >>>>>'
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
on ukirt.dbo.rs_lastcommit(origin)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.rs_threads'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.rs_threads" >>>>>'
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
on ukirt.dbo.rs_threads(id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.rs_ticket_history'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.rs_ticket_history" >>>>>'
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
on ukirt.dbo.rs_ticket_history(cnt)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.tapeinfo'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.tapeinfo" >>>>>'
go

setuser 'dbo'
go 

create table tapeinfo (
	ut_dmf                          int                              not null,
	instrument                      varchar(20)                      not null,
	tape                            varchar(10)                      not null,
	file_no                         int                              not null,
	ut_date                         datetime                             null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.tapeinfo to public Granted by dbo
go
Grant Delete Statistics on dbo.tapeinfo to arc Granted by dbo
go
Grant Truncate Table on dbo.tapeinfo to arc Granted by dbo
go
Grant Update Statistics on dbo.tapeinfo to arc Granted by dbo
go
Grant References on dbo.tapeinfo to arc Granted by dbo
go
Grant Insert on dbo.tapeinfo to arc Granted by dbo
go
Grant Delete on dbo.tapeinfo to arc Granted by dbo
go
Grant Update on dbo.tapeinfo to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'index_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_1" >>>>>'
go 

create nonclustered index index_1 
on ukirt.dbo.tapeinfo(ut_dmf, instrument)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'index_2'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_2" >>>>>'
go 

create nonclustered index index_2 
on ukirt.dbo.tapeinfo(tape)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'ukirt.dbo.ukrev'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "ukirt.dbo.ukrev" >>>>>'
go

setuser 'dbo'
go 

create table ukrev (
	ut_dmf                          int                              not null,
	operator                        varchar(10)                          null,
	type                            varchar(1)                           null,
	observers                       varchar(31)                          null,
	morning_shift                   varchar(1)                           null,
	instruments                     varchar(21)                          null,
	optical_config                  int                                  null,
	hours_avail                     float(16)                            null,
	hours_obs                       float(16)                            null,
	hours_lost                      float(16)                            null,
	wind_avg                        float(16)                            null,
	wind_peak                       float(16)                            null,
	humidity_high                   float(16)                            null,
	humidity_low                    float(16)                            null,
	cloud_coverage                  int                                  null,
	cloud_type                      varchar(16)                          null,
	precipitation                   varchar(1)                           null,
	fog                             varchar(1)                           null,
	port_north                      varchar(11)                          null,
	north_v                         float(16)                            null,
	north_h                         float(16)                            null,
	port_east                       varchar(11)                          null,
	east_v                          float(16)                            null,
	east_h                          float(16)                            null,
	port_south                      varchar(11)                          null,
	south_v                         float(16)                            null,
	south_h                         float(16)                            null,
	port_west                       varchar(11)                          null,
	west_v                          float(16)                            null,
	west_h                          float(16)                            null,
	seeing_am                       float(16)                            null,
	seeing_pm                       float(16)                            null,
	sony_x                          float(16)                            null,
	sony_y                          float(16)                            null,
	telescope_ih                    float(16)                            null,
	telescope_id                    float(16)                            null,
	telescope_ch                    float(16)                            null,
	camera_focus                    float(16)                            null,
	telescope_desc                  varchar(51)                          null,
	telescope_loss                  float(16)                            null,
	instrument_desc                 varchar(51)                          null,
	instrument_user                 varchar(1)                           null,
	instrument_loss                 float(16)                            null,
	computer_desc                   varchar(51)                          null,
	computer_user                   varchar(1)                           null,
	computer_loss                   float(16)                            null,
	other_desc                      varchar(51)                          null,
	other_user                      varchar(1)                           null,
	other_loss                      float(16)                            null,
	comments                        text                                 null,
	ut_date                         datetime                             null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

sp_placeobject 'default', 'dbo.ukrev.tukrev'
go 

Grant Select on dbo.ukrev to public Granted by dbo
go
Grant Delete Statistics on dbo.ukrev to arc Granted by dbo
go
Grant Truncate Table on dbo.ukrev to arc Granted by dbo
go
Grant Update Statistics on dbo.ukrev to arc Granted by dbo
go
Grant References on dbo.ukrev to arc Granted by dbo
go
Grant Insert on dbo.ukrev to arc Granted by dbo
go
Grant Delete on dbo.ukrev to arc Granted by dbo
go
Grant Update on dbo.ukrev to arc Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'index_1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "index_1" >>>>>'
go 

create unique clustered index index_1 
on ukirt.dbo.ukrev(ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'ukirt.dbo.rs_check_repl_stat'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "ukirt.dbo.rs_check_repl_stat" >>>>>'
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
-- DDL for Stored Procedure 'ukirt.dbo.rs_get_lastcommit'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "ukirt.dbo.rs_get_lastcommit" >>>>>'
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
-- DDL for Stored Procedure 'ukirt.dbo.rs_initialize_threads'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "ukirt.dbo.rs_initialize_threads" >>>>>'
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
-- DDL for Stored Procedure 'ukirt.dbo.rs_marker'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "ukirt.dbo.rs_marker" >>>>>'
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
-- DDL for Stored Procedure 'ukirt.dbo.rs_send_repserver_cmd'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "ukirt.dbo.rs_send_repserver_cmd" >>>>>'
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
-- DDL for Stored Procedure 'ukirt.dbo.rs_ticket'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "ukirt.dbo.rs_ticket" >>>>>'
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
-- DDL for Stored Procedure 'ukirt.dbo.rs_ticket_report'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "ukirt.dbo.rs_ticket_report" >>>>>'
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
-- DDL for Stored Procedure 'ukirt.dbo.rs_ticket_v1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "ukirt.dbo.rs_ticket_v1" >>>>>'
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
-- DDL for Stored Procedure 'ukirt.dbo.rs_update_lastcommit'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "ukirt.dbo.rs_update_lastcommit" >>>>>'
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
-- DDL for Stored Procedure 'ukirt.dbo.rs_update_threads'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "ukirt.dbo.rs_update_threads" >>>>>'
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
use ukirt
go 

sp_addthreshold ukirt, 'logsegment', 21872, sp_thresholdaction
go 

sp_addthreshold ukirt, 'logsegment', 138240, sp_thresholdaction
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
Grant Select on dbo.CGS4 to public Granted by dbo
go
Grant Select on dbo.COMMON to public Granted by dbo
go
Grant Select on dbo.IRCAM3 to public Granted by dbo
go
Grant Select on dbo.MICHELLE to public Granted by dbo
go
Grant Select on dbo.UFTI to public Granted by dbo
go
Grant Select on dbo.UIST to public Granted by dbo
go
Grant Select on dbo.WFCAM to public Granted by dbo
go
Grant Select on dbo.WFCAM_OLD to public Granted by dbo
go
Grant Select on dbo.requests to public Granted by dbo
go
Grant Select on dbo.tapeinfo to public Granted by dbo
go
Grant Select on dbo.ukrev to public Granted by dbo
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
Grant Select on dbo.rs_threads to public Granted by dbo
go
Grant Execute on dbo.rs_update_threads to public Granted by dbo
go
Grant Execute on dbo.rs_initialize_threads to public Granted by dbo
go
Grant Execute on dbo.rs_ticket_v1 to public Granted by dbo
go
Grant References on dbo.CGS4 to arc Granted by dbo
go
Grant Insert on dbo.CGS4 to arc Granted by dbo
go
Grant Delete on dbo.CGS4 to arc Granted by dbo
go
Grant Update on dbo.CGS4 to arc Granted by dbo
go
Grant Delete Statistics on dbo.CGS4 to arc Granted by dbo
go
Grant Truncate Table on dbo.CGS4 to arc Granted by dbo
go
Grant Update Statistics on dbo.CGS4 to arc Granted by dbo
go
Grant References on dbo.COMMON to arc Granted by dbo
go
Grant Insert on dbo.COMMON to arc Granted by dbo
go
Grant Delete on dbo.COMMON to arc Granted by dbo
go
Grant Update on dbo.COMMON to arc Granted by dbo
go
Grant Delete Statistics on dbo.COMMON to arc Granted by dbo
go
Grant Truncate Table on dbo.COMMON to arc Granted by dbo
go
Grant Update Statistics on dbo.COMMON to arc Granted by dbo
go
Grant References on dbo.IRCAM3 to arc Granted by dbo
go
Grant Insert on dbo.IRCAM3 to arc Granted by dbo
go
Grant Delete on dbo.IRCAM3 to arc Granted by dbo
go
Grant Update on dbo.IRCAM3 to arc Granted by dbo
go
Grant Delete Statistics on dbo.IRCAM3 to arc Granted by dbo
go
Grant Truncate Table on dbo.IRCAM3 to arc Granted by dbo
go
Grant Update Statistics on dbo.IRCAM3 to arc Granted by dbo
go
Grant References on dbo.MICHELLE to arc Granted by dbo
go
Grant Insert on dbo.MICHELLE to arc Granted by dbo
go
Grant Delete on dbo.MICHELLE to arc Granted by dbo
go
Grant Update on dbo.MICHELLE to arc Granted by dbo
go
Grant Delete Statistics on dbo.MICHELLE to arc Granted by dbo
go
Grant Truncate Table on dbo.MICHELLE to arc Granted by dbo
go
Grant Update Statistics on dbo.MICHELLE to arc Granted by dbo
go
Grant References on dbo.UFTI to arc Granted by dbo
go
Grant Insert on dbo.UFTI to arc Granted by dbo
go
Grant Delete on dbo.UFTI to arc Granted by dbo
go
Grant Update on dbo.UFTI to arc Granted by dbo
go
Grant Delete Statistics on dbo.UFTI to arc Granted by dbo
go
Grant Truncate Table on dbo.UFTI to arc Granted by dbo
go
Grant Update Statistics on dbo.UFTI to arc Granted by dbo
go
Grant References on dbo.UIST to arc Granted by dbo
go
Grant Insert on dbo.UIST to arc Granted by dbo
go
Grant Delete on dbo.UIST to arc Granted by dbo
go
Grant Update on dbo.UIST to arc Granted by dbo
go
Grant Delete Statistics on dbo.UIST to arc Granted by dbo
go
Grant Truncate Table on dbo.UIST to arc Granted by dbo
go
Grant Update Statistics on dbo.UIST to arc Granted by dbo
go
Grant References on dbo.WFCAM to arc Granted by dbo
go
Grant Insert on dbo.WFCAM to arc Granted by dbo
go
Grant Delete on dbo.WFCAM to arc Granted by dbo
go
Grant Update on dbo.WFCAM to arc Granted by dbo
go
Grant Delete Statistics on dbo.WFCAM to arc Granted by dbo
go
Grant Truncate Table on dbo.WFCAM to arc Granted by dbo
go
Grant Update Statistics on dbo.WFCAM to arc Granted by dbo
go
Grant References on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Insert on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Delete on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Update on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Delete Statistics on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Truncate Table on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant Update Statistics on dbo.WFCAM_OLD to arc Granted by dbo
go
Grant References on dbo.requests to arc Granted by dbo
go
Grant Insert on dbo.requests to arc Granted by dbo
go
Grant Delete on dbo.requests to arc Granted by dbo
go
Grant Update on dbo.requests to arc Granted by dbo
go
Grant Delete Statistics on dbo.requests to arc Granted by dbo
go
Grant Truncate Table on dbo.requests to arc Granted by dbo
go
Grant Update Statistics on dbo.requests to arc Granted by dbo
go
Grant References on dbo.tapeinfo to arc Granted by dbo
go
Grant Insert on dbo.tapeinfo to arc Granted by dbo
go
Grant Delete on dbo.tapeinfo to arc Granted by dbo
go
Grant Update on dbo.tapeinfo to arc Granted by dbo
go
Grant Delete Statistics on dbo.tapeinfo to arc Granted by dbo
go
Grant Truncate Table on dbo.tapeinfo to arc Granted by dbo
go
Grant Update Statistics on dbo.tapeinfo to arc Granted by dbo
go
Grant References on dbo.ukrev to arc Granted by dbo
go
Grant Insert on dbo.ukrev to arc Granted by dbo
go
Grant Delete on dbo.ukrev to arc Granted by dbo
go
Grant Update on dbo.ukrev to arc Granted by dbo
go
Grant Delete Statistics on dbo.ukrev to arc Granted by dbo
go
Grant Truncate Table on dbo.ukrev to arc Granted by dbo
go
Grant Update Statistics on dbo.ukrev to arc Granted by dbo
go


-- DDLGen Completed
-- at 12/06/17 9:38:31 HST