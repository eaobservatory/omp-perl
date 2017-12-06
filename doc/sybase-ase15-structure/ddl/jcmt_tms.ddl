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
-- -S SYB_JAC -I /opt2/sybase/ase-15.0/interfaces -P*** -U sa -O ddl/2016-0308/jcmt_tms.ddl.2016-0308-0153 -L jcmt_tms.progress.2016-0308-0153 -T DB -N jcmt_tms 
-- at 03/08/16 1:54:02 HST


Found 1 dbids with wrong number of rows cached in '#seginfo' v/s the rows in 'master.dbo.sysusages'
use jcmt_tms
go

exec sp_changedbowner 'jach', true 
go

exec master.dbo.sp_dboption jcmt_tms, 'select into/bulkcopy/pllsort', true
go

exec master.dbo.sp_dboption jcmt_tms, 'abort tran on log full', true
go

exec master.dbo.sp_dboption jcmt_tms, 'full logging for select into', true
go

checkpoint
go


-----------------------------------------------------------------------------
-- DDL for Group 'jcmtstaff'
-----------------------------------------------------------------------------

print '<<<<< CREATING Group - "jcmtstaff" >>>>>'
go 

exec sp_addgroup 'jcmtstaff'

go 


-----------------------------------------------------------------------------
-- DDL for Group 'observers'
-----------------------------------------------------------------------------

print '<<<<< CREATING Group - "observers" >>>>>'
go 

exec sp_addgroup 'observers'

go 


-----------------------------------------------------------------------------
-- DDL for Group 'visitors'
-----------------------------------------------------------------------------

print '<<<<< CREATING Group - "visitors" >>>>>'
go 

exec sp_addgroup 'visitors'

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

exec sp_adduser 'staff' ,'staff' ,'jcmtstaff'
go 


-----------------------------------------------------------------------------
-- DDL for User 'visitor'
-----------------------------------------------------------------------------

print '<<<<< CREATING User - "visitor" >>>>>'
go 

exec sp_adduser 'visitor' ,'visitor' ,'visitors'
go 


-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.c11d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.c11d" >>>>>'
go 

setuser 'dbo'
go 

create default c11d
as "        "

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.c1d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.c1d" >>>>>'
go 

setuser 'dbo'
go 

create default c1d
as " "

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.c2d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.c2d" >>>>>'
go 

setuser 'dbo'
go 

create default c2d
as "  "

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.c3d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.c3d" >>>>>'
go 

setuser 'dbo'
go 

create default c3d
as "   "

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.c4d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.c4d" >>>>>'
go 

setuser 'dbo'
go 

create default c4d
as "    "

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.c5d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.c5d" >>>>>'
go 

setuser 'dbo'
go 

create default c5d
as "     "

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.c6d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.c6d" >>>>>'
go 

setuser 'dbo'
go 

create default c6d
as "      "

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.c8d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.c8d" >>>>>'
go 

setuser 'dbo'
go 

create default c8d
as "        "

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.dt8d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.dt8d" >>>>>'
go 

setuser 'dbo'
go 

create default dt8d
as  "01/01/2050 00:00:00"

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.i2d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.i2d" >>>>>'
go 

setuser 'dbo'
go 

create default i2d
as 0

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.i4d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.i4d" >>>>>'
go 

setuser 'dbo'
go 

create default i4d
as 0

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.idd'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.idd" >>>>>'
go 

setuser 'dbo'
go 

create default idd
as 0

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.l1d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.l1d" >>>>>'
go 

setuser 'dbo'
go 

create default l1d
as 0

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.r4d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.r4d" >>>>>'
go 

setuser 'dbo'
go 

create default r4d
as 0.

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.r8d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.r8d" >>>>>'
go 

setuser 'dbo'
go 

create default r8d
as 0.

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc10d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc10d" >>>>>'
go 

setuser 'dbo'
go 

create default vc10d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc120d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc120d" >>>>>'
go 

setuser 'dbo'
go 

create default vc120d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc12d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc12d" >>>>>'
go 

setuser 'dbo'
go 

create default vc12d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc16d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc16d" >>>>>'
go 

setuser 'dbo'
go 

create default vc16d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc20d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc20d" >>>>>'
go 

setuser 'dbo'
go 

create default vc20d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc240d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc240d" >>>>>'
go 

setuser 'dbo'
go 

create default vc240d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc24d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc24d" >>>>>'
go 

setuser 'dbo'
go 

create default vc24d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc255d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc255d" >>>>>'
go 

setuser 'dbo'
go 

create default vc255d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc2d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc2d" >>>>>'
go 

setuser 'dbo'
go 

create default vc2d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc3d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc3d" >>>>>'
go 

setuser 'dbo'
go 

create default vc3d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc40d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc40d" >>>>>'
go 

setuser 'dbo'
go 

create default vc40d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc4d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc4d" >>>>>'
go 

setuser 'dbo'
go 

create default vc4d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc5d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc5d" >>>>>'
go 

setuser 'dbo'
go 

create default vc5d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc64d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc64d" >>>>>'
go 

setuser 'dbo'
go 

create default vc64d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc6d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc6d" >>>>>'
go 

setuser 'dbo'
go 

create default vc6d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.vc8d'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.vc8d" >>>>>'
go 

setuser 'dbo'
go 

create default vc8d
as ""

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Default 'jcmt_tms.dbo.year2050_dflt'
-----------------------------------------------------------------------------

print '<<<<< CREATING Default - "jcmt_tms.dbo.year2050_dflt" >>>>>'
go 

setuser 'dbo'
go 

create default year2050_dflt as "jan 01 2050 00:00am"

go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc255'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc255" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc255' , 'varchar(255)' , null
go 

sp_bindefault 'dbo.vc255d', 'vc255'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc240'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc240" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc240' , 'varchar(240)' , null
go 

sp_bindefault 'dbo.vc240d', 'vc240'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc120'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc120" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc120' , 'varchar(120)' , null
go 

sp_bindefault 'dbo.vc120d', 'vc120'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc64'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc64" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc64' , 'varchar(64)' , null
go 

sp_bindefault 'dbo.vc64d', 'vc64'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc40'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc40" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc40' , 'varchar(40)' , null
go 

sp_bindefault 'dbo.vc40d', 'vc40'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc24'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc24" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc24' , 'varchar(24)' , null
go 

sp_bindefault 'dbo.vc24d', 'vc24'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc20'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc20" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc20' , 'varchar(20)' , null
go 

sp_bindefault 'dbo.vc20d', 'vc20'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc16'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc16" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc16' , 'varchar(16)' , null
go 

sp_bindefault 'dbo.vc16d', 'vc16'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc12'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc12" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc12' , 'varchar(12)' , null
go 

sp_bindefault 'dbo.vc12d', 'vc12'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc10'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc10" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc10' , 'varchar(10)' , null
go 

sp_bindefault 'dbo.vc10d', 'vc10'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc8'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc8" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc8' , 'varchar(8)' , null
go 

sp_bindefault 'dbo.vc8d', 'vc8'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc6'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc6" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc6' , 'varchar(6)' , null
go 

sp_bindefault 'dbo.vc6d', 'vc6'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc5'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc5" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc5' , 'varchar(5)' , null
go 

sp_bindefault 'dbo.vc5d', 'vc5'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc4'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc4" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc4' , 'varchar(4)' , null
go 

sp_bindefault 'dbo.vc4d', 'vc4'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc3'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc3" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc3' , 'varchar(3)' , null
go 

sp_bindefault 'dbo.vc3d', 'vc3'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vc2'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vc2" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vc2' , 'varchar(2)' , null
go 

sp_bindefault 'dbo.vc2d', 'vc2'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.c11'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.c11" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'c11' , 'char(11)' , null
go 

sp_bindefault 'dbo.c11d', 'c11'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.c8'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.c8" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'c8' , 'char(8)' , null
go 

sp_bindefault 'dbo.c8d', 'c8'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.c6'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.c6" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'c6' , 'char(6)' , null
go 

sp_bindefault 'dbo.c6d', 'c6'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.c5'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.c5" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'c5' , 'char(5)' , null
go 

sp_bindefault 'dbo.c5d', 'c5'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.c4'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.c4" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'c4' , 'char(4)' , null
go 

sp_bindefault 'dbo.c4d', 'c4'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.c3'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.c3" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'c3' , 'char(3)' , null
go 

sp_bindefault 'dbo.c3d', 'c3'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.c2'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.c2" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'c2' , 'char(2)' , null
go 

sp_bindefault 'dbo.c2d', 'c2'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.c1'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.c1" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'c1' , 'char(1)' , null
go 

sp_bindefault 'dbo.c1d', 'c1'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.l1'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.l1" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'l1' , 'tinyint' , null
go 

sp_bindefault 'dbo.l1d', 'l1'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.i2'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.i2" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'i2' , 'smallint' , null
go 

sp_bindefault 'dbo.i2d', 'i2'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.i4'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.i4" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'i4' , 'int' , null
go 

sp_bindefault 'dbo.i4d', 'i4'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.r4'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.r4" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'r4' , 'real' , null
go 

sp_bindefault 'dbo.r4d', 'r4'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.r8'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.r8" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'r8' , 'float(16)' , null
go 

sp_bindefault 'dbo.r8d', 'r8'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.dt8'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.dt8" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'dt8' , 'datetime' , null
go 

sp_bindefault 'dbo.dt8d', 'dt8'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.vb255'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.vb255" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'vb255' , 'varbinary(255)' , null
go 

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.dt8_2050'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.dt8_2050" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'dt8_2050' , 'datetime' , null
go 

sp_bindefault 'dbo.year2050_dflt', 'dt8_2050'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for UserDefinedDatatype 'jcmt_tms.id'
-----------------------------------------------------------------------------

print '<<<<< CREATING UserDefinedDatatype - "jcmt_tms.id" >>>>>'
go 

SETUSER 'dbo'
go

exec  sp_addtype 'id' , 'int' , null
go 

sp_bindefault 'dbo.idd', 'id'
go

SETUSER
go


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.AZEL'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.AZEL" >>>>>'
go

use jcmt_tms
go 

setuser 'dbo'
go 

create table AZEL (
	projid                          vc16                                 null,
	scan                            r8                                   null,
	ut                              dt8                                  null,
	object                          vc16                                 null,
	raj2000                         r8                                   null,
	decj2000                        r8                                   null,
	strt_az                         r8                                   null,
	strt_el                         r8                                   null,
	end_az                          r8                                   null,
	end_el                          r8                                   null,
	utstart                         varchar(19)                      not null,
	utstop                          varchar(19)                      not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'AZELutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELutind" >>>>>'
go 

create unique clustered index AZELutind 
on jcmt_tms.dbo.AZEL(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELprojind" >>>>>'
go 

create nonclustered index AZELprojind 
on jcmt_tms.dbo.AZEL(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELstrtazind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELstrtazind" >>>>>'
go 

create nonclustered index AZELstrtazind 
on jcmt_tms.dbo.AZEL(strt_az)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELstrtelind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELstrtelind" >>>>>'
go 

create nonclustered index AZELstrtelind 
on jcmt_tms.dbo.AZEL(strt_el)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELendazind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELendazind" >>>>>'
go 

create nonclustered index AZELendazind 
on jcmt_tms.dbo.AZEL(end_az)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELendelind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELendelind" >>>>>'
go 

create nonclustered index AZELendelind 
on jcmt_tms.dbo.AZEL(end_el)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.AZEL2'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.AZEL2" >>>>>'
go

setuser 'dbo'
go 

create table AZEL2 (
	projid                          vc16                                 null,
	scan                            r8                                   null,
	ut                              dt8                                  null,
	object                          vc16                                 null,
	raj2000                         r8                                   null,
	decj2000                        r8                                   null,
	strt_az                         r8                                   null,
	strt_el                         r8                                   null,
	end_az                          r8                                   null,
	end_el                          r8                                   null,
	utstart                         varchar(19)                      not null,
	utstop                          varchar(19)                      not null,
	strt_f2                         r4                                   null,
	end_f2                          r4                                   null,
	avg_f2                          real                             not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'AZEL2utind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZEL2utind" >>>>>'
go 

create unique clustered index AZEL2utind 
on jcmt_tms.dbo.AZEL2(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELprojind" >>>>>'
go 

create nonclustered index AZELprojind 
on jcmt_tms.dbo.AZEL2(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELstrtazind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELstrtazind" >>>>>'
go 

create nonclustered index AZELstrtazind 
on jcmt_tms.dbo.AZEL2(strt_az)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELstrtelind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELstrtelind" >>>>>'
go 

create nonclustered index AZELstrtelind 
on jcmt_tms.dbo.AZEL2(strt_el)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELendazind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELendazind" >>>>>'
go 

create nonclustered index AZELendazind 
on jcmt_tms.dbo.AZEL2(end_az)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELendelind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELendelind" >>>>>'
go 

create nonclustered index AZELendelind 
on jcmt_tms.dbo.AZEL2(end_el)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'AZELavgf2ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "AZELavgf2ind" >>>>>'
go 

create nonclustered index AZELavgf2ind 
on jcmt_tms.dbo.AZEL2(avg_f2)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.CAL'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.CAL" >>>>>'
go

setuser 'dbo'
go 

create table CAL (
	cal#                            numeric(9,0)                     identity,
	date                            dt8                                  null,
	mode                            vc8                                  null,
	lofreq                          r8                                   null,
	freq                            r8                                   null,
	rx                              vc8                                  null,
	sbmode                          c3                                   null,
	flag                            i2                                   null,
	note                            vc255                                null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.CAL to public Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'CALdateind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "CALdateind" >>>>>'
go 

create unique clustered index CALdateind 
on jcmt_tms.dbo.CAL(date)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'CALlofreqind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "CALlofreqind" >>>>>'
go 

create nonclustered index CALlofreqind 
on jcmt_tms.dbo.CAL(lofreq)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.CRYO'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.CRYO" >>>>>'
go

setuser 'dbo'
go 

create table CRYO (
	cryo#                           id                                   null,
	ut                              dt8                                  null,
	userid                          vc16                                 null,
	notes                           vc64                                 null,
	p_vacuum                        r4                                   null,
	p_optbox                        r4                                   null,
	lhe_level                       r4                                   null,
	lhe_boiloff                     r4                                   null,
	dewar_ln2_trap                  r4                                   null,
	dewar_ln2_shield                r4                                   null,
	cold_trap_ln2                   r4                                   null,
	p1                              r4                                   null,
	p2                              r4                                   null,
	g1                              r4                                   null,
	g2                              r4                                   null,
	d1                              r4                                   null,
	d2                              r4                                   null,
	d4                              r4                                   null,
	d5                              r4                                   null,
	d8                              r4                                   null,
	bridge_res                      r4                                   null,
	array_temp                      r4                                   null,
	battery_no                      i4                                   null,
	fet_lw                          r4                                   null,
	fet_sw                          r4                                   null,
	tuple_id                        i4                                   null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Delete Statistics on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Truncate Table on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Update Statistics on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant References on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Select on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Insert on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Delete on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Update on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Select on dbo.CRYO to observers Granted by dbo
go
Grant Select on dbo.CRYO to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'CRYOcryoind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "CRYOcryoind" >>>>>'
go 

create unique clustered index CRYOcryoind 
on jcmt_tms.dbo.CRYO(cryo#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'CRYOut'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "CRYOut" >>>>>'
go 

create nonclustered index CRYOut 
on jcmt_tms.dbo.CRYO(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.CSONIGHT'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.CSONIGHT" >>>>>'
go

setuser 'dbo'
go 

create table CSONIGHT (
	utdate                          datetime                             null,
	avgtau                          float(16)                            null,
	month                           numeric(18,6)                        null,
	grade                           float(16)                            null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.CSONIGHT to dbo Granted by dbo
go
Grant Select on dbo.CSONIGHT to jcmtstaff Granted by dbo
go
Grant Select on dbo.CSONIGHT to observers Granted by dbo
go
Grant Select on dbo.CSONIGHT to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.CSOTAU'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.CSOTAU" >>>>>'
go

setuser 'dbo'
go 

create table CSOTAU (
	tau#                            id                                   null,
	cso_ut                          dt8                                  null,
	hst                             r4                                   null,
	tau                             r4                                   null,
	tau_rms                         r4                                   null,
	cso_ut_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.CSOTAU to dbo Granted by dbo
go
Grant Select on dbo.CSOTAU to jcmtstaff Granted by dbo
go
Grant Select on dbo.CSOTAU to observers Granted by dbo
go
Grant Select on dbo.CSOTAU to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'CSOTAUtau#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "CSOTAUtau#ind" >>>>>'
go 

create unique clustered index CSOTAUtau#ind 
on jcmt_tms.dbo.CSOTAU(tau#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'CSOTAUcsoutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "CSOTAUcsoutind" >>>>>'
go 

create unique nonclustered index CSOTAUcsoutind 
on jcmt_tms.dbo.CSOTAU(cso_ut)
with ignore_dup_key 
go 


-----------------------------------------------------------------------------
-- DDL for Index 'CSOTAUcsodmfind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "CSOTAUcsodmfind" >>>>>'
go 

create nonclustered index CSOTAUcsodmfind 
on jcmt_tms.dbo.CSOTAU(cso_ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'CSOTAUtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "CSOTAUtupind" >>>>>'
go 

create nonclustered index CSOTAUtupind 
on jcmt_tms.dbo.CSOTAU(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.CSOTEMP'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.CSOTEMP" >>>>>'
go

setuser 'dbo'
go 

create table CSOTEMP (
	tau#                            id                                   null,
	cso_ut                          dt8                                  null,
	hst                             r4                                   null,
	uthh                            numeric(18,6)                        null,
	tau                             r4                                   null,
	tau_rms                         r4                                   null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.DBLOG'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.DBLOG" >>>>>'
go

setuser 'dbo'
go 

create table DBLOG (
	projid                          vc16                                 null,
	scan                            r8                                   null,
	utstart                         dt8                                  null,
	utstop                          dt8                                  null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'DBLOGut1ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "DBLOGut1ind" >>>>>'
go 

create unique clustered index DBLOGut1ind 
on jcmt_tms.dbo.DBLOG(utstart)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'DBLOGut2ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "DBLOGut2ind" >>>>>'
go 

create nonclustered index DBLOGut2ind 
on jcmt_tms.dbo.DBLOG(utstop)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'DBLOGprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "DBLOGprojind" >>>>>'
go 

create nonclustered index DBLOGprojind 
on jcmt_tms.dbo.DBLOG(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.FLUX'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.FLUX" >>>>>'
go

setuser 'dbo'
go 

create table FLUX (
	flux#                           id                                   null,
	ut                              r8                                   null,
	run                             i2                                   null,
	flux                            r8                                   null,
	sn                              r8                                   null,
	object                          vc16                                 null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.FLUX to dbo Granted by dbo
go
Grant Select on dbo.FLUX to jcmtstaff Granted by dbo
go
Grant Select on dbo.FLUX to observers Granted by dbo
go
Grant Select on dbo.FLUX to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'FLUXflux#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "FLUXflux#ind" >>>>>'
go 

create unique clustered index FLUXflux#ind 
on jcmt_tms.dbo.FLUX(flux#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'FLUXutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "FLUXutind" >>>>>'
go 

create nonclustered index FLUXutind 
on jcmt_tms.dbo.FLUX(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'FLUXobject'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "FLUXobject" >>>>>'
go 

create nonclustered index FLUXobject 
on jcmt_tms.dbo.FLUX(object)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.LINE'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.LINE" >>>>>'
go

setuser 'dbo'
go 

create table LINE (
	line#                           id                                   null,
	line                            vc16                                 null,
	restfrq                         r8                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.LINE to public Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'LINEtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LINEtupind" >>>>>'
go 

create unique nonclustered index LINEtupind 
on jcmt_tms.dbo.LINE(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.LOG'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.LOG" >>>>>'
go

setuser 'dbo'
go 

create table LOG (
	log#                            id                                   null,
	ut                              dt8                                  null,
	proj_id                         vc16                                 null,
	run                             i4                                   null,
	status                          vc16                                 null,
	comment                         varchar(255)                     not null,
	active                          i2                                   null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'LOGlog#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LOGlog#ind" >>>>>'
go 

create unique clustered index LOGlog#ind 
on jcmt_tms.dbo.LOG(log#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'LOGutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LOGutind" >>>>>'
go 

create nonclustered index LOGutind 
on jcmt_tms.dbo.LOG(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_CSOTAU'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_CSOTAU" >>>>>'
go

setuser 'dbo'
go 

create table L_CSOTAU (
	tau#                            id                                   null,
	cso_ut                          dt8                                  null,
	hst                             r4                                   null,
	tau                             r4                                   null,
	tau_rms                         r4                                   null,
	cso_ut_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'lcsotau_csout_idx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "lcsotau_csout_idx" >>>>>'
go 

create unique nonclustered index lcsotau_csout_idx 
on jcmt_tms.dbo.L_CSOTAU(cso_ut)
with ignore_dup_key 
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_NOI'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_NOI" >>>>>'
go

setuser 'dbo'
go 

create table L_NOI (
	noi#                            id                                   null,
	channel                         c3                                   null,
	chop                            r4                                   null,
	chop_err                        r4                                   null,
	cal                             r4                                   null,
	cal_err                         r4                                   null,
	quality                         i4                                   null,
	ut                              datetime                         not null,
	chop_thr                        r4                                   null,
	source                          vc16                                 null,
	az                              r4                                   null,
	el                              r4                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_SAOPHA'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_SAOPHA" >>>>>'
go

setuser 'dbo'
go 

create table L_SAOPHA (
	pha#                            id                                   null,
	sao_ut                          dt8                                  null,
	hst                             r4                                   null,
	pha                             r4                                   null,
	seeing                          r4                                   null,
	sao_ut_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_SCA'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_SCA" >>>>>'
go

setuser 'dbo'
go 

create table L_SCA (
	sca#                            id                                   null,
	ut                              dt8                                  null,
	ses#                            id                                   null,
	sou#                            id                                   null,
	wea#                            id                                   null,
	tel#                            id                                   null,
	gsdfile                         vc120                                null,
	projid                          vc16                                 null,
	scan                            r8                                   null,
	object                          vc16                                 null,
	object2                         vc16                                 null,
	frontend                        vc16                                 null,
	frontype                        vc16                                 null,
	nofchan                         i4                                   null,
	backend                         vc16                                 null,
	backtype                        vc16                                 null,
	nobchan                         i4                                   null,
	norsect                         i4                                   null,
	chopping                        l1                                   null,
	obscal                          l1                                   null,
	obscen                          l1                                   null,
	obsfly                          l1                                   null,
	obsfocus                        l1                                   null,
	obsmap                          l1                                   null,
	obsmode                         vc16                                 null,
	coordcd                         vc16                                 null,
	coordcd2                        i4                                   null,
	radate                          r8                                   null,
	decdate                         r8                                   null,
	az                              r8                                   null,
	el                              r8                                   null,
	restfrq1                        r8                                   null,
	restfrq2                        r8                                   null,
	velocity                        r8                                   null,
	vdef                            vc16                                 null,
	vref                            vc16                                 null,
	ut1c                            r8                                   null,
	lst                             r8                                   null,
	samprat                         i4                                   null,
	nocycles                        i4                                   null,
	cycllen                         i4                                   null,
	noscans                         i4                                   null,
	noscnpts                        i4                                   null,
	nocycpts                        i4                                   null,
	xcell0                          r4                                   null,
	ycell0                          r4                                   null,
	xref                            r8                                   null,
	yref                            r8                                   null,
	xsource                         r8                                   null,
	ysource                         r8                                   null,
	frame                           vc16                                 null,
	frame2                          i4                                   null,
	xyangle                         r8                                   null,
	deltax                          r8                                   null,
	deltay                          r8                                   null,
	scanang                         r8                                   null,
	yposang                         r8                                   null,
	afocusv                         r4                                   null,
	afocush                         r4                                   null,
	afocusr                         r4                                   null,
	tcold                           r4                                   null,
	thot                            r4                                   null,
	noswvar                         i4                                   null,
	nophase                         i4                                   null,
	snstvty                         i4                                   null,
	phase                           i4                                   null,
	mapunit                         vc16                                 null,
	nomapdim                        i4                                   null,
	nopts                           i4                                   null,
	noxpts                          i4                                   null,
	noypts                          i4                                   null,
	reversal                        l1                                   null,
	directn                         vc16                                 null,
	xsign                           l1                                   null,
	ysign                           l1                                   null,
	spect                           r8                                   null,
	resp                            r4                                   null,
	stdspect                        r8                                   null,
	trms                            r8                                   null,
	radate_int                      i4                                   null,
	decdate_int                     i4                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null,
	polarity                        vc6                                  null,
	sbmode                          vc6                                  null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'LSCAsca#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSCAsca#ind" >>>>>'
go 

create unique clustered index LSCAsca#ind 
on jcmt_tms.dbo.L_SCA(sca#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'LSCAtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSCAtupind" >>>>>'
go 

create nonclustered index LSCAtupind 
on jcmt_tms.dbo.L_SCA(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_SCU'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_SCU" >>>>>'
go

setuser 'dbo'
go 

create table L_SCU (
	scu#                            id                                   null,
	ut                              dt8                                  null,
	scu_id                          vc64                                 null,
	sdffile                         vc64                                 null,
	proj_id                         vc16                                 null,
	run                             i2                                   null,
	release_date                    dt8                                  null,
	raj2000                         r8                                   null,
	decj2000                        r8                                   null,
	object                          vc16                                 null,
	obj_type                        vc16                                 null,
	accept                          vc16                                 null,
	align_ax                        vc8                                  null,
	align_sh                        r8                                   null,
	alt_obs                         r8                                   null,
	amend                           r4                                   null,
	amstart                         r4                                   null,
	apend                           r4                                   null,
	apstart                         r4                                   null,
	atend                           r4                                   null,
	atstart                         r4                                   null,
	boloms                          vc16                                 null,
	calibrtr                        c1                                   null,
	cal_frq                         r8                                   null,
	cent_crd                        vc8                                  null,
	chop_crd                        vc8                                  null,
	chop_frq                        r8                                   null,
	chop_fun                        vc16                                 null,
	chop_pa                         r4                                   null,
	chop_thr                        r4                                   null,
	data_dir                        vc16                                 null,
	drgroup                         vc16                                 null,
	drrecipe                        vc24                                 null,
	end_azd                         r4                                   null,
	end_el                          r4                                   null,
	end_eld                         r4                                   null,
	equinox                         i4                                   null,
	exposed                         r4                                   null,
	exp_no                          i4                                   null,
	exp_time                        r8                                   null,
	e_per_i                         i2                                   null,
	filter                          vc16                                 null,
	focus_sh                        r8                                   null,
	gain                            i2                                   null,
	hstend                          vc20                                 null,
	hststart                        vc20                                 null,
	humend                          i2                                   null,
	humstart                        i2                                   null,
	int_no                          i2                                   null,
	jigl_cnt                        i2                                   null,
	jigl_nam                        vc40                                 null,
	j_per_s                         i2                                   null,
	j_repeat                        i2                                   null,
	locl_crd                        vc16                                 null,
	long                            vc16                                 null,
	lat                             vc16                                 null,
	long2                           vc16                                 null,
	lat2                            vc16                                 null,
	map_hght                        i2                                   null,
	map_pa                          r8                                   null,
	map_wdth                        i2                                   null,
	map_x                           r4                                   null,
	map_y                           r4                                   null,
	max_el                          r8                                   null,
	meandec                         r8                                   null,
	meanra                          r8                                   null,
	meas_no                         i4                                   null,
	min_el                          r8                                   null,
	mjd1                            r8                                   null,
	mjd2                            r8                                   null,
	mode                            vc16                                 null,
	n_int                           i2                                   null,
	n_measur                        i2                                   null,
	observer                        vc16                                 null,
	sam_crds                        vc16                                 null,
	sam_dx                          r8                                   null,
	sam_dy                          r8                                   null,
	sam_mode                        vc8                                  null,
	sam_pa                          r8                                   null,
	scan_rev                        c1                                   null,
	start_el                        r8                                   null,
	state                           vc40                                 null,
	stend                           vc16                                 null,
	strt_azd                        r8                                   null,
	strt_eld                        r8                                   null,
	ststart                         vc16                                 null,
	swtch_md                        vc8                                  null,
	swtch_no                        i2                                   null,
	s_per_e                         i2                                   null,
	utdate                          vc16                                 null,
	utend                           vc20                                 null,
	utstart                         vc20                                 null,
	wvplate                         i2                                   null,
	wpltname                        vc64                                 null,
	align_dx                        r4                                   null,
	align_dy                        r4                                   null,
	align_x                         r4                                   null,
	align_y                         r4                                   null,
	az_err                          r4                                   null,
	chopping                        c1                                   null,
	el_err                          r4                                   null,
	focus_dz                        r4                                   null,
	focus_z                         r4                                   null,
	seeing                          r4                                   null,
	see_date                        vc16                                 null,
	tau_225                         r8                                   null,
	tau_date                        vc16                                 null,
	tau_rms                         r8                                   null,
	uaz                             r8                                   null,
	uel                             r8                                   null,
	ut_date                         vc16                                 null,
	chop_lg                         i4                                   null,
	chop_pd                         r4                                   null,
	cntr_du3                        r4                                   null,
	cntr_du4                        r4                                   null,
	etatel_1                        r4                                   null,
	etatel_2                        r4                                   null,
	etatel_3                        r4                                   null,
	filt_350                        i2                                   null,
	filt_450                        i2                                   null,
	filt_750                        i2                                   null,
	filt_850                        i2                                   null,
	filt_1100                       i2                                   null,
	filt_1350                       i2                                   null,
	filt_2000                       i2                                   null,
	filt_1                          vc8                                  null,
	filt_2                          vc8                                  null,
	filt_3                          vc8                                  null,
	flat                            vc40                                 null,
	meas_bol                        vc16                                 null,
	n_bols                          i2                                   null,
	n_subs                          i2                                   null,
	phot_bbf                        vc40                                 null,
	rebin                           vc8                                  null,
	ref_adc                         r8                                   null,
	ref_chan                        r8                                   null,
	sam_time                        i4                                   null,
	simulate                        c1                                   null,
	sub_1                           vc8                                  null,
	sub_2                           vc8                                  null,
	sub_3                           vc8                                  null,
	s_gd_bol                        vc8                                  null,
	s_guard                         c1                                   null,
	tauz_1                          r4                                   null,
	tauz_2                          r4                                   null,
	tauz_3                          r4                                   null,
	t_amb                           r4                                   null,
	t_cold_1                        r4                                   null,
	t_cold_2                        r4                                   null,
	t_cold_3                        r4                                   null,
	t_hot                           r4                                   null,
	t_tel                           r4                                   null,
	wave_1                          r4                                   null,
	wave_2                          r4                                   null,
	wave_3                          r4                                   null,
	ut_dmf                          i4                                   null,
	ra_int                          i4                                   null,
	dec_int                         i4                                   null,
	release_date_dmf                i4                                   null,
	msbid                           vc40                                 null,
	tuple_id                        id                               not null,
	obsid                           varchar(48)                      not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'LSCUscu#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSCUscu#ind" >>>>>'
go 

create unique clustered index LSCUscu#ind 
on jcmt_tms.dbo.L_SCU(scu#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'LSCUtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSCUtupind" >>>>>'
go 

create nonclustered index LSCUtupind 
on jcmt_tms.dbo.L_SCU(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_SES'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_SES" >>>>>'
go

setuser 'dbo'
go 

create table L_SES (
	ses#                            id                                   null,
	utstart                         dt8                                  null,
	utstop                          dt8                                  null,
	projid                          vc16                                 null,
	obsid                           vc16                                 null,
	observer                        vc16                                 null,
	operator                        vc16                                 null,
	telescop                        vc16                                 null,
	longitud                        r8                                   null,
	latitude                        r8                                   null,
	height                          r8                                   null,
	mounting                        vc16                                 null,
	utstart_dmf                     i4                                   null,
	utstop_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'LSESses#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSESses#ind" >>>>>'
go 

create unique clustered index LSESses#ind 
on jcmt_tms.dbo.L_SES(ses#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'LSEStupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSEStupind" >>>>>'
go 

create nonclustered index LSEStupind 
on jcmt_tms.dbo.L_SES(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_SOU'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_SOU" >>>>>'
go

setuser 'dbo'
go 

create table L_SOU (
	sou#                            id                                   null,
	ut                              dt8                                  null,
	object                          vc16                                 null,
	cenmove                         l1                                   null,
	epoch                           r8                                   null,
	epochtyp                        vc16                                 null,
	epocra                          r8                                   null,
	epocdec                         r8                                   null,
	raj2000                         r8                                   null,
	decj2000                        r8                                   null,
	gallong                         r8                                   null,
	gallat                          r8                                   null,
	epocra_int                      i4                                   null,
	epocdec_int                     i4                                   null,
	raj2000_int                     i4                                   null,
	decj2000_int                    i4                                   null,
	gallong_int                     i4                                   null,
	gallat_int                      i4                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'LSOUsou#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSOUsou#ind" >>>>>'
go 

create unique clustered index LSOUsou#ind 
on jcmt_tms.dbo.L_SOU(sou#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'LSOUallind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSOUallind" >>>>>'
go 

create nonclustered index LSOUallind 
on jcmt_tms.dbo.L_SOU(object, epoch, epocra_int, epocdec_int)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'LSOUtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSOUtupind" >>>>>'
go 

create nonclustered index LSOUtupind 
on jcmt_tms.dbo.L_SOU(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_SPH'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_SPH" >>>>>'
go

setuser 'dbo'
go 

create table L_SPH (
	sph#                            id                                   null,
	sca#                            id                                   null,
	ut                              dt8                                  null,
	projid                          vc16                                 null,
	scan                            i4                                   null,
	band                            i4                                   null,
	backend                         vc16                                 null,
	filter                          vc16                                 null,
	aperture                        vc16                                 null,
	spect                           r8                                   null,
	resp                            r4                                   null,
	stdspect                        r8                                   null,
	trms                            r8                                   null,
	cyclrev                         i4                                   null,
	sntvtyrg                        vc16                                 null,
	timecnst                        vc16                                 null,
	freqres                         r4                                   null,
	obsfreq                         r8                                   null,
	restfreq                        r8                                   null,
	befenulo                        r8                                   null,
	bw                              r4                                   null,
	trx                             r4                                   null,
	stsys                           r4                                   null,
	tsky                            r4                                   null,
	ttel                            r4                                   null,
	gains                           r4                                   null,
	tcal                            r4                                   null,
	tauh2o                          r4                                   null,
	eta_sky                         r4                                   null,
	alpha                           r4                                   null,
	g_s                             r4                                   null,
	eta_tel                         r4                                   null,
	t_sky_im                        r4                                   null,
	eta_sky_im                      r4                                   null,
	t_sys_im                        r4                                   null,
	ta_sky                          r4                                   null,
	cm                              i4                                   null,
	bm                              i4                                   null,
	overlap                         r4                                   null,
	bescon                          i4                                   null,
	nobesdch                        i4                                   null,
	besspec                         i4                                   null,
	betotif                         r8                                   null,
	befesb                          i4                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null,
	mixer_id                        i4                                   null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'LSPHsph#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSPHsph#ind" >>>>>'
go 

create unique clustered index LSPHsph#ind 
on jcmt_tms.dbo.L_SPH(sph#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'LSPHtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSPHtupind" >>>>>'
go 

create nonclustered index LSPHtupind 
on jcmt_tms.dbo.L_SPH(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_SUB'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_SUB" >>>>>'
go

setuser 'dbo'
go 

create table L_SUB (
	sub#                            id                                   null,
	sca#                            id                                   null,
	ut                              dt8                                  null,
	projid                          vc16                                 null,
	scan                            r8                                   null,
	subscan                         i2                                   null,
	xcell0                          r4                                   null,
	ycell0                          r4                                   null,
	lst                             r8                                   null,
	airmass                         r8                                   null,
	samprat                         i4                                   null,
	nocycles                        i4                                   null,
	ncycle                          i4                                   null,
	cycllen                         i4                                   null,
	noscans                         i4                                   null,
	nscan                           i4                                   null,
	noscnpts                        i4                                   null,
	nocycpts                        i4                                   null,
	ncycpts                         i4                                   null,
	intgr                           i4                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'LSUBsub#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSUBsub#ind" >>>>>'
go 

create unique clustered index LSUBsub#ind 
on jcmt_tms.dbo.L_SUB(sub#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'LSUBtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LSUBtupind" >>>>>'
go 

create nonclustered index LSUBtupind 
on jcmt_tms.dbo.L_SUB(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_TEL'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_TEL" >>>>>'
go

setuser 'dbo'
go 

create table L_TEL (
	tel#                            id                                   null,
	fe#                             id                                   null,
	eff#                            id                                   null,
	be#                             id                                   null,
	smu#                            id                                   null,
	poi#                            id                                   null,
	foc#                            id                                   null,
	utstart                         dt8                                  null,
	utstop                          dt8                                  null,
	projid                          vc16                                 null,
	scan                            i4                                   null,
	frontend                        vc16                                 null,
	frontype                        vc16                                 null,
	nofchan                         i4                                   null,
	backend                         vc16                                 null,
	backtype                        vc16                                 null,
	noifpbes                        i4                                   null,
	nobchan                         i4                                   null,
	config                          i4                                   null,
	outputt                         vc16                                 null,
	calsrc                          vc16                                 null,
	shftfrac                        r4                                   null,
	badchv                          r8                                   null,
	norchan                         i4                                   null,
	norsect                         i4                                   null,
	dataunit                        vc16                                 null,
	swmode                          vc16                                 null,
	caltask                         vc16                                 null,
	caltype                         vc16                                 null,
	redmode                         vc16                                 null,
	waveform                        vc16                                 null,
	chopfreq                        r4                                   null,
	chopcoor                        vc16                                 null,
	chopthrw                        r4                                   null,
	chopdirn                        r4                                   null,
	ewtilt                          r4                                   null,
	nstilt                          r4                                   null,
	ew_scale                        r4                                   null,
	ns_scale                        r4                                   null,
	ew_encode                       i4                                   null,
	ns_encode                       i4                                   null,
	xpoint                          r8                                   null,
	ypoint                          r8                                   null,
	uxpnt                           r8                                   null,
	uypnt                           r8                                   null,
	focusv                          r4                                   null,
	focusl                          r4                                   null,
	focusr                          r4                                   null,
	utstart_dmf                     i4                                   null,
	utstop_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'LTELtel#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LTELtel#ind" >>>>>'
go 

create unique clustered index LTELtel#ind 
on jcmt_tms.dbo.L_TEL(tel#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'LTELtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LTELtupind" >>>>>'
go 

create nonclustered index LTELtupind 
on jcmt_tms.dbo.L_TEL(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.L_WEA'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.L_WEA" >>>>>'
go

setuser 'dbo'
go 

create table L_WEA (
	wea#                            id                                   null,
	utstart                         dt8                                  null,
	utstop                          dt8                                  null,
	projid                          vc16                                 null,
	scan                            i4                                   null,
	ws#                             id                                   null,
	tau#                            id                                   null,
	pha#                            id                                   null,
	tamb                            r4                                   null,
	pressure                        r4                                   null,
	humidity                        r4                                   null,
	tau                             r4                                   null,
	tau_rms                         r4                                   null,
	tau_date                        dt8                                  null,
	pha                             r4                                   null,
	pha_date                        dt8                                  null,
	utstart_dmf                     i4                                   null,
	utstop_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'LWEAwea#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LWEAwea#ind" >>>>>'
go 

create unique clustered index LWEAwea#ind 
on jcmt_tms.dbo.L_WEA(wea#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'LWEAtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "LWEAtupind" >>>>>'
go 

create nonclustered index LWEAtupind 
on jcmt_tms.dbo.L_WEA(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.MIXER'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.MIXER" >>>>>'
go

setuser 'dbo'
go 

create table MIXER (
	mix#                            numeric(9,0)                     identity,
	date                            dt8                                  null,
	mixid                           i2                                   null,
	trx_mean                        r8                                   null,
	trx_sd                          r8                                   null,
	tsys_mean                       r8                                   null,
	tsys_sd                         r8                                   null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.MIXER to public Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'MIXdatemix'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "MIXdatemix" >>>>>'
go 

create unique clustered index MIXdatemix 
on jcmt_tms.dbo.MIXER(date, mixid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'MIXmixid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "MIXmixid" >>>>>'
go 

create nonclustered index MIXmixid 
on jcmt_tms.dbo.MIXER(mix#)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.MOTOR'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.MOTOR" >>>>>'
go

setuser 'dbo'
go 

create table MOTOR (
	motor#                          id                                   null,
	ut                              dt8                                  null,
	userid                          vc16                                 null,
	sector                          i4                                   null,
	mtrInSector                     i4                                   null,
	wRefFound                       bit                              not null,
	phaseErr                        bit                              not null,
	slotErr                         bit                              not null,
	wheelErr                        bit                              not null,
	slotTB                          bit                              not null,
	wheelTB                         bit                              not null,
	phaseMSB                        bit                              not null,
	phase2                          bit                              not null,
	phase1                          bit                              not null,
	phaseLSB                        bit                              not null,
	softMask                        bit                              not null,
	phaseMask                       bit                              not null,
	slotMask                        bit                              not null,
	wheelMask                       bit                              not null,
	motorInvalid                    bit                              not null,
	motorDisable                    bit                              not null,
	phase                           i4                                   null,
	crpos                           i4                                   null,
	stepr                           i4                                   null,
	datum                           i4                                   null,
	hilim                           i4                                   null,
	lolim                           i4                                   null,
	hslot                           i4                                   null,
	lslot                           i4                                   null,
	wlref                           i4                                   null,
	wlent                           i4                                   null,
	activ                           i4                                   null,
	diff                            i4                                   null,
	notes                           vc40                                 null,
	tuple_id                        i4                                   null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.MOTOR to observers Granted by dbo
go
Grant Select on dbo.MOTOR to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'MOTORmotorind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "MOTORmotorind" >>>>>'
go 

create unique clustered index MOTORmotorind 
on jcmt_tms.dbo.MOTOR(motor#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'MOTORutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "MOTORutind" >>>>>'
go 

create nonclustered index MOTORutind 
on jcmt_tms.dbo.MOTOR(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.NOI'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.NOI" >>>>>'
go

setuser 'dbo'
go 

create table NOI (
	noi#                            id                                   null,
	channel                         c3                                   null,
	chop                            r4                                   null,
	chop_err                        r4                                   null,
	cal                             r4                                   null,
	cal_err                         r4                                   null,
	quality                         i4                                   null,
	ut                              datetime                         not null,
	chop_thr                        r4                                   null,
	source                          vc16                                 null,
	az                              r4                                   null,
	el                              r4                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.NOI to dbo Granted by dbo
go
Grant Select on dbo.NOI to jcmtstaff Granted by dbo
go
Grant Select on dbo.NOI to observers Granted by dbo
go
Grant Select on dbo.NOI to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'NOInoi#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "NOInoi#ind" >>>>>'
go 

create unique clustered index NOInoi#ind 
on jcmt_tms.dbo.NOI(noi#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'NOIutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "NOIutind" >>>>>'
go 

create nonclustered index NOIutind 
on jcmt_tms.dbo.NOI(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'NOIutdmfind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "NOIutdmfind" >>>>>'
go 

create nonclustered index NOIutdmfind 
on jcmt_tms.dbo.NOI(ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'NOItupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "NOItupind" >>>>>'
go 

create unique nonclustered index NOItupind 
on jcmt_tms.dbo.NOI(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.PHA'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.PHA" >>>>>'
go

setuser 'dbo'
go 

create table PHA (
	pha#                            id                                   null,
	sao_ut                          dt8                                  null,
	hst                             r4                                   null,
	pha                             r4                                   null,
	seeing                          r4                                   null,
	sao_ut_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.PHA to dbo Granted by dbo
go
Grant Select on dbo.PHA to jcmtstaff Granted by dbo
go
Grant Select on dbo.PHA to observers Granted by dbo
go
Grant Select on dbo.PHA to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'PHApha#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "PHApha#ind" >>>>>'
go 

create unique clustered index PHApha#ind 
on jcmt_tms.dbo.PHA(pha#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'PHAsaoutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "PHAsaoutind" >>>>>'
go 

create nonclustered index PHAsaoutind 
on jcmt_tms.dbo.PHA(sao_ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'PHAsaodmfind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "PHAsaodmfind" >>>>>'
go 

create nonclustered index PHAsaodmfind 
on jcmt_tms.dbo.PHA(sao_ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'PHAtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "PHAtupind" >>>>>'
go 

create nonclustered index PHAtupind 
on jcmt_tms.dbo.PHA(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.RXTAU'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.RXTAU" >>>>>'
go

setuser 'dbo'
go 

create table RXTAU (
	projid                          vc16                                 null,
	scan                            r8                                   null,
	frontend                        vc16                                 null,
	ut                              dt8                                  null,
	tau                             r4                                   null,
	inttime                         r4                                   null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'RXTAUut'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "RXTAUut" >>>>>'
go 

create unique clustered index RXTAUut 
on jcmt_tms.dbo.RXTAU(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'RXrx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "RXrx" >>>>>'
go 

create nonclustered index RXrx 
on jcmt_tms.dbo.RXTAU(frontend)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'RXtau'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "RXtau" >>>>>'
go 

create nonclustered index RXtau 
on jcmt_tms.dbo.RXTAU(tau)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'RXprojid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "RXprojid" >>>>>'
go 

create nonclustered index RXprojid 
on jcmt_tms.dbo.RXTAU(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.SAOPHA'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.SAOPHA" >>>>>'
go

setuser 'dbo'
go 

create table SAOPHA (
	pha#                            id                                   null,
	sao_ut                          dt8                                  null,
	hst                             r4                                   null,
	pha                             r4                                   null,
	seeing                          r4                                   null,
	sao_ut_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.SAOPHA to dbo Granted by dbo
go
Grant Select on dbo.SAOPHA to jcmtstaff Granted by dbo
go
Grant Select on dbo.SAOPHA to observers Granted by dbo
go
Grant Select on dbo.SAOPHA to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'SAOPHApha#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SAOPHApha#ind" >>>>>'
go 

create unique clustered index SAOPHApha#ind 
on jcmt_tms.dbo.SAOPHA(pha#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SAOPHAsaoutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SAOPHAsaoutind" >>>>>'
go 

create nonclustered index SAOPHAsaoutind 
on jcmt_tms.dbo.SAOPHA(sao_ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SAOPHAsaodmfind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SAOPHAsaodmfind" >>>>>'
go 

create nonclustered index SAOPHAsaodmfind 
on jcmt_tms.dbo.SAOPHA(sao_ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SAOPHAtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SAOPHAtupind" >>>>>'
go 

create nonclustered index SAOPHAtupind 
on jcmt_tms.dbo.SAOPHA(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.SCA'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.SCA" >>>>>'
go

setuser 'dbo'
go 

create table SCA (
	sca#                            id                                   null,
	ut                              dt8                                  null,
	ses#                            id                                   null,
	sou#                            id                                   null,
	wea#                            id                                   null,
	tel#                            id                                   null,
	gsdfile                         vc120                                null,
	projid                          vc16                                 null,
	scan                            r8                                   null,
	object                          vc16                                 null,
	object2                         vc16                                 null,
	frontend                        vc16                                 null,
	frontype                        vc16                                 null,
	nofchan                         i4                                   null,
	backend                         vc16                                 null,
	backtype                        vc16                                 null,
	nobchan                         i4                                   null,
	norsect                         i4                                   null,
	chopping                        l1                                   null,
	obscal                          l1                                   null,
	obscen                          l1                                   null,
	obsfly                          l1                                   null,
	obsfocus                        l1                                   null,
	obsmap                          l1                                   null,
	obsmode                         vc16                                 null,
	coordcd                         vc16                                 null,
	coordcd2                        i4                                   null,
	radate                          r8                                   null,
	decdate                         r8                                   null,
	az                              r8                                   null,
	el                              r8                                   null,
	restfrq1                        r8                                   null,
	restfrq2                        r8                                   null,
	velocity                        r8                                   null,
	vdef                            vc16                                 null,
	vref                            vc16                                 null,
	ut1c                            r8                                   null,
	lst                             r8                                   null,
	samprat                         i4                                   null,
	nocycles                        i4                                   null,
	cycllen                         i4                                   null,
	noscans                         i4                                   null,
	noscnpts                        i4                                   null,
	nocycpts                        i4                                   null,
	xcell0                          r4                                   null,
	ycell0                          r4                                   null,
	xref                            r8                                   null,
	yref                            r8                                   null,
	xsource                         r8                                   null,
	ysource                         r8                                   null,
	frame                           vc16                                 null,
	frame2                          i4                                   null,
	xyangle                         r8                                   null,
	deltax                          r8                                   null,
	deltay                          r8                                   null,
	scanang                         r8                                   null,
	yposang                         r8                                   null,
	afocusv                         r4                                   null,
	afocush                         r4                                   null,
	afocusr                         r4                                   null,
	tcold                           r4                                   null,
	thot                            r4                                   null,
	noswvar                         i4                                   null,
	nophase                         i4                                   null,
	snstvty                         i4                                   null,
	phase                           i4                                   null,
	mapunit                         vc16                                 null,
	nomapdim                        i4                                   null,
	nopts                           i4                                   null,
	noxpts                          i4                                   null,
	noypts                          i4                                   null,
	reversal                        l1                                   null,
	directn                         vc16                                 null,
	xsign                           l1                                   null,
	ysign                           l1                                   null,
	spect                           r8                                   null,
	resp                            r4                                   null,
	stdspect                        r8                                   null,
	trms                            r8                                   null,
	radate_int                      i4                                   null,
	decdate_int                     i4                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null,
	polarity                        vc6                                  null,
	sbmode                          vc6                                  null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.SCA to dbo Granted by dbo
go
Grant Select on dbo.SCA to jcmtstaff Granted by dbo
go
Grant Select on dbo.SCA to observers Granted by dbo
go
Grant Select on dbo.SCA to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'SCAsca#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCAsca#ind" >>>>>'
go 

create unique clustered index SCAsca#ind 
on jcmt_tms.dbo.SCA(sca#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCAutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCAutind" >>>>>'
go 

create nonclustered index SCAutind 
on jcmt_tms.dbo.SCA(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCAprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCAprojind" >>>>>'
go 

create nonclustered index SCAprojind 
on jcmt_tms.dbo.SCA(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCAobjind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCAobjind" >>>>>'
go 

create nonclustered index SCAobjind 
on jcmt_tms.dbo.SCA(object)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCAsesind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCAsesind" >>>>>'
go 

create nonclustered index SCAsesind 
on jcmt_tms.dbo.SCA(ses#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCAsouind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCAsouind" >>>>>'
go 

create nonclustered index SCAsouind 
on jcmt_tms.dbo.SCA(sou#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCAweaind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCAweaind" >>>>>'
go 

create nonclustered index SCAweaind 
on jcmt_tms.dbo.SCA(wea#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCAtelind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCAtelind" >>>>>'
go 

create nonclustered index SCAtelind 
on jcmt_tms.dbo.SCA(tel#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCAutdmfind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCAutdmfind" >>>>>'
go 

create nonclustered index SCAutdmfind 
on jcmt_tms.dbo.SCA(ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCAtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCAtupind" >>>>>'
go 

create unique nonclustered index SCAtupind 
on jcmt_tms.dbo.SCA(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.SCU'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.SCU" >>>>>'
go

setuser 'dbo'
go 

create table SCU (
	scu#                            id                                   null,
	ut                              dt8                                  null,
	scu_id                          vc64                                 null,
	sdffile                         vc64                                 null,
	proj_id                         vc16                                 null,
	run                             i2                                   null,
	release_date                    dt8                                  null,
	raj2000                         r8                                   null,
	decj2000                        r8                                   null,
	object                          vc16                                 null,
	obj_type                        vc16                                 null,
	accept                          vc16                                 null,
	align_ax                        vc8                                  null,
	align_sh                        r8                                   null,
	alt_obs                         r8                                   null,
	amend                           r4                                   null,
	amstart                         r4                                   null,
	apend                           r4                                   null,
	apstart                         r4                                   null,
	atend                           r4                                   null,
	atstart                         r4                                   null,
	boloms                          vc16                                 null,
	calibrtr                        c1                                   null,
	cal_frq                         r8                                   null,
	cent_crd                        vc8                                  null,
	chop_crd                        vc8                                  null,
	chop_frq                        r8                                   null,
	chop_fun                        vc16                                 null,
	chop_pa                         r4                                   null,
	chop_thr                        r4                                   null,
	data_dir                        vc16                                 null,
	drgroup                         vc16                                 null,
	drrecipe                        vc24                                 null,
	end_azd                         r4                                   null,
	end_el                          r4                                   null,
	end_eld                         r4                                   null,
	equinox                         i4                                   null,
	exposed                         r4                                   null,
	exp_no                          i4                                   null,
	exp_time                        r8                                   null,
	e_per_i                         i2                                   null,
	filter                          vc16                                 null,
	focus_sh                        r8                                   null,
	gain                            i2                                   null,
	hstend                          vc20                                 null,
	hststart                        vc20                                 null,
	humend                          i2                                   null,
	humstart                        i2                                   null,
	int_no                          i2                                   null,
	jigl_cnt                        i2                                   null,
	jigl_nam                        vc40                                 null,
	j_per_s                         i2                                   null,
	j_repeat                        i2                                   null,
	locl_crd                        vc16                                 null,
	long                            vc16                                 null,
	lat                             vc16                                 null,
	long2                           vc16                                 null,
	lat2                            vc16                                 null,
	map_hght                        i2                                   null,
	map_pa                          r8                                   null,
	map_wdth                        i2                                   null,
	map_x                           r4                                   null,
	map_y                           r4                                   null,
	max_el                          r8                                   null,
	meandec                         r8                                   null,
	meanra                          r8                                   null,
	meas_no                         i4                                   null,
	min_el                          r8                                   null,
	mjd1                            r8                                   null,
	mjd2                            r8                                   null,
	mode                            vc16                                 null,
	n_int                           i2                                   null,
	n_measur                        i2                                   null,
	observer                        vc16                                 null,
	sam_crds                        vc16                                 null,
	sam_dx                          r8                                   null,
	sam_dy                          r8                                   null,
	sam_mode                        vc8                                  null,
	sam_pa                          r8                                   null,
	scan_rev                        c1                                   null,
	start_el                        r8                                   null,
	state                           vc40                                 null,
	stend                           vc16                                 null,
	strt_azd                        r8                                   null,
	strt_eld                        r8                                   null,
	ststart                         vc16                                 null,
	swtch_md                        vc8                                  null,
	swtch_no                        i2                                   null,
	s_per_e                         i2                                   null,
	utdate                          vc16                                 null,
	utend                           vc20                                 null,
	utstart                         vc20                                 null,
	wvplate                         i2                                   null,
	wpltname                        vc64                                 null,
	align_dx                        r4                                   null,
	align_dy                        r4                                   null,
	align_x                         r4                                   null,
	align_y                         r4                                   null,
	az_err                          r4                                   null,
	chopping                        c1                                   null,
	el_err                          r4                                   null,
	focus_dz                        r4                                   null,
	focus_z                         r4                                   null,
	seeing                          r4                                   null,
	see_date                        vc16                                 null,
	tau_225                         r8                                   null,
	tau_date                        vc16                                 null,
	tau_rms                         r8                                   null,
	uaz                             r8                                   null,
	uel                             r8                                   null,
	ut_date                         vc16                                 null,
	chop_lg                         i4                                   null,
	chop_pd                         r4                                   null,
	cntr_du3                        r4                                   null,
	cntr_du4                        r4                                   null,
	etatel_1                        r4                                   null,
	etatel_2                        r4                                   null,
	etatel_3                        r4                                   null,
	filt_350                        i2                                   null,
	filt_450                        i2                                   null,
	filt_750                        i2                                   null,
	filt_850                        i2                                   null,
	filt_1100                       i2                                   null,
	filt_1350                       i2                                   null,
	filt_2000                       i2                                   null,
	filt_1                          vc8                                  null,
	filt_2                          vc8                                  null,
	filt_3                          vc8                                  null,
	flat                            vc40                                 null,
	meas_bol                        vc16                                 null,
	n_bols                          i2                                   null,
	n_subs                          i2                                   null,
	phot_bbf                        vc40                                 null,
	rebin                           vc8                                  null,
	ref_adc                         r8                                   null,
	ref_chan                        r8                                   null,
	sam_time                        i4                                   null,
	simulate                        c1                                   null,
	sub_1                           vc8                                  null,
	sub_2                           vc8                                  null,
	sub_3                           vc8                                  null,
	s_gd_bol                        vc8                                  null,
	s_guard                         c1                                   null,
	tauz_1                          r4                                   null,
	tauz_2                          r4                                   null,
	tauz_3                          r4                                   null,
	t_amb                           r4                                   null,
	t_cold_1                        r4                                   null,
	t_cold_2                        r4                                   null,
	t_cold_3                        r4                                   null,
	t_hot                           r4                                   null,
	t_tel                           r4                                   null,
	wave_1                          r4                                   null,
	wave_2                          r4                                   null,
	wave_3                          r4                                   null,
	ut_dmf                          i4                                   null,
	ra_int                          i4                                   null,
	dec_int                         i4                                   null,
	release_date_dmf                i4                                   null,
	msbid                           vc40                                 null,
	tuple_id                        id                               not null,
	obsid                           varchar(48)                      not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.SCU to dbo Granted by dbo
go
Grant Select on dbo.SCU to jcmtstaff Granted by dbo
go
Grant Select on dbo.SCU to observers Granted by dbo
go
Grant Select on dbo.SCU to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'SCUscu#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUscu#ind" >>>>>'
go 

create unique clustered index SCUscu#ind 
on jcmt_tms.dbo.SCU(scu#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCUutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUutind" >>>>>'
go 

create nonclustered index SCUutind 
on jcmt_tms.dbo.SCU(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCUscuid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUscuid" >>>>>'
go 

create unique nonclustered index SCUscuid 
on jcmt_tms.dbo.SCU(scu_id)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCUutdmfind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUutdmfind" >>>>>'
go 

create nonclustered index SCUutdmfind 
on jcmt_tms.dbo.SCU(ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCUutdate'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUutdate" >>>>>'
go 

create nonclustered index SCUutdate 
on jcmt_tms.dbo.SCU(utdate)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCUprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUprojind" >>>>>'
go 

create nonclustered index SCUprojind 
on jcmt_tms.dbo.SCU(proj_id)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCUobjind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUobjind" >>>>>'
go 

create nonclustered index SCUobjind 
on jcmt_tms.dbo.SCU(object)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCUrajind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUrajind" >>>>>'
go 

create nonclustered index SCUrajind 
on jcmt_tms.dbo.SCU(ra_int)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCUdecjind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUdecjind" >>>>>'
go 

create nonclustered index SCUdecjind 
on jcmt_tms.dbo.SCU(dec_int)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCUmsbid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUmsbid" >>>>>'
go 

create nonclustered index SCUmsbid 
on jcmt_tms.dbo.SCU(msbid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SCUtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SCUtupind" >>>>>'
go 

create unique nonclustered index SCUtupind 
on jcmt_tms.dbo.SCU(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.SES'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.SES" >>>>>'
go

setuser 'dbo'
go 

create table SES (
	ses#                            id                                   null,
	utstart                         dt8                                  null,
	utstop                          dt8                                  null,
	projid                          vc16                                 null,
	obsid                           vc16                                 null,
	observer                        vc16                                 null,
	operator                        vc16                                 null,
	telescop                        vc16                                 null,
	longitud                        r8                                   null,
	latitude                        r8                                   null,
	height                          r8                                   null,
	mounting                        vc16                                 null,
	utstart_dmf                     i4                                   null,
	utstop_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.SES to dbo Granted by dbo
go
Grant Select on dbo.SES to jcmtstaff Granted by dbo
go
Grant Select on dbo.SES to observers Granted by dbo
go
Grant Select on dbo.SES to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'SESses#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SESses#ind" >>>>>'
go 

create unique clustered index SESses#ind 
on jcmt_tms.dbo.SES(ses#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SESprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SESprojind" >>>>>'
go 

create nonclustered index SESprojind 
on jcmt_tms.dbo.SES(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SESutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SESutind" >>>>>'
go 

create nonclustered index SESutind 
on jcmt_tms.dbo.SES(utstart)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SESut1dind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SESut1dind" >>>>>'
go 

create nonclustered index SESut1dind 
on jcmt_tms.dbo.SES(utstart_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SESut2dind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SESut2dind" >>>>>'
go 

create nonclustered index SESut2dind 
on jcmt_tms.dbo.SES(utstop_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SEStupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SEStupind" >>>>>'
go 

create unique nonclustered index SEStupind 
on jcmt_tms.dbo.SES(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.SOU'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.SOU" >>>>>'
go

setuser 'dbo'
go 

create table SOU (
	sou#                            id                                   null,
	ut                              dt8                                  null,
	object                          vc16                                 null,
	cenmove                         l1                                   null,
	epoch                           r8                                   null,
	epochtyp                        vc16                                 null,
	epocra                          r8                                   null,
	epocdec                         r8                                   null,
	raj2000                         r8                                   null,
	decj2000                        r8                                   null,
	gallong                         r8                                   null,
	gallat                          r8                                   null,
	epocra_int                      i4                                   null,
	epocdec_int                     i4                                   null,
	raj2000_int                     i4                                   null,
	decj2000_int                    i4                                   null,
	gallong_int                     i4                                   null,
	gallat_int                      i4                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.SOU to dbo Granted by dbo
go
Grant Select on dbo.SOU to jcmtstaff Granted by dbo
go
Grant Select on dbo.SOU to observers Granted by dbo
go
Grant Select on dbo.SOU to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'SOUsou#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SOUsou#ind" >>>>>'
go 

create unique clustered index SOUsou#ind 
on jcmt_tms.dbo.SOU(sou#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SOUobjind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SOUobjind" >>>>>'
go 

create nonclustered index SOUobjind 
on jcmt_tms.dbo.SOU(object)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SOUraind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SOUraind" >>>>>'
go 

create nonclustered index SOUraind 
on jcmt_tms.dbo.SOU(epocra)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SOUdecind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SOUdecind" >>>>>'
go 

create nonclustered index SOUdecind 
on jcmt_tms.dbo.SOU(epocdec)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SOUiraind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SOUiraind" >>>>>'
go 

create nonclustered index SOUiraind 
on jcmt_tms.dbo.SOU(epocra_int)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SOUidecind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SOUidecind" >>>>>'
go 

create nonclustered index SOUidecind 
on jcmt_tms.dbo.SOU(epocdec_int)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SOUutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SOUutind" >>>>>'
go 

create nonclustered index SOUutind 
on jcmt_tms.dbo.SOU(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SOUutdmfind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SOUutdmfind" >>>>>'
go 

create nonclustered index SOUutdmfind 
on jcmt_tms.dbo.SOU(ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SOUtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SOUtupind" >>>>>'
go 

create unique nonclustered index SOUtupind 
on jcmt_tms.dbo.SOU(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.SPH'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.SPH" >>>>>'
go

setuser 'dbo'
go 

create table SPH (
	sph#                            id                                   null,
	sca#                            id                                   null,
	ut                              dt8                                  null,
	projid                          vc16                                 null,
	scan                            i4                                   null,
	band                            i4                                   null,
	backend                         vc16                                 null,
	filter                          vc16                                 null,
	aperture                        vc16                                 null,
	spect                           r8                                   null,
	resp                            r4                                   null,
	stdspect                        r8                                   null,
	trms                            r8                                   null,
	cyclrev                         i4                                   null,
	sntvtyrg                        vc16                                 null,
	timecnst                        vc16                                 null,
	freqres                         r4                                   null,
	obsfreq                         r8                                   null,
	restfreq                        r8                                   null,
	befenulo                        r8                                   null,
	bw                              r4                                   null,
	trx                             r4                                   null,
	stsys                           r4                                   null,
	tsky                            r4                                   null,
	ttel                            r4                                   null,
	gains                           r4                                   null,
	tcal                            r4                                   null,
	tauh2o                          r4                                   null,
	eta_sky                         r4                                   null,
	alpha                           r4                                   null,
	g_s                             r4                                   null,
	eta_tel                         r4                                   null,
	t_sky_im                        r4                                   null,
	eta_sky_im                      r4                                   null,
	t_sys_im                        r4                                   null,
	ta_sky                          r4                                   null,
	cm                              i4                                   null,
	bm                              i4                                   null,
	overlap                         r4                                   null,
	bescon                          i4                                   null,
	nobesdch                        i4                                   null,
	besspec                         i4                                   null,
	betotif                         r8                                   null,
	befesb                          i4                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null,
	mixer_id                        i4                                   null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.SPH to dbo Granted by dbo
go
Grant Select on dbo.SPH to jcmtstaff Granted by dbo
go
Grant Select on dbo.SPH to observers Granted by dbo
go
Grant Select on dbo.SPH to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'SPHsph#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SPHsph#ind" >>>>>'
go 

create unique clustered index SPHsph#ind 
on jcmt_tms.dbo.SPH(sph#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SPHsca#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SPHsca#ind" >>>>>'
go 

create nonclustered index SPHsca#ind 
on jcmt_tms.dbo.SPH(sca#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SPHprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SPHprojind" >>>>>'
go 

create nonclustered index SPHprojind 
on jcmt_tms.dbo.SPH(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SPHutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SPHutind" >>>>>'
go 

create nonclustered index SPHutind 
on jcmt_tms.dbo.SPH(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SPHutdmfind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SPHutdmfind" >>>>>'
go 

create nonclustered index SPHutdmfind 
on jcmt_tms.dbo.SPH(ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SPHtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SPHtupind" >>>>>'
go 

create unique nonclustered index SPHtupind 
on jcmt_tms.dbo.SPH(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.STA'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.STA" >>>>>'
go

setuser 'dbo'
go 

create table STA (
	sta#                            id                                   null,
	ut                              dt8                                  null,
	sca#                            id                                   null,
	tdv                             r4                                   null,
	sb                              c3                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.STA to dbo Granted by dbo
go
Grant Select on dbo.STA to jcmtstaff Granted by dbo
go
Grant Select on dbo.STA to observers Granted by dbo
go
Grant Select on dbo.STA to visitors Granted by dbo
go
Grant Insert on dbo.STA to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'STAsta#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "STAsta#ind" >>>>>'
go 

create unique clustered index STAsta#ind 
on jcmt_tms.dbo.STA(sta#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'STAscaind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "STAscaind" >>>>>'
go 

create nonclustered index STAscaind 
on jcmt_tms.dbo.STA(sca#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'STAutdind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "STAutdind" >>>>>'
go 

create nonclustered index STAutdind 
on jcmt_tms.dbo.STA(ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'STAtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "STAtupind" >>>>>'
go 

create unique nonclustered index STAtupind 
on jcmt_tms.dbo.STA(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.STSOU'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.STSOU" >>>>>'
go

setuser 'dbo'
go 

create table STSOU (
	stsou#                          id                                   null,
	object                          vc16                                 null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Grant Select on dbo.STSOU to public Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'STSOUtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "STSOUtupind" >>>>>'
go 

create unique nonclustered index STSOUtupind 
on jcmt_tms.dbo.STSOU(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.SUB'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.SUB" >>>>>'
go

setuser 'dbo'
go 

create table SUB (
	sub#                            id                                   null,
	sca#                            id                                   null,
	ut                              dt8                                  null,
	projid                          vc16                                 null,
	scan                            r8                                   null,
	subscan                         i2                                   null,
	xcell0                          r4                                   null,
	ycell0                          r4                                   null,
	lst                             r8                                   null,
	airmass                         r8                                   null,
	samprat                         i4                                   null,
	nocycles                        i4                                   null,
	ncycle                          i4                                   null,
	cycllen                         i4                                   null,
	noscans                         i4                                   null,
	nscan                           i4                                   null,
	noscnpts                        i4                                   null,
	nocycpts                        i4                                   null,
	ncycpts                         i4                                   null,
	intgr                           i4                                   null,
	ut_dmf                          i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.SUB to dbo Granted by dbo
go
Grant Select on dbo.SUB to jcmtstaff Granted by dbo
go
Grant Select on dbo.SUB to observers Granted by dbo
go
Grant Select on dbo.SUB to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'SUBsub#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SUBsub#ind" >>>>>'
go 

create unique clustered index SUBsub#ind 
on jcmt_tms.dbo.SUB(sub#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SUBsca#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SUBsca#ind" >>>>>'
go 

create nonclustered index SUBsca#ind 
on jcmt_tms.dbo.SUB(sca#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SUBprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SUBprojind" >>>>>'
go 

create nonclustered index SUBprojind 
on jcmt_tms.dbo.SUB(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SUButind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SUButind" >>>>>'
go 

create nonclustered index SUButind 
on jcmt_tms.dbo.SUB(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SUButdmfind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SUButdmfind" >>>>>'
go 

create nonclustered index SUButdmfind 
on jcmt_tms.dbo.SUB(ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'SUBtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "SUBtupind" >>>>>'
go 

create unique nonclustered index SUBtupind 
on jcmt_tms.dbo.SUB(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.TAU'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.TAU" >>>>>'
go

setuser 'dbo'
go 

create table TAU (
	tau#                            id                                   null,
	cso_ut                          dt8                                  null,
	hst                             r4                                   null,
	tau                             r4                                   null,
	tau_rms                         r4                                   null,
	cso_ut_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.TAU to dbo Granted by dbo
go
Grant Select on dbo.TAU to jcmtstaff Granted by dbo
go
Grant Select on dbo.TAU to observers Granted by dbo
go
Grant Select on dbo.TAU to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'TAUtau#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "TAUtau#ind" >>>>>'
go 

create unique clustered index TAUtau#ind 
on jcmt_tms.dbo.TAU(tau#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'TAUcsoutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "TAUcsoutind" >>>>>'
go 

create nonclustered index TAUcsoutind 
on jcmt_tms.dbo.TAU(cso_ut)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'TAUcsodmfind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "TAUcsodmfind" >>>>>'
go 

create nonclustered index TAUcsodmfind 
on jcmt_tms.dbo.TAU(cso_ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'TAUtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "TAUtupind" >>>>>'
go 

create nonclustered index TAUtupind 
on jcmt_tms.dbo.TAU(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.TEL'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.TEL" >>>>>'
go

setuser 'dbo'
go 

create table TEL (
	tel#                            id                                   null,
	fe#                             id                                   null,
	eff#                            id                                   null,
	be#                             id                                   null,
	smu#                            id                                   null,
	poi#                            id                                   null,
	foc#                            id                                   null,
	utstart                         dt8                                  null,
	utstop                          dt8                                  null,
	projid                          vc16                                 null,
	scan                            i4                                   null,
	frontend                        vc16                                 null,
	frontype                        vc16                                 null,
	nofchan                         i4                                   null,
	backend                         vc16                                 null,
	backtype                        vc16                                 null,
	noifpbes                        i4                                   null,
	nobchan                         i4                                   null,
	config                          i4                                   null,
	outputt                         vc16                                 null,
	calsrc                          vc16                                 null,
	shftfrac                        r4                                   null,
	badchv                          r8                                   null,
	norchan                         i4                                   null,
	norsect                         i4                                   null,
	dataunit                        vc16                                 null,
	swmode                          vc16                                 null,
	caltask                         vc16                                 null,
	caltype                         vc16                                 null,
	redmode                         vc16                                 null,
	waveform                        vc16                                 null,
	chopfreq                        r4                                   null,
	chopcoor                        vc16                                 null,
	chopthrw                        r4                                   null,
	chopdirn                        r4                                   null,
	ewtilt                          r4                                   null,
	nstilt                          r4                                   null,
	ew_scale                        r4                                   null,
	ns_scale                        r4                                   null,
	ew_encode                       i4                                   null,
	ns_encode                       i4                                   null,
	xpoint                          r8                                   null,
	ypoint                          r8                                   null,
	uxpnt                           r8                                   null,
	uypnt                           r8                                   null,
	focusv                          r4                                   null,
	focusl                          r4                                   null,
	focusr                          r4                                   null,
	utstart_dmf                     i4                                   null,
	utstop_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.TEL to dbo Granted by dbo
go
Grant Select on dbo.TEL to jcmtstaff Granted by dbo
go
Grant Select on dbo.TEL to observers Granted by dbo
go
Grant Select on dbo.TEL to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'TELtel#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "TELtel#ind" >>>>>'
go 

create unique clustered index TELtel#ind 
on jcmt_tms.dbo.TEL(tel#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'TELprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "TELprojind" >>>>>'
go 

create nonclustered index TELprojind 
on jcmt_tms.dbo.TEL(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'TELutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "TELutind" >>>>>'
go 

create nonclustered index TELutind 
on jcmt_tms.dbo.TEL(utstart)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'TELut1dind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "TELut1dind" >>>>>'
go 

create nonclustered index TELut1dind 
on jcmt_tms.dbo.TEL(utstart_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'TELut2dind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "TELut2dind" >>>>>'
go 

create nonclustered index TELut2dind 
on jcmt_tms.dbo.TEL(utstop_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'TELtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "TELtupind" >>>>>'
go 

create unique nonclustered index TELtupind 
on jcmt_tms.dbo.TEL(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.THI'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.THI" >>>>>'
go

setuser 'dbo'
go 

create table THI (
	thi#                            i2                                   null,
	az                              r4                                   null,
	f1                              r4                                   null,
	f2                              r4                                   null,
	f3                              r4                                   null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'THIthiind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "THIthiind" >>>>>'
go 

create unique clustered index THIthiind 
on jcmt_tms.dbo.THI(thi#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'THIazind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "THIazind" >>>>>'
go 

create nonclustered index THIazind 
on jcmt_tms.dbo.THI(az)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.WEA'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.WEA" >>>>>'
go

setuser 'dbo'
go 

create table WEA (
	wea#                            id                                   null,
	utstart                         dt8                                  null,
	utstop                          dt8                                  null,
	projid                          vc16                                 null,
	scan                            i4                                   null,
	ws#                             id                                   null,
	tau#                            id                                   null,
	pha#                            id                                   null,
	tamb                            r4                                   null,
	pressure                        r4                                   null,
	humidity                        r4                                   null,
	tau                             r4                                   null,
	tau_rms                         r4                                   null,
	tau_date                        dt8                                  null,
	pha                             r4                                   null,
	pha_date                        dt8                                  null,
	utstart_dmf                     i4                                   null,
	utstop_dmf                      i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.WEA to dbo Granted by dbo
go
Grant Select on dbo.WEA to jcmtstaff Granted by dbo
go
Grant Select on dbo.WEA to observers Granted by dbo
go
Grant Select on dbo.WEA to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'WEAwea#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "WEAwea#ind" >>>>>'
go 

create unique clustered index WEAwea#ind 
on jcmt_tms.dbo.WEA(wea#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'WEAutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "WEAutind" >>>>>'
go 

create nonclustered index WEAutind 
on jcmt_tms.dbo.WEA(utstart)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'WEAprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "WEAprojind" >>>>>'
go 

create nonclustered index WEAprojind 
on jcmt_tms.dbo.WEA(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'WEAut1dind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "WEAut1dind" >>>>>'
go 

create nonclustered index WEAut1dind 
on jcmt_tms.dbo.WEA(utstart_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'WEAut2dind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "WEAut2dind" >>>>>'
go 

create nonclustered index WEAut2dind 
on jcmt_tms.dbo.WEA(utstop_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'WEAtupind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "WEAtupind" >>>>>'
go 

create unique nonclustered index WEAtupind 
on jcmt_tms.dbo.WEA(tuple_id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.WS'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.WS" >>>>>'
go

setuser 'dbo'
go 

create table WS (
	ws#                             id                                   null,
	ut                              dt8                                  null,
	period                          vc16                                 null,
	name                            vc16                                 null,
	avgval                          r4                                   null,
	minval                          r4                                   null,
	maxval                          r4                                   null,
	npts                            i4                                   null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 


setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'WSws#ind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "WSws#ind" >>>>>'
go 

create unique clustered index WSws#ind 
on jcmt_tms.dbo.WS(ws#)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'WSutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "WSutind" >>>>>'
go 

create nonclustered index WSutind 
on jcmt_tms.dbo.WS(ut)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.rs_lastcommit'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.rs_lastcommit" >>>>>'
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
on jcmt_tms.dbo.rs_lastcommit(origin)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.rs_threads'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.rs_threads" >>>>>'
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
on jcmt_tms.dbo.rs_threads(id)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.rs_ticket_history'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.rs_ticket_history" >>>>>'
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
on jcmt_tms.dbo.rs_ticket_history(cnt)
go 


-----------------------------------------------------------------------------
-- DDL for Table 'jcmt_tms.dbo.scan'
-----------------------------------------------------------------------------
print '<<<<< CREATING Table - "jcmt_tms.dbo.scan" >>>>>'
go

setuser 'dbo'
go 

create table scan (
	dir_id                          varchar(107)                         null,
	scan_id                         varchar(120)                         null,
	projid                          varchar(16)                          null,
	scan                            int                                  null,
	sca_idx                         id                                   null,
	release_date                    datetime                             null,
	obsmode                         varchar(16)                          null,
	lst                             r8                                   null,
	utdate                          dt8                                  null,
	uthour                          real                                 null,
	ra                              r8                                   null,
	dec                             r8                                   null,
	lii                             r8                                   null,
	bii                             r8                                   null,
	azimuth                         r8                                   null,
	elevation                       r8                                   null,
	epoch                           r8                                   null,
	ra_epoch                        r8                                   null,
	dec_epoch                       r8                                   null,
	ncycle                          i4                                   null,
	cycllen                         i4                                   null,
	coordcd                         vc16                                 null,
	deltax                          r8                                   null,
	deltay                          r8                                   null,
	yposang                         r8                                   null,
	xsource                         r8                                   null,
	ysource                         r8                                   null,
	xmap                            i4                                   null,
	ymap                            i4                                   null,
	object                          varchar(16)                          null,
	nscan                           i4                                   null,
	frontend                        varchar(16)                          null,
	frontype                        varchar(16)                          null,
	backend                         varchar(16)                          null,
	backtype                        varchar(16)                          null,
	velocity                        r8                                   null,
	restfreq                        r8                                   null,
	freqres                         r4                                   null,
	veldef                          varchar(16)                          null,
	velref                          varchar(16)                          null,
	nobchan                         i4                                   null,
	norsect                         i4                                   null,
	swmode                          varchar(27)                          null,
	chopfreq                        r4                                   null,
	filter                          varchar(16)                          null,
	aperture                        varchar(16)                          null,
	photometry                      r8                                   null,
	phot_error                      r8                                   null,
	tsys                            r4                                   null,
	tau                             r4                                   null,
	seeing                          r4                                   null,
	tamb                            r4                                   null,
	humidity                        r4                                   null,
	epocra_int                      i4                                   null,
	epocdec_int                     i4                                   null,
	ra_int                          i4                                   null,
	dec_int                         i4                                   null,
	lii_int                         i4                                   null,
	bii_int                         i4                                   null,
	ut_dmf                          i4                                   null,
	release_date_dmf                int                                  null,
	tuple_id                        i4                               not null 
)
lock allpages
with dml_logging = full
 on 'default'
go 

Revoke Delete on dbo.scan to dbo Granted by dbo
go
Grant Select on dbo.scan to jcmtstaff Granted by dbo
go
Grant Select on dbo.scan to observers Granted by dbo
go
Grant Select on dbo.scan to visitors Granted by dbo
go

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Index 'scanobj'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "scanobj" >>>>>'
go 

create clustered index scanobj 
on jcmt_tms.dbo.scan(object)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'scanscaid'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "scanscaid" >>>>>'
go 

create unique nonclustered index scanscaid 
on jcmt_tms.dbo.scan(sca_idx)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'scanutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "scanutind" >>>>>'
go 

create nonclustered index scanutind 
on jcmt_tms.dbo.scan(utdate)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'scandutind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "scandutind" >>>>>'
go 

create nonclustered index scandutind 
on jcmt_tms.dbo.scan(ut_dmf)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'scanprojind'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "scanprojind" >>>>>'
go 

create nonclustered index scanprojind 
on jcmt_tms.dbo.scan(projid)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'scanradec'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "scanradec" >>>>>'
go 

create nonclustered index scanradec 
on jcmt_tms.dbo.scan(ra_int, dec_int)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'scaneradec'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "scaneradec" >>>>>'
go 

create nonclustered index scaneradec 
on jcmt_tms.dbo.scan(epocra_int, epocdec_int)
go 


-----------------------------------------------------------------------------
-- DDL for Index 'scanrf'
-----------------------------------------------------------------------------

print '<<<<< CREATING Index - "scanrf" >>>>>'
go 

create nonclustered index scanrf 
on jcmt_tms.dbo.scan(restfreq)
go 


-----------------------------------------------------------------------------
-- DDL for View 'jcmt_tms.dbo.standards'
-----------------------------------------------------------------------------

print '<<<<< CREATING View - "jcmt_tms.dbo.standards" >>>>>'
go 

setuser 'dbo'
go 


create view standards (sca_idx, projid, scan, object, ut, line,
         restfrq, dir_id, scan_id, ut_dmf)
  as
  select distinct SCA.sca#, SCA.projid, SCA.scan, 
         SCA.object, SCA.ut, LINE.line, LINE.restfrq,
         stuff(reverse(stuff(reverse(gsdfile),1,
              (charindex("/",reverse(gsdfile))),NULL)),1,13,NULL),
         reverse(
         substring(reverse(gsdfile),5,(charindex("/",reverse(gsdfile))-5))),
         SCA.ut_dmf
  from SCA, SPH, STSOU, LINE
  where SCA.ut > "10/1/1993" 
    and SPH.sca#=SCA.sca# and SCA.object=lower(STSOU.object)
    and (((SPH.obsfreq+SPH.bw/2000.0)>LINE.restfrq
           and (SPH.obsfreq-SPH.bw/2000.0)<LINE.restfrq)
    or
         (SPH.g_s < 0.9 and (SPH.obsfreq+SPH.bw/2000.0-
              sign(SPH.betotif)*(5.5+2.5*sign(SPH.obsfreq-
              (400-200*charindex("rxa3i",SCA.frontend)-
               100*charindex("rxb",SCA.frontend)-
	       100*charindex("rxb3cu",SCA.frontend)+
	       100*charindex("rxb3",SCA.frontend)))))>LINE.restfrq
          and (SPH.obsfreq-SPH.bw/2000.0-
               sign(SPH.betotif)*(5.5+2.5*sign(SPH.obsfreq-
              (400-200*charindex("rxa3i",SCA.frontend)-
               100*charindex("rxb",SCA.frontend)-
	       100*charindex("rxb3cu",SCA.frontend)+
	       100*charindex("rxb3",SCA.frontend)))))<LINE.restfrq))

go 

Grant Select on dbo.standards to public Granted by dbo
go
Revoke Insert on dbo.standards to dbo Granted by dbo
go
Revoke Delete on dbo.standards to dbo Granted by dbo
go
Revoke Update on dbo.standards to dbo Granted by dbo
go
setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.checkut'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.checkut" >>>>>'
go 

setuser 'dbo'
go 

create procedure checkut
(    @ut        dt8    )
as
/* 
** sql to check whether ut is later than last ut in DB.
** If not (ut is before  last) -1 is returned else 0.
**
** usage :    exec checkut @ut="mm/dd/yyyy hh:mm:ss"
**
*/
  declare @dbut dt8, @utdiff r8, @sca# id

  select @sca#=max(sca#) from SCA

  if @sca# = 0
  begin
     return 0
  end

  select @dbut=ut from SCA where sca# = @sca#

  select @utdiff=datediff(ss,@dbut,@ut)

  if @utdiff < 0
  begin
     return -1
  end

  return 0

go 

Grant Execute on dbo.checkut to jcmtstaff Granted by dbo
go
Grant Execute on dbo.checkut to observers Granted by dbo
go

sp_procxmode 'checkut', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.dec2rad'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.dec2rad" >>>>>'
go 

setuser 'dbo'
go 

create procedure dec2rad
(
     @sdec      vc16,
     @result     r8 output
)
as
/* 
** Convert DEC (+/-dd:mm:ss.s) to radians
*/
   declare @dec r8

     exec hex2decim @sdec, @result = @dec output
     select @result = radians(@dec)


go 

Grant Execute on dbo.dec2rad to jcmtstaff Granted by dbo
go
Grant Execute on dbo.dec2rad to observers Granted by dbo
go
Grant Execute on dbo.dec2rad to visitors Granted by dbo
go

sp_procxmode 'dec2rad', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.delay_release'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.delay_release" >>>>>'
go 

setuser 'dbo'
go 

create procedure delay_release
(    @new_ut      dt8,
     @projid     vc16,
     @ut1         dt8,
     @ut2         dt8,   
     @run1         i4,    
     @run2         i4  )
as
/* 
** sql to change the release date of observations to @new_ut
**
** usage: exec delay_release @month=6,@projid="...",@ut1="mm/dd/yyyy hh:mm:ss"
**
** All observations for the projid and @ut1 < ut < @ut2 and @run1 < run < @run2
** will get their release_date and release_date_dmf field changed. The routine
** reports the "BEFORE" and "AFTER" settings.
*/
   grant update on SCU to dbo

   if @ut1 = @ut2
   begin
     select @ut2 = dateadd(dd,1,@ut1)
   end 

   if exists (select * from SCU
                  where proj_id=lower(@projid)
                  and ut between @ut1 and @ut2
                  and run between @run1 and @run2) 
   begin

      print "ORGINAL: "
      print "========="

      select proj_id, run, ut, release_date, release_date_dmf 
      from SCU
          where proj_id=lower(@projid)
                and ut between @ut1 and @ut2
                and run between @run1 and @run2
/*
**          release_date=dateadd(mm,@months,release_date),
**          release_date_dmf = datediff(ss, "01/01/1980 00:00:00", 
**                             dateadd(mm,@months,release_date))
*/
      update SCU set 
          release_date=@new_ut,
          release_date_dmf = datediff(ss, "01/01/1980 00:00:00", 
                             @new_ut)
          where proj_id=lower(@projid)
                and ut between @ut1 and @ut2
                and run between @run1 and @run2

      print "UPDATED: "
      print "========="

      select proj_id, run, ut, release_date, release_date_dmf 
      from SCU
          where proj_id=lower(@projid)
                and ut between @ut1 and @ut2
                and run between @run1 and @run2

   end   

   revoke update on SCU from dbo

   return 0


go 


sp_procxmode 'delay_release', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.findobj'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.findobj" >>>>>'
go 

setuser 'dbo'
go 

create procedure findobj
(    @ra        vc16, 
    @dec        vc16,
    @box          i2 = 600,
    @ut_min       dt8 = "19980101",
    @ut_max       dt8 = "20500101",
    @f1           r8 = 200.0,
    @f2           r8 = 999.0,
    @const      vc120 = ""  )
as
/* 
** sql to find a observations in a box around a Ra-Dec position, optional
** within a given frequency range. The position must be in J2000. 
** Positions can be "hh mm ss.s" or "hh:mm:ss.s"
** 
** usage :    exec findobj @ra="hh mm ss", @dec="dd mm ss", @box=600,
**                 @ut_min="yyyymmdd", @ut_max="yyyymmdd",
**                 @f1=lo_freq, @f2=hi_freq
**
*/
  declare @ra_deg r8, @dec_deg r8, @hh i2, @mm i2, @ss r4,
          @sign i2, @dd i2, @am i2, @as r4, @i i2, 
          @rdum vc16, @ddum vc16, 
          @rmin i4, @rmax i4, @dmin i4, @dmax i4

  select @ra = str_replace(@ra,":"," "), @dec = str_replace(@dec,":"," ")   
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

  select @ra_deg  = 15.0 *(@hh+@mm/60.0+@ss/3600.0),
         @dec_deg = @sign*(@dd+@am/60.0+@as/3600.0)

  if ( ((@sign*@dec_deg) + 0.5*@box/3600.0) <  90.0 )
  begin
     select @rmin = @ra_deg*3600*1000 - 
                       0.5*@box*1000/cos(@dec_deg*3.1415926536/180.0),
            @rmax = @ra_deg*3600*1000 +
                       0.5*@box*1000/cos(@dec_deg*3.1415926536/180.0),
            @dmin = @dec_deg*3600*1000 - 0.5*@box*1000,
            @dmax = @dec_deg*3600*1000 + 0.5*@box*1000

     if (@rmin < 0) 
       select @rmin = @rmin+(360*3600*1000)

     if (@rmax > (360*3600*1000))
       select @rmax = @rmax-(360*3600*1000)

     if (@rmin <= @rmax)
       SELECT projid, SCA.object, SCA.ut, scan, obsmode, restfrq1, velocity, 
              vdef, vref, frontend, backend, el from SCA,SOU
       WHERE raj2000_int BETWEEN @rmin and @rmax AND
             decj2000_int BETWEEN @dmin and @dmax AND
             SOU.sou#=SCA.sou# AND
             SCA.ut between @ut_min and @ut_max 
             AND restfrq1 between @f1 and @f2
             order by SCA.ut
     else
       SELECT projid, SCA.object, SCA.ut, scan, obsmode, restfrq1, velocity, 
              vdef, vref, frontend, backend, el from SCA,SOU
       WHERE (raj2000_int >= @rmin OR raj2000_int <= @rmax) AND
             decj2000_int BETWEEN @dmin and @dmax AND
             SOU.sou#=SCA.sou# AND
             SCA.ut between @ut_min and @ut_max 
             AND restfrq1 between @f1 and @f2 
             order by SCA.ut
  end
  else
  begin
    if (@sign = 1)
      select @dmax = 90*3600*1000,
             @dmin = @dec_deg*3600*1000 - 0.5*@box*1000
    else
      select @dmax = @dec_deg*3600*1000 + 0.5*@box*1000,
             @dmin = 90*3600*1000
             
    SELECT projid, SCA.object, SCA.ut, scan, obsmode, restfrq1, velocity, 
           vdef, vref, frontend, backend, el from SCA,SOU
    WHERE decj2000_int BETWEEN @dmin and @dmax AND
          SOU.sou#=SCA.sou# AND
             SCA.ut between @ut_min and @ut_max 
             AND restfrq1 between @f1 and @f2
             order by SCA.ut
  end

  return(0)

go 

Grant Execute on dbo.findobj to staff Granted by dbo
go

sp_procxmode 'findobj', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.findobj_het'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.findobj_het" >>>>>'
go 

setuser 'dbo'
go 

create procedure findobj_het
(    @ra        vc16, 
    @dec        vc16,
    @box          i2 = 600,
   @const      vc120 = ""  )
as
/* 
** sql to find a observations in a box around a Ra-Dec position.
** The position must be in J2000. 
**
** usage :    exec findobj_het @ra="hh mm ss" @dec="dd mm ss" @box=600
**
*/
  declare @ra_deg r8, @dec_deg r8, @hh i2, @mm i2, @ss r4,
          @sign i2, @dd i2, @am i2, @as r4, @i i2, 
          @rdum vc16, @ddum vc16, 
          @rmin i4, @rmax i4, @dmin i4, @dmax i4

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

  select @ra_deg  = 15.0 *(@hh+@mm/60.0+@ss/3600.0),
         @dec_deg = @sign*(@dd+@am/60.0+@as/3600.0)

  if ( ((@sign*@dec_deg) + 0.5*@box/3600.0) <  90.0 )
  begin
     select @rmin = @ra_deg*3600*1000 - 
                       0.5*@box*1000/cos(@dec_deg*3.1415926536/180.0),
            @rmax = @ra_deg*3600*1000 +
                       0.5*@box*1000/cos(@dec_deg*3.1415926536/180.0),
            @dmin = @dec_deg*3600*1000 - 0.5*@box*1000,
            @dmax = @dec_deg*3600*1000 + 0.5*@box*1000

     if (@rmin < 0) 
       select @rmin = @rmin+(360*3600*1000)

     if (@rmax > (360*3600*1000))
       select @rmax = @rmax-(360*3600*1000)

     if (@rmin <= @rmax)
       SELECT projid, object, utdate, scan, obsmode, restfreq, 
              velocity, tint=cycllen*ncycle, tsys, elevation, tau, seeing 
       FROM jcmt_tms..scan
       WHERE ra_int BETWEEN @rmin and @rmax AND
             dec_int BETWEEN @dmin and @dmax
     else
       SELECT projid, object, utdate, scan, obsmode, restfreq, 
              velocity, tint=cycllen*ncycle, tsys, elevation, tau, seeing 
       FROM jcmt_tms..scan
       WHERE (ra_int >= @rmin OR ra_int <= @rmax) AND
             dec_int BETWEEN @dmin and @dmax
  end
  else
  begin
    if (@sign = 1)
      select @dmax = 90*3600*1000,
             @dmin = @dec_deg*3600*1000 - 0.5*@box*1000
    else
      select @dmax = @dec_deg*3600*1000 + 0.5*@box*1000,
             @dmin = 90*3600*1000
             
    SELECT projid, object, utdate, scan, obsmode, restfreq, 
           velocity, tint=cycllen*ncycle, tsys, elevation, tau, seeing 
    FROM jcmt_tms..scan
    WHERE dec_int BETWEEN @dmin and @dmax

  end

  return(0)

go 

Grant Execute on dbo.findobj_het to jcmtstaff Granted by dbo
go

sp_procxmode 'findobj_het', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.getsta'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.getsta" >>>>>'
go 

setuser 'dbo'
go 

create procedure getsta
(    @ut1    dt8 = "1/1/1985",
     @ut2    dt8 = "1/1/2050"  )
as
/* 
** sql to list spectral standards observer within the specified
** date range. 
** Default time range is previous month from current date.
** NOTE: routine only handles DAS data (after 10/1/1993)
**
** usage :    exec getsta @ut1="mm/dd/yyyy" .....
**
*/
  declare @utdiff r4, @utdum dt8, @utnow dt8,
          @utd1 char(8), @utd2 char(8), @ifsw r4

  select @utnow=dateadd(hh,10,getdate())
  
  select @utdiff=datediff(mm,"1/1/1985",@ut1)
  if @utdiff < 1
  begin
    select @utdiff=datediff(mm,@ut2,"1/1/2050")
    if @utdiff < 1
    begin
      select @ut1 = dateadd(mm,-1,@utnow),  @ut2 = @utnow
    end
    else
    begin
      select @ut1 = dateadd(mm,-1,@ut2)
    end
  end

  select @utdiff=datediff(mm,@ut2,"1/1/2050")
  if @utdiff < 1
  begin
    select @utdiff=datediff(mm,"1/1/1985",@ut1)
    if @utdiff < 1
    begin
      select @ut1 = dateadd(mm,-1,@utnow),  @ut2 = @utnow
    end
    else
    begin
      select @ut2 = dateadd(mm,1,@ut1)
    end
  end

  select @utdiff=datediff(ss,@ut1,@ut2)/(3600.0*24.0)

  if @utdiff < 0
  begin
    select @utdum=@ut1
    select @ut1=@ut2
    select @ut2=@utdum
    select @utdiff=-1*@utdiff
  end

  if @utdiff < 0
  begin 
     print " "
     print " Error ordering UT range: %1! and %2!.", @utd1, @utd2
     print " "
     return -1
  end

  select @utdiff=datediff(ss,"10/1/1993",@ut1)
  if @utdiff < 0
  begin
     print " "
     print " This routine only handles data after 10/1/1993."
     print " "
     return -2
  end

  select @utd1=convert(char(8),@ut1,1),@utd2=convert(char(8),@ut2,1)

/*
** RxA2:   IF = 3.0 GHz
** RxB3i:  IF = 3.0 GHz (until: 12/6/1996)
** RxB3cu: IF = 8.0 GHz (installation: 12/6/1996)
** RxC2:   IF = 8.0 GHz

  select @utdiff=datediff(ss,"12/6/1996",@ut1), @ifsw=300
  if @utdiff < 0
  begin
     select @ifsw=400
  end
*/

  print " "
  print " JCMT spectral standards from UT %1! through %2!.", @utd1, @utd2
  print " Covers both Signal and Image sideband (dual sideband only)."
  print " Starting search, have patience..."
  print " "

  select 
    sca#=convert(char(7),sca_idx),
    projid="  "+convert(char(12),projid),
    utdate="  "+convert(char(8),ut,112),
    scan=str(scan,5,0),
    object="  "+convert(char(12),object),
    line="  "+convert(char(8),line), 
    linefreq=str(restfrq,10,5)
  from standards where ut>@ut1 and ut<@ut2
  order by restfrq,ut

  return 0

go 

Grant Execute on dbo.getsta to public Granted by dbo
go

sp_procxmode 'getsta', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.gettrx'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.gettrx" >>>>>'
go 

setuser 'dbo'
go 

create procedure gettrx
(    @mode        i4 = 1,
     @ut1        dt8 = "1/1/1985",
     @ut2        dt8 = "1/1/2050",
     @fr1         r4 =        200,
     @fr2         r4 =       1000,
     @el1         r4 =       -1.0,
     @el2         r4 =       91.0,
     @tr1         r4 =      -10.0,
     @tr2         r4 =    10000.0   )
as
/* 
** sql to get receiver (modes 1..3) or system temps (modes 11..13) 
** for the central subband of all scans between ut dates 1 and 2, lo
**  frequency range fr1 - fr2, elevation range el1 - el2, and trx range 
** trx1 - trx2 ordered by ut time (mode=1 & 11), lofreq (mode 2 & 12), 
** or EL (mode 3 && 13).
** If the mode is < 0 no ordering is done to support large and quick
** queries.
** Default time range is previous three months from current date.
**
** usage :    exec gettrx @ut1="mm/dd/yyyy hh:mm:ss" .....
**
*/
  declare @utdiff r4, @frdiff r4, @utdum dt8, @frdum r4, 
          @eldiff r4, @trdiff r4, @eldum  r4, @trdum r4, 
          @utnow dt8

  select @utnow=dateadd(hh,10,getdate())
  
  select @utdiff=datediff(ss,"1/1/1985",@ut1)
  if @utdiff < 1
  begin
    select @utdiff=datediff(ss,@ut2,"1/1/2050")
    if @utdiff < 1
    begin
      select @ut1 = dateadd(mm,-3,@utnow),  @ut2 = @utnow
    end
    else
    begin
      select @ut1 = dateadd(mm,-3,@ut2)
    end
  end

  select @utdiff=datediff(ss,@ut2,"1/1/2050")
  if @utdiff < 1
  begin
    select @utdiff=datediff(ss,"1/1/1985",@ut1)
    if @utdiff < 1
    begin
      select @ut1 = dateadd(mm,-3,@utnow),  @ut2 = @utnow
    end
    else
    begin
      select @ut2 = dateadd(mm,3,@ut1)
    end
  end

  select @utdiff=datediff(ss,@ut1,@ut2)/(3600.0*24.0)

  if @utdiff < 0
  begin
    select @utdum=@ut1
    select @ut1=@ut2
    select @ut2=@utdum
    select @utdiff=-1*@utdiff
  end

  if @utdiff < 0
  begin 
     return -1
  end

  if @fr2 < @fr1
  begin
    select @frdum=@fr1
    select @fr1=@fr2
    select @fr2=@frdum
  end

  if @el2 < @el1
  begin
    select @eldum=@el1
    select @el1=@el2
    select @el2=@eldum
  end

  if @tr2 < @tr1
  begin
    select @trdum=@tr1
    select @tr1=@tr2
    select @tr2=@trdum
  end

  if @mode = 1
    begin
      select ut=2444239.5+SCA.ut_dmf/8.64e4, trx=SPH.trx*(-1.0*SPH.g_s+1.5), 
             lofreq=SPH.befenulo
      from SCA, SPH
      where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
         order by SPH.befenulo
    end
  else if @mode = -1
    begin
      select ut=2444239.5+SCA.ut_dmf/8.64e4, trx=SPH.trx*(-1.0*SPH.g_s+1.5), 
             lofreq=SPH.befenulo
      from SCA, SPH
      where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
    end
  else if @mode = 2
    begin
      select lofreq=SPH.befenulo, trx=SPH.trx*(-1.0*SPH.g_s+1.5), 
             day=datediff(hh,@utnow,SCA.ut)/24.0
      from SCA, SPH
      where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
         order by SCA.ut
    end
  else if @mode = -2
    begin
      select lofreq=SPH.befenulo, trx=SPH.trx*(-1.0*SPH.g_s+1.5), 
             day=datediff(hh,@utnow,SCA.ut)/24.0
      from SCA, SPH
      where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
    end
  else if @mode = 3
    begin
      select el=SCA.el, trx=SPH.trx*(-1.0*SPH.g_s+1.5), 
             lofreq=SPH.befenulo
        from SCA, SPH
        where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
         order by SPH.befenulo
    end
  else if @mode = -3
    begin
      select el=SCA.el, trx=SPH.trx*(-1.0*SPH.g_s+1.5), 
             lofreq=SPH.befenulo
        from SCA, SPH
        where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
    end
  if @mode = 11
    begin
      select ut=2444239.5+SCA.ut_dmf/8.64e4, stsys=SPH.stsys, 
             lofreq=SPH.befenulo
      from SCA, SPH
      where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
         order by SPH.befenulo
    end
  else if @mode = -11
    begin
      select ut=2444239.5+SCA.ut_dmf/8.64e4, stsys=SPH.stsys, 
             lofreq=SPH.befenulo
      from SCA, SPH
      where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
    end
  else if @mode = 12
    begin
      select lofreq=SPH.befenulo, stsys=SPH.stsys, 
             day=datediff(hh,@utnow,SCA.ut)/24.0
      from SCA, SPH
      where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
         order by SCA.ut
    end
  else if @mode = -12
    begin
      select lofreq=SPH.befenulo, stsys=SPH.stsys, 
             day=datediff(hh,@utnow,SCA.ut)/24.0
      from SCA, SPH
      where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
    end
  else if @mode = 13
    begin
      select el=SCA.el, stsys=SPH.stsys, 
             lofreq=SPH.befenulo
        from SCA, SPH
        where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
         order by SPH.befenulo
    end
  else if @mode = -13
    begin
      select el=SCA.el, stsys=SPH.stsys, 
             lofreq=SPH.befenulo
        from SCA, SPH
        where
         SCA.ut >= @ut1 and SCA.ut < @ut2
         and SCA.el > @el1 and SCA.el < @el2
         and SPH.sca# = SCA.sca#
         and SPH.band = convert(int,(SCA.norsect+1)/2)
         and SPH.befenulo >= @fr1 and SPH.befenulo <= @fr2
         and SPH.trx > @tr1 and SPH.trx < @tr2 and SPH.g_s > 0
    end
  else
    return -2

  return 0

go 

Grant Execute on dbo.gettrx to jcmtstaff Granted by dbo
go
Grant Execute on dbo.gettrx to observers Granted by dbo
go
Grant Execute on dbo.gettrx to visitors Granted by dbo
go

sp_procxmode 'gettrx', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.hex2decim'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.hex2decim" >>>>>'
go 

setuser 'dbo'
go 

create procedure hex2decim
(
     @hex     vc16,
     @result    r8 output
)
as
/* 
** Convert xx:yy:zz.z string to decimal representation: xx.xxxxx
*/
   declare @i i4
   declare @dd i4, @am i4, @as r8, @sign i4

   select @hex = rtrim(ltrim(@hex)), @sign = 1

   select @i = charindex(":",@hex)
   select @dd = convert(int,substring(@hex,1,(@i-1)))
   if (@dd < 0)
   begin
     select @sign = -1, @dd=abs(@dd)
   end
   select @hex = stuff(@hex,1,@i,NULL)
   select @i = charindex(":",@hex)
   select @am = convert(int,substring(@hex,1,(@i-1)))
   select @as = convert(real,stuff(@hex,1,@i,NULL)), @i=0

   select @result = @sign*(@dd+@am/60.0+@as/3600.0)
  
   return(0)

go 

Grant Execute on dbo.hex2decim to jcmtstaff Granted by dbo
go
Grant Execute on dbo.hex2decim to observers Granted by dbo
go
Grant Execute on dbo.hex2decim to visitors Granted by dbo
go

sp_procxmode 'hex2decim', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.lst_elev'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.lst_elev" >>>>>'
go 

setuser 'dbo'
go 

create procedure lst_elev
(
     @sra      vc16,
     @sdec     vc16,
     @el_deg     r4,
     @lst1       r4 output,
     @lst2       r4 output
)
as
/*
** Calculate LST range for which a source is above the specified elevation
** (in degrees) for the provided RA and DEC (colon separated numbers).
** LSTs in fractional hours are returned. 
*/
   declare @ra r8, @dec r8, @lat_deg r8, @lat r8, @el r8
   declare @mid r8, @lst1_rad r8, @lst2_rad r8

   select @el      = radians(@el_deg),
          @lat_deg = 19.8258323669,
          @lat     = radians(19.8258323669),
          @lst1    = -1.0,
          @lst2    = -1.0

   exec ra2rad @sra,  @result = @ra  output
   exec dec2rad @sdec, @result = @dec output

/*
** Midpoint of the LST two values, followed by rising and setting LST
*/
   select @mid=acos((sin(@el)-sin(@lat)*sin(@dec))/(cos(@lat)*cos(@dec)))
   select @lst1_rad = 2*pi()-@mid+@ra, @lst2_rad = @mid+@ra

   if (@lst1_rad > 2*pi()) 
   begin 
     select @lst1_rad = @lst1_rad - 2*pi()
   end
   else
   begin 
     if (@lst1_rad < 0) 
     begin 
       select @lst1_rad = @lst1_rad + 2*pi()
     end
   end
  
   if (@lst2_rad > 2*pi()) 
   begin
      select @lst2_rad = @lst2_rad - 2*pi()
   end
   else
   begin 
     if (@lst2_rad < 0) 
     begin 
       select @lst2_rad = @lst2_rad + 2*pi()
     end
   end

   select @lst1 = round(12.0*@lst1_rad/pi(),4),
          @lst2 = round(12.0*@lst2_rad/pi(),4)

   return (0)

go 

Grant Execute on dbo.lst_elev to jcmtstaff Granted by dbo
go
Grant Execute on dbo.lst_elev to observers Granted by dbo
go
Grant Execute on dbo.lst_elev to visitors Granted by dbo
go

sp_procxmode 'lst_elev', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.lst_rise'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.lst_rise" >>>>>'
go 

setuser 'dbo'
go 

create procedure lst_rise
(
     @sra      vc16,
     @sdec     vc16,
     @el_deg     r4,
     @lst_rise   r4 output
)
as
/*
** Calculate LST when a source rises above the specified elevation
** (in degrees) for the provided RA and DEC (colon separated numbers).
*/
   declare @lst_set r4

   exec lst_elev @sra, @sdec, @el_deg,
        @lst1 = @lst_rise output,
        @lst2 = @lst_set  output

   return(0)

go 

Grant Execute on dbo.lst_rise to jcmtstaff Granted by dbo
go
Grant Execute on dbo.lst_rise to observers Granted by dbo
go
Grant Execute on dbo.lst_rise to visitors Granted by dbo
go

sp_procxmode 'lst_rise', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.lst_set'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.lst_set" >>>>>'
go 

setuser 'dbo'
go 

create procedure lst_set
(
     @sra      vc16,
     @sdec     vc16,
     @el_deg     r4,
     @lst_set    r4 output
)
as
/*
** Calculate LST when a source sets below the specified elevation
** (in degrees) for the provided RA and DEC (colon separated numbers).
*/
   declare @lst_rise r4

   exec lst_elev @sra, @sdec, @el_deg,
        @lst1 = @lst_rise output,
        @lst2 = @lst_set  output

   return(0)

go 

Grant Execute on dbo.lst_set to jcmtstaff Granted by dbo
go
Grant Execute on dbo.lst_set to observers Granted by dbo
go
Grant Execute on dbo.lst_set to visitors Granted by dbo
go

sp_procxmode 'lst_set', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putapb'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putapb" >>>>>'
go 

setuser 'dbo'
go 

create procedure putapb
(  @utcso        dt8 = "1/1/1980",
   @tau          r4  = -1,
   @tau_rms      r4  = -1,
   @utsao        dt8 = "1/1/1980",    
   @pha          r4  = -1,
   @pha_rms      r4  = -1,
   @seeing       r4  = -1,
   @maxtau#      i4 output,
   @maxpha#      i4 output
)
as
/* 
** sql make an entry in the TAU and PHA tables.
**
** usage :    exec putapb @ut="mm/dd/yyyy hh:mm:ss",@xxx=yyy,....
**
** NOTE: if @tau = -999.0 or @pha = -999.0 the routine just returns 
**       the max(tau#) and max(pha#) in the output variables without 
**       doing any updates.
*/
  declare @next int, @tau# int, @ttup int, @pha# int, @ptup int, 
          @cso_ut_dmf int, @sao_ut_dmf int, @hst real


  if  @tau = -999.0 or @pha = -999.0
  begin
    select @maxtau#=max(tau#) from TAU
    select @maxpha#=max(pha#) from PHA
    return 0
  end
      
  if @tau <> -1
  begin
    select @next=0,
           @cso_ut_dmf=datediff(ss, "01/01/1980 00:00:00", @utcso),
           @hst=(convert(real,datepart(hh,@utcso))+
                 convert(real,datepart(mi,@utcso))/60.0+
                 convert(real,datepart(ss,@utcso))/3600.0)-10.0

    if @hst < 0.0 
    begin
       select @hst = @hst + 24.0
    end

    select @tau#=max(tau#), @ttup=max(tuple_id) from TAU
    select @maxtau#=@tau#

    if @cso_ut_dmf <> 0 and not exists (select * from TAU
                   where tau#=@tau# and cso_ut=@utcso)
    begin
      if @tau# < 3600000
      begin
         select @next=3600000, @ttup=@ttup+1
      end
      else
      begin
         select @next=@tau#+1, @ttup=@ttup+1
      end
    end

    if @next <> 0
    begin
       insert into TAU ( tau#, cso_ut, hst,  tau,  tau_rms,
                         cso_ut_dmf,  tuple_id )
                 values(@next, @utcso, @hst, @tau, @tau_rms,
                        @cso_ut_dmf,  @ttup )
       select @maxtau#=@next
    end
  end

  if @pha <> -1
  begin

    select @next=0,
           @sao_ut_dmf=datediff(ss, "01/01/1980 00:00:00", @utsao),
           @hst=(convert(real,datepart(hh,@utsao))+
                 convert(real,datepart(mi,@utsao))/60.0+
                 convert(real,datepart(ss,@utsao))/3600.0)-10.0

    if @hst < 0.0 
    begin
       select @hst = @hst + 24.0
    end

    select @pha#=max(pha#), @ptup=max(tuple_id) from PHA
    select @maxpha#=@pha#

    if @sao_ut_dmf <> 0 and not exists (select * from PHA
                   where pha#=@pha# and sao_ut=@utsao)
    begin
      if @pha# < 3600000
      begin
         select @next=3600000, @ptup=@ptup+1
      end
      else
      begin
         select @next=@pha#+1, @ptup=@ptup+1
      end
    end

    if @next <> 0
    begin
       insert into PHA ( pha#,  sao_ut, hst, pha,  seeing,
                         sao_ut_dmf,  tuple_id )
                 values(@next, @utsao, @hst, @pha, @seeing,
                        @sao_ut_dmf, @ptup )
       select @maxpha#=@next
     end
  end

  return 0

go 


sp_procxmode 'putapb', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putarch'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putarch" >>>>>'
go 

setuser 'dbo'
go 

create procedure putarch
as
/* 
** Sql to move date from Loading Tables into real Archive tables
** This needs quite a bit of sorting. 
**
** usage :    exec putses @ut="mm/dd/yyyy hh:mm:ss",@projid=......
**
*/

/*
** Copy from Loading Tables to Archive in one transaction
*/
   declare @start i4

   select @start = 3600000

   begin transaction archive

      if exists (select ses# from SES 
           where ses# >= @start and ses# < (@start+100000))
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert SES
          select L_SES.ses#, L_SES.utstart, L_SES.utstop, L_SES.projid, L_SES.obsid, L_SES.observer, L_SES.operator, L_SES.telescop, L_SES.longitud, L_SES.latitude, L_SES.height, L_SES.mounting, L_SES.utstart_dmf, L_SES.utstop_dmf, L_SES.tuple_id from L_SES where ses# > 
          (select max(ses#) from SES 
           where ses# >= @start and ses# < (@start+100000))
          order by ses#
        end
      else
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert SES select L_SES.ses#, L_SES.utstart, L_SES.utstop, L_SES.projid, L_SES.obsid, L_SES.observer, L_SES.operator, L_SES.telescop, L_SES.longitud, L_SES.latitude, L_SES.height, L_SES.mounting, L_SES.utstart_dmf, L_SES.utstop_dmf, L_SES.tuple_id from L_SES
          where ses# >= @start and ses# < (@start+100000)
          order by ses#
        end

      if (@@transtate <> 0) 
        begin
          rollback transaction archive
          if (@@transtate <> 3)
            return -101
          else
            return -1
        end

      /* Adaptive Server has expanded all '*' elements in the following statement */ insert SOU
          select L_SOU.sou#, L_SOU.ut, L_SOU.object, L_SOU.cenmove, L_SOU.epoch, L_SOU.epochtyp, L_SOU.epocra, L_SOU.epocdec, L_SOU.raj2000, L_SOU.decj2000, L_SOU.gallong, L_SOU.gallat, L_SOU.epocra_int, L_SOU.epocdec_int, L_SOU.raj2000_int, L_SOU.decj2000_int, L_SOU.gallong_int, L_SOU.gallat_int, L_SOU.ut_dmf, L_SOU.tuple_id from L_SOU where sou# > (select max(sou#) from SOU)
          order by sou#

      if (@@transtate <> 0) 
        begin
          rollback transaction archive
          if (@@transtate <> 3)
            return -102
          else
            return -2
        end

      if exists (select tel# from TEL 
           where tel# >= @start and tel# < (@start+100000))
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert TEL
          select L_TEL.tel#, L_TEL.fe#, L_TEL.eff#, L_TEL.be#, L_TEL.smu#, L_TEL.poi#, L_TEL.foc#, L_TEL.utstart, L_TEL.utstop, L_TEL.projid, L_TEL.scan, L_TEL.frontend, L_TEL.frontype, L_TEL.nofchan, L_TEL.backend, L_TEL.backtype, L_TEL.noifpbes, L_TEL.nobchan, L_TEL.config, L_TEL.outputt, L_TEL.calsrc, L_TEL.shftfrac, L_TEL.badchv, L_TEL.norchan, L_TEL.norsect, L_TEL.dataunit, L_TEL.swmode, L_TEL.caltask, L_TEL.caltype, L_TEL.redmode, L_TEL.waveform, L_TEL.chopfreq, L_TEL.chopcoor, L_TEL.chopthrw, L_TEL.chopdirn, L_TEL.ewtilt, L_TEL.nstilt, L_TEL.ew_scale, L_TEL.ns_scale, L_TEL.ew_encode, L_TEL.ns_encode, L_TEL.xpoint, L_TEL.ypoint, L_TEL.uxpnt, L_TEL.uypnt, L_TEL.focusv, L_TEL.focusl, L_TEL.focusr, L_TEL.utstart_dmf, L_TEL.utstop_dmf, L_TEL.tuple_id from L_TEL where tel# >
          (select max(tel#) from TEL 
           where tel# >= @start and tel# < (@start+100000))
          order by tel#
        end
      else
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert TEL select L_TEL.tel#, L_TEL.fe#, L_TEL.eff#, L_TEL.be#, L_TEL.smu#, L_TEL.poi#, L_TEL.foc#, L_TEL.utstart, L_TEL.utstop, L_TEL.projid, L_TEL.scan, L_TEL.frontend, L_TEL.frontype, L_TEL.nofchan, L_TEL.backend, L_TEL.backtype, L_TEL.noifpbes, L_TEL.nobchan, L_TEL.config, L_TEL.outputt, L_TEL.calsrc, L_TEL.shftfrac, L_TEL.badchv, L_TEL.norchan, L_TEL.norsect, L_TEL.dataunit, L_TEL.swmode, L_TEL.caltask, L_TEL.caltype, L_TEL.redmode, L_TEL.waveform, L_TEL.chopfreq, L_TEL.chopcoor, L_TEL.chopthrw, L_TEL.chopdirn, L_TEL.ewtilt, L_TEL.nstilt, L_TEL.ew_scale, L_TEL.ns_scale, L_TEL.ew_encode, L_TEL.ns_encode, L_TEL.xpoint, L_TEL.ypoint, L_TEL.uxpnt, L_TEL.uypnt, L_TEL.focusv, L_TEL.focusl, L_TEL.focusr, L_TEL.utstart_dmf, L_TEL.utstop_dmf, L_TEL.tuple_id from L_TEL 
          where tel# >= @start and tel# < (@start+100000)
          order by tel#
        end

      if (@@transtate <> 0) 
        begin
          rollback transaction archive
          if (@@transtate <> 3)
            return -103
          else
            return -3
        end

      if exists (select wea# from WEA 
           where wea# >= @start and wea# < (@start+100000))
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert WEA
          select L_WEA.wea#, L_WEA.utstart, L_WEA.utstop, L_WEA.projid, L_WEA.scan, L_WEA.ws#, L_WEA.tau#, L_WEA.pha#, L_WEA.tamb, L_WEA.pressure, L_WEA.humidity, L_WEA.tau, L_WEA.tau_rms, L_WEA.tau_date, L_WEA.pha, L_WEA.pha_date, L_WEA.utstart_dmf, L_WEA.utstop_dmf, L_WEA.tuple_id from L_WEA where wea# >
          (select max(wea#) from WEA 
           where wea# >= @start and wea# < (@start+100000))
          order by wea#
        end
      else
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert WEA select L_WEA.wea#, L_WEA.utstart, L_WEA.utstop, L_WEA.projid, L_WEA.scan, L_WEA.ws#, L_WEA.tau#, L_WEA.pha#, L_WEA.tamb, L_WEA.pressure, L_WEA.humidity, L_WEA.tau, L_WEA.tau_rms, L_WEA.tau_date, L_WEA.pha, L_WEA.pha_date, L_WEA.utstart_dmf, L_WEA.utstop_dmf, L_WEA.tuple_id from L_WEA
          where wea# >= @start and wea# < (@start+100000)
          order by wea#
        end

      if (@@transtate <> 0) 
        begin
          rollback transaction archive
          if (@@transtate <> 3)
            return -104
          else
            return -4
        end

      if exists (select sca# from SCA 
           where sca# >= @start and sca# < (@start+100000))
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert SCA
          select L_SCA.sca#, L_SCA.ut, L_SCA.ses#, L_SCA.sou#, L_SCA.wea#, L_SCA.tel#, L_SCA.gsdfile, L_SCA.projid, L_SCA.scan, L_SCA.object, L_SCA.object2, L_SCA.frontend, L_SCA.frontype, L_SCA.nofchan, L_SCA.backend, L_SCA.backtype, L_SCA.nobchan, L_SCA.norsect, L_SCA.chopping, L_SCA.obscal, L_SCA.obscen, L_SCA.obsfly, L_SCA.obsfocus, L_SCA.obsmap, L_SCA.obsmode, L_SCA.coordcd, L_SCA.coordcd2, L_SCA.radate, L_SCA.decdate, L_SCA.az, L_SCA.el, L_SCA.restfrq1, L_SCA.restfrq2, L_SCA.velocity, L_SCA.vdef, L_SCA.vref, L_SCA.ut1c, L_SCA.lst, L_SCA.samprat, L_SCA.nocycles, L_SCA.cycllen, L_SCA.noscans, L_SCA.noscnpts, L_SCA.nocycpts, L_SCA.xcell0, L_SCA.ycell0, L_SCA.xref, L_SCA.yref, L_SCA.xsource, L_SCA.ysource, L_SCA.frame, L_SCA.frame2, L_SCA.xyangle, L_SCA.deltax, L_SCA.deltay, L_SCA.scanang, L_SCA.yposang, L_SCA.afocusv, L_SCA.afocush, L_SCA.afocusr, L_SCA.tcold, L_SCA.thot, L_SCA.noswvar, L_SCA.nophase, L_SCA.snstvty, L_SCA.phase, L_SCA.mapunit, L_SCA.nomapdim, L_SCA.nopts, L_SCA.noxpts, L_SCA.noypts, L_SCA.reversal, L_SCA.directn, L_SCA.xsign, L_SCA.ysign, L_SCA.spect, L_SCA.resp, L_SCA.stdspect, L_SCA.trms, L_SCA.radate_int, L_SCA.decdate_int, L_SCA.ut_dmf, L_SCA.tuple_id, L_SCA.polarity, L_SCA.sbmode from L_SCA where sca# >
          (select max(sca#) from SCA 
           where sca# >= @start and sca# < (@start+100000))
          order by sca#
        end
      else
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert SCA select L_SCA.sca#, L_SCA.ut, L_SCA.ses#, L_SCA.sou#, L_SCA.wea#, L_SCA.tel#, L_SCA.gsdfile, L_SCA.projid, L_SCA.scan, L_SCA.object, L_SCA.object2, L_SCA.frontend, L_SCA.frontype, L_SCA.nofchan, L_SCA.backend, L_SCA.backtype, L_SCA.nobchan, L_SCA.norsect, L_SCA.chopping, L_SCA.obscal, L_SCA.obscen, L_SCA.obsfly, L_SCA.obsfocus, L_SCA.obsmap, L_SCA.obsmode, L_SCA.coordcd, L_SCA.coordcd2, L_SCA.radate, L_SCA.decdate, L_SCA.az, L_SCA.el, L_SCA.restfrq1, L_SCA.restfrq2, L_SCA.velocity, L_SCA.vdef, L_SCA.vref, L_SCA.ut1c, L_SCA.lst, L_SCA.samprat, L_SCA.nocycles, L_SCA.cycllen, L_SCA.noscans, L_SCA.noscnpts, L_SCA.nocycpts, L_SCA.xcell0, L_SCA.ycell0, L_SCA.xref, L_SCA.yref, L_SCA.xsource, L_SCA.ysource, L_SCA.frame, L_SCA.frame2, L_SCA.xyangle, L_SCA.deltax, L_SCA.deltay, L_SCA.scanang, L_SCA.yposang, L_SCA.afocusv, L_SCA.afocush, L_SCA.afocusr, L_SCA.tcold, L_SCA.thot, L_SCA.noswvar, L_SCA.nophase, L_SCA.snstvty, L_SCA.phase, L_SCA.mapunit, L_SCA.nomapdim, L_SCA.nopts, L_SCA.noxpts, L_SCA.noypts, L_SCA.reversal, L_SCA.directn, L_SCA.xsign, L_SCA.ysign, L_SCA.spect, L_SCA.resp, L_SCA.stdspect, L_SCA.trms, L_SCA.radate_int, L_SCA.decdate_int, L_SCA.ut_dmf, L_SCA.tuple_id, L_SCA.polarity, L_SCA.sbmode from L_SCA
          where sca# >= @start and sca# < (@start+100000)
          order by sca#
        end

      if (@@transtate <> 0) 
        begin
          rollback transaction archive
          if (@@transtate <> 3)
            return -105
          else
            return -5
        end

      if exists (select sph# from SPH 
           where sph# >= @start and sph# < (@start+100000))
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert SPH
          select L_SPH.sph#, L_SPH.sca#, L_SPH.ut, L_SPH.projid, L_SPH.scan, L_SPH.band, L_SPH.backend, L_SPH.filter, L_SPH.aperture, L_SPH.spect, L_SPH.resp, L_SPH.stdspect, L_SPH.trms, L_SPH.cyclrev, L_SPH.sntvtyrg, L_SPH.timecnst, L_SPH.freqres, L_SPH.obsfreq, L_SPH.restfreq, L_SPH.befenulo, L_SPH.bw, L_SPH.trx, L_SPH.stsys, L_SPH.tsky, L_SPH.ttel, L_SPH.gains, L_SPH.tcal, L_SPH.tauh2o, L_SPH.eta_sky, L_SPH.alpha, L_SPH.g_s, L_SPH.eta_tel, L_SPH.t_sky_im, L_SPH.eta_sky_im, L_SPH.t_sys_im, L_SPH.ta_sky, L_SPH.cm, L_SPH.bm, L_SPH.overlap, L_SPH.bescon, L_SPH.nobesdch, L_SPH.besspec, L_SPH.betotif, L_SPH.befesb, L_SPH.ut_dmf, L_SPH.tuple_id, L_SPH.mixer_id from L_SPH where sph# >
          (select max(sph#) from SPH 
           where sph# >= @start and sph# < (@start+100000))
          order by sph#
        end
      else
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert SPH select L_SPH.sph#, L_SPH.sca#, L_SPH.ut, L_SPH.projid, L_SPH.scan, L_SPH.band, L_SPH.backend, L_SPH.filter, L_SPH.aperture, L_SPH.spect, L_SPH.resp, L_SPH.stdspect, L_SPH.trms, L_SPH.cyclrev, L_SPH.sntvtyrg, L_SPH.timecnst, L_SPH.freqres, L_SPH.obsfreq, L_SPH.restfreq, L_SPH.befenulo, L_SPH.bw, L_SPH.trx, L_SPH.stsys, L_SPH.tsky, L_SPH.ttel, L_SPH.gains, L_SPH.tcal, L_SPH.tauh2o, L_SPH.eta_sky, L_SPH.alpha, L_SPH.g_s, L_SPH.eta_tel, L_SPH.t_sky_im, L_SPH.eta_sky_im, L_SPH.t_sys_im, L_SPH.ta_sky, L_SPH.cm, L_SPH.bm, L_SPH.overlap, L_SPH.bescon, L_SPH.nobesdch, L_SPH.besspec, L_SPH.betotif, L_SPH.befesb, L_SPH.ut_dmf, L_SPH.tuple_id, L_SPH.mixer_id from L_SPH
          where sph# >= @start and sph# < (@start+100000)
          order by sph#
        end

      if (@@transtate <> 0) 
        begin
          rollback transaction archive
          if (@@transtate <> 3)
            return -106
          else
            return -6
        end

      if exists (select sub# from SUB 
           where sub# >= @start and sub# < (@start+100000))
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert SUB
          select L_SUB.sub#, L_SUB.sca#, L_SUB.ut, L_SUB.projid, L_SUB.scan, L_SUB.subscan, L_SUB.xcell0, L_SUB.ycell0, L_SUB.lst, L_SUB.airmass, L_SUB.samprat, L_SUB.nocycles, L_SUB.ncycle, L_SUB.cycllen, L_SUB.noscans, L_SUB.nscan, L_SUB.noscnpts, L_SUB.nocycpts, L_SUB.ncycpts, L_SUB.intgr, L_SUB.ut_dmf, L_SUB.tuple_id from L_SUB where sub# >
          (select max(sub#) from SUB 
           where sub# >= @start and sub# < (@start+100000))
          order by sub#
        end
      else
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert SUB select L_SUB.sub#, L_SUB.sca#, L_SUB.ut, L_SUB.projid, L_SUB.scan, L_SUB.subscan, L_SUB.xcell0, L_SUB.ycell0, L_SUB.lst, L_SUB.airmass, L_SUB.samprat, L_SUB.nocycles, L_SUB.ncycle, L_SUB.cycllen, L_SUB.noscans, L_SUB.nscan, L_SUB.noscnpts, L_SUB.nocycpts, L_SUB.ncycpts, L_SUB.intgr, L_SUB.ut_dmf, L_SUB.tuple_id from L_SUB
          where sub# >= @start and sub# < (@start+100000)
          order by sub#
        end

      if (@@transtate <> 0) 
        begin
          rollback transaction archive
          if (@@transtate <> 3)
            return -107
          else
            return -7
        end

   commit transaction archive

   if (@@transtate <> 1) 
     begin
       rollback transaction archive
       if (@@transtate <> 3)
         return -110
       else
         return -10
     end

/*
** Prepare Loading tables for next read.
*/
   begin transaction empty

      delete from L_SES
          where ses# < (select max(ses#) from L_SES)

      if (@@transtate <> 0) 
        begin
          rollback transaction empty
          if (@@transtate <> 3)
            return -201
          else
            return -11
        end

      delete from L_SOU
          where sou# < (select max(sou#) from L_SOU)

      if (@@transtate <> 0) 
        begin
          rollback transaction empty
          if (@@transtate <> 3)
            return -202
          else
            return -12
        end

      delete from L_WEA
          where wea# < (select max(wea#) from L_WEA)

      if (@@transtate <> 0) 
        begin
          rollback transaction empty
          if (@@transtate <> 3)
            return -203
          else
            return -13
        end

      delete from L_SCA
          where sca# < (select max(sca#) from L_SCA)

      if (@@transtate <> 0) 
        begin
          rollback transaction empty
          if (@@transtate <> 3)
            return -204
          else
            return -14
        end

      delete from L_TEL
          where tel# < (select max(tel#) from L_TEL)

      if (@@transtate <> 0) 
        begin
          rollback transaction empty
          if (@@transtate <> 3)
            return -205
          else
            return -15
        end

      delete from L_SPH
          where sph# < (select max(sph#) from L_SPH)

      if (@@transtate <> 0) 
        begin
          rollback transaction empty
          if (@@transtate <> 3)
            return -206
          else
            return -16
        end

      delete from L_SUB
          where sub# < (select max(sub#) from L_SUB)

      if (@@transtate <> 0) 
        begin
          rollback transaction empty
          if (@@transtate <> 3)
            return -207
          else
            return -17
        end

   commit transaction empty

   if (@@transtate <> 1) 
     begin
       rollback transaction empty
       if (@@transtate <> 3)
         return -210
       else
         return -20
     end


   checkpoint
   return 0


go 


sp_procxmode 'putarch', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putlsca'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putlsca" >>>>>'
go 

setuser 'dbo'
go 

create procedure putlsca
(  @ses#          id,
   @sou#          id,
   @wea#          id,
   @tel#          id,
   @ut            dt8,
   @gsdfile       vc120,
   @projid        vc16,
   @scan          r8,
   @object        vc16,
   @object2       vc16,     
   @frontend      vc16,   
   @frontype      vc16,   
   @nofchan       i4  =   1,     
   @backend       vc16,   
   @backtype      vc16,   
   @nobchan       i4  =   1,     
   @norsect       i4  =   1,
   @chopping      l1,     
   @obscal        l1  =   0,     
   @obscen        l1,     
   @obsfly        l1,     
   @obsfocus      l1,     
   @obsmap        l1,     
   @obsmode       vc16,   
   @coordcd       vc16,   
   @coordcd2      i4,     
   @radate        r8,     
   @decdate       r8,     
   @az            r8,     
   @el            r8,     
   @restfrq1      r8,
   @restfrq2      r8,
   @velocity      r8  = 0.0,     
   @vdef          vc16 = "",   
   @vref          vc16 = "",
   @ut1c          r8,     
   @lst           r8,     
   @samprat       i4,     
   @nocycles      i4,     
   @cycllen       i4,     
   @noscans       i4,     
   @noscnpts      i4,     
   @nocycpts      i4,     
   @xcell0        r4,
   @ycell0        r4,
   @xref          r8,     
   @yref          r8,     
   @xsource       r8,     
   @ysource       r8,     
   @frame         vc16,   
   @frame2        i4,     
   @xyangle       r8,     
   @deltax        r8,     
   @deltay        r8,     
   @scanang       r8,     
   @yposang       r8,     
   @afocusv       r4,     
   @afocush       r4,     
   @afocusr       r4,     
   @tcold         r4  = 0.0,
   @thot          r4  = 0.0,
   @noswvar       i4,     
   @nophase       i4  =   0,
   @snstvty       i4  =   0,
   @phase         i4  =   0,
   @mapunit       vc16,   
   @nomapdim      i4,     
   @nopts         i4,     
   @noxpts        i4,     
   @noypts        i4,     
   @reversal      l1,     
   @directn       vc16,   
   @xsign         l1,     
   @ysign         l1,
   @spect         r8   = 0.0,
   @resp          r4   = 0.0,
   @stdspect      r8   = 0.0,
   @trms          r8   = 0.0  )
as
/* 
** sql make an entry in the L_SCA table.
**
** usage :    exec putlsca @ut="mm/dd/yyyy hh:mm:ss",@xxx=yyy,....
**
*/
  declare @sca# int, @tup int, @radate_int int, @decdate_int int, @ut_dmf int

  select @sca#=max(sca#)+1, @tup=max(tuple_id)+1 from L_SCA

  if @sca# < 3600000
  begin
    select @sca# = 3600000
  end

  select @ut_dmf=datediff(ss, "01/01/1980 00:00:00", @ut), 
         @radate_int=convert(int,@radate*3.6e6), 
         @decdate_int=convert(int,@decdate*3.6e6)
         
  insert into L_SCA (  sca#,  ut,
    ses#,  sou#,  wea#,  tel#,  projid,  gsdfile,  scan,  object, 
    object2,  frontend,  frontype,  nofchan,  backend,  backtype, 
    nobchan,  norsect,  chopping,  obscal,  obscen,  obsfly,  obsfocus, 
    obsmap,  obsmode,  coordcd,  coordcd2,  radate,  decdate,  az, 
    el,  restfrq1,  restfrq2,  velocity,  vdef,  vref,  ut1c,  lst, 
    samprat,  nocycles,  cycllen,  noscans,  noscnpts,  nocycpts,
    xcell0,  ycell0,  xref,  yref,  xsource,  ysource,  frame,  frame2, 
    xyangle,  deltax,  deltay,  scanang,  yposang,  afocusv,  afocush, 
    afocusr,  tcold,  thot,  noswvar,  nophase,  snstvty,  phase, 
    mapunit,  nomapdim,  nopts,  noxpts,  noypts,  reversal,  directn, 
    xsign,  ysign,  spect,  resp,  stdspect,  trms,
    radate_int,  decdate_int,  ut_dmf,  tuple_id )
  values ( @sca#, @ut,
   @ses#, @sou#, @wea#, @tel#, @projid, @gsdfile, @scan, @object, 
   @object2, @frontend, @frontype, @nofchan, @backend, @backtype, 
   @nobchan, @norsect, @chopping, @obscal, @obscen, @obsfly, @obsfocus, 
   @obsmap, @obsmode, @coordcd, @coordcd2, @radate, @decdate, @az, 
   @el, @restfrq1, @restfrq2, @velocity, @vdef, @vref, @ut1c, @lst, 
   @samprat, @nocycles, @cycllen, @noscans, @noscnpts, @nocycpts,
   @xcell0, @ycell0, @xref, @yref, @xsource, @ysource, @frame, @frame2, 
   @xyangle, @deltax, @deltay, @scanang, @yposang, @afocusv, @afocush, 
   @afocusr, @tcold, @thot, @noswvar, @nophase, @snstvty, @phase, 
   @mapunit, @nomapdim, @nopts, @noxpts, @noypts, @reversal, @directn, 
   @xsign, @ysign, @spect, @resp, @stdspect, @trms,
   @radate_int, @decdate_int, @ut_dmf, @tup )

  return @sca#

go 


sp_procxmode 'putlsca', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putlses'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putlses" >>>>>'
go 

setuser 'dbo'
go 

create procedure putlses
(    @ut         dt8,
     @projid     vc16,
     @obsid      vc16,   
     @observer   vc16,   
     @operator   vc16,    
     @telescop   vc16,
     @longitud   r8 = 155.479721100,
     @latitude   r8 =  19.825832370,
     @height     r8 =   4.092093,     
     @mounting   vc16 = "az/alt"  )
as
/* 
** sql make an entry in the L_SES table.
**
** usage :    exec putlses @ut="mm/dd/yyyy hh:mm:ss",@projid=......
**
*/
  declare @next int, @ses# int, @tup int, @ut_dmf int,
          @op id, @oobs vc16, @oss vc16, @oto vc16

  select @next=0

  select @ses#=max(ses#), @tup=max(tuple_id) from L_SES

    if not exists (select * from L_SES
                   where ses#=@ses# and
                         projid like @projid and
                         telescop like @telescop and
                         obsid like @obsid and
                         observer like @observer and
                         operator like @operator )
    begin
      if @ses# < 3600000
      begin
         select @next=3600000, @tup=@tup+1
      end
      else
      begin
         select @next=@ses#+1, @tup=@tup+1
      end
    end

  if @next <> 0
  begin
     select @ut_dmf=datediff(ss, "01/01/1980 00:00:00", @ut)

     update L_SES set utstop = @ut, utstop_dmf=@ut_dmf where ses# = @ses#
     insert into L_SES ( ses#,  projid,  utstart,  telescop,
                       obsid,  observer,  operator,
                       longitud,  latitude,  height,  mounting,  
                       utstart_dmf,  utstop_dmf,  tuple_id )
               values(@next, @projid, @ut,      @telescop,
                      @obsid, @observer, @operator,
                      @longitud, @latitude, @height, @mounting,
                      @ut_dmf, @ut_dmf, @tup )
     return @next
  end

  return @ses#

go 


sp_procxmode 'putlses', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putlsou'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putlsou" >>>>>'
go 

setuser 'dbo'
go 

create procedure putlsou
(  @ut         dt8,
   @projid    vc16 = "",
   @object    vc16,   
   @cenmove     l1,     
   @epoch       r8,     
   @epochtyp  vc16,   
   @epocra      r8,     
   @epocdec     r8,
   @raj2000     r8,     
   @decj2000    r8,     
   @gallong     r8,     
   @gallat      r8  )
as
/* 
** sql make an entry in the L_SOU table.
**
** usage :    exec putlsou @ut="mm/dd/yyyy hh:mm:ss",@xxx=yyy,....
**
*/
  declare @next int, @sou# int, @tup int, 
          @epocra_int int, @epocdec_int int,
          @raj2000_int int, @decj2000_int int,
          @gallong_int int, @gallat_int int, @ut_dmf int

  select @next=0,
         @ut_dmf=datediff(ss, "01/01/1980 00:00:00", @ut), 
         @epocra_int=convert(int,@epocra*3.6e6), 
         @epocdec_int=convert(int,@epocdec*3.6e6),
         @raj2000_int=convert(int,@raj2000*3.6e6), 
         @decj2000_int=convert(int,@decj2000*3.6e6),
         @gallong_int=convert(int,@gallong*3.6e6), 
         @gallat_int=convert(int,@gallat*3.6e6)

  select @sou#=max(sou#)+1, @tup=max(tuple_id)+1 from L_SOU

  if @sou# = 1
  begin
    select @next=1, @tup=1
  end
  else
  begin
      if exists (select sou# from L_SOU where object like @object
                 and epoch = @epoch and epocra_int = @epocra_int and
                 epocdec_int = @epocdec_int)
        begin
          select @sou# = sou# from L_SOU where object like @object
                 and epoch = @epoch and epocra_int = @epocra_int and
                 epocdec_int = @epocdec_int
        end
      else if exists (select sou# from SOU where object like @object
                 and epoch = @epoch and epocra_int = @epocra_int and
                 epocdec_int = @epocdec_int)
        begin
          select @sou# = sou# from SOU where object like @object
                 and epoch = @epoch and epocra_int = @epocra_int and
                 epocdec_int = @epocdec_int
        end
      else
        begin
	  select @next = @sou#
        end
  end

  if @next <> 0
  begin
     insert into L_SOU ( sou#, ut, object, cenmove, epoch,
                       epochtyp, epocra, epocdec, raj2000, decj2000,
                       gallong, gallat,  epocra_int,  epocdec_int,
                       raj2000_int,  decj2000_int,  
                       gallong_int,  gallat_int,  ut_dmf,  tuple_id )
               values(@next, @ut, @object, @cenmove, @epoch,
                      @epochtyp, @epocra, @epocdec, @raj2000,
                      @decj2000, @gallong, @gallat, @epocra_int, @epocdec_int,
                      @raj2000_int, @decj2000_int,
                      @gallong_int, @gallat_int, @ut_dmf,  @tup )


     return @next
  end

  return @sou#

go 


sp_procxmode 'putlsou', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putlsph'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putlsph" >>>>>'
go 

setuser 'dbo'
go 

create procedure putlsph
(  @ut           dt8,
   @sca#          id,
   @projid      vc16,
   @scan          i4,
   @band          i4,
   @backend     vc16,   
   @filter      vc16 =  "",
   @aperture    vc16 =  "",
   @spect         r8 = 0.0,
   @resp          r4 = 0.0,
   @stdspect      r8 = 0.0,
   @trms          r8 = 0.0,
   @cyclrev       i4 =   0,
   @sntvtyrg    vc16 =  "",
   @timecnst    vc16 =  "",
   @freqres       r4 = 0.0,
   @obsfreq       r8,     
   @restfreq      r8,     
   @befenulo      r8 = 0.0,     
   @bw            r4 = 0.0,
   @trx           r4 = 0.0,     
   @stsys         r4 = 0.0,     
   @tsky          r4 = 0.0,     
   @ttel          r4 = 0.0,     
   @gains         r4 = 0.0,     
   @tcal          r4 = 0.0,     
   @tauh2o        r4 = 0.0,     
   @eta_sky       r4 = 0.0,     
   @alpha         r4 = 0.0,     
   @g_s           r4 = 0.0,     
   @eta_tel       r4 = 0.0,     
   @t_sky_im      r4 = 0.0,     
   @eta_sky_im    r4 = 0.0,     
   @t_sys_im      r4 = 0.0,     
   @ta_sky        r4 = 0.0,      
   @cm            i4 = 0.0,     
   @bm            i4 = 0.0,     
   @overlap       r4 = 0.0,     
   @bescon        i4 =   0,     
   @nobesdch      i4 =   0,     
   @besspec       i4 =   0,     
   @betotif       r8 = 0.0,     
   @befesb        i4 =   0   )
as
/* 
** sql make an entry in the L_SPH table.
**
** usage :    exec putlsph @ut="mm/dd/yyyy hh:mm:ss",@xxx=yyy,....
**
*/
  declare @sph# int, @tup int, @ut_dmf int

  select @sph#=max(sph#)+1, @tup=max(tuple_id)+1 from L_SPH

  if @sph# < 3600000
  begin
    select @sph# = 3600000
  end

  select @ut_dmf=datediff(ss, "01/01/1980 00:00:00", @ut)
  insert into L_SPH (  sph#,
           ut,  sca#,  projid,  scan,  band,  backend,  filter,  aperture,
           spect,  resp,  stdspect,  trms,  cyclrev,  sntvtyrg,  timecnst,
           freqres,  obsfreq,  restfreq,  befenulo,  bw,  trx,  stsys,
           tsky,  ttel,  gains,  tcal,  tauh2o,  eta_sky,  alpha,  g_s,
           eta_tel,  t_sky_im,  eta_sky_im,  t_sys_im,  ta_sky,  cm,
           bm,  overlap,  bescon,  nobesdch,  besspec,  betotif,  befesb,
           ut_dmf,  tuple_id )
  values ( @sph#,
          @ut, @sca#, @projid, @scan, @band, @backend, @filter, @aperture,
          @spect, @resp, @stdspect, @trms, @cyclrev, @sntvtyrg, @timecnst,
          @freqres, @obsfreq, @restfreq, @befenulo, @bw, @trx, @stsys,
          @tsky, @ttel, @gains, @tcal, @tauh2o, @eta_sky, @alpha, @g_s,
          @eta_tel, @t_sky_im, @eta_sky_im, @t_sys_im, @ta_sky, @cm,
          @bm, @overlap, @bescon, @nobesdch, @besspec, @betotif, @befesb,
          @ut_dmf, @tup )


  return @sph#

go 


sp_procxmode 'putlsph', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putlsub'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putlsub" >>>>>'
go 

setuser 'dbo'
go 

create procedure putlsub
(  @ut        dt8,
   @sca#       id,
   @projid   vc16,
   @scan       r8,     
   @subscan    i2,
   @xcell0     r4,     
   @ycell0     r4,     
   @lst        r8,     
   @airmass    r8,     
   @samprat    i4,     
   @nocycles   i4,     
   @ncycle     i4,     
   @cycllen    i4,     
   @noscans    i4,     
   @nscan      i4,     
   @noscnpts   i4,     
   @nocycpts   i4,     
   @ncycpts    i4,     
   @intgr      i4   =  -1  )
as
/* 
** sql make an entry in the L_SUB table.
**
** usage :    exec putlsub @ut="mm/dd/yyyy hh:mm:ss",@xxx=yyy,....
**
*/
  declare @sub# int, @tup int, @ut_dmf int

  select @sub#=max(sub#)+1, @tup=max(tuple_id)+1 from L_SUB

  if @sub# < 3600000
  begin
    select @sub# = 3600000
  end

  select @ut_dmf=datediff(ss, "01/01/1980 00:00:00", @ut)
  insert into L_SUB (  sub#, sca#, 
           ut,  projid,  scan,  subscan,  xcell0,  ycell0,
           lst,  airmass,  samprat,  nocycles,  ncycle,  cycllen,
           noscans,  nscan,  noscnpts,  nocycpts,  ncycpts,  intgr,
           ut_dmf,  tuple_id )
  values ( @sub#, @sca#,
          @ut, @projid, @scan, @subscan, @xcell0, @ycell0,
          @lst, @airmass, @samprat, @nocycles, @ncycle, @cycllen,
          @noscans, @nscan, @noscnpts, @nocycpts, @ncycpts, @intgr,
          @ut_dmf, @tup )

  return @sub#

go 


sp_procxmode 'putlsub', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putltel'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putltel" >>>>>'
go 

setuser 'dbo'
go 

create procedure putltel
(  @ut            dt8,
   @projid        vc16,
   @scan          i4,
   @frontend      vc16,
   @frontype      vc16,
   @nofchan       i4    =   1,
   @backend       vc16,
   @backtype      vc16,
   @noifpbes      i4    =   0,
   @nobchan       i4    =   1,
   @config        i4    =   0,
   @outputt       vc16  =  "",
   @calsrc        vc16  =  "",
   @shftfrac      r4    = 0.0,
   @badchv        r8    = -1.797693135e+38,
   @norchan       i4    =   1,
   @norsect       i4    =   1,
   @dataunit      vc16  =  "",
   @swmode        vc16  =  "",
   @caltask       vc16  =  "",
   @caltype       vc16  =  "",
   @redmode       vc16  =  "",
   @waveform      vc16,
   @chopfreq      r4,
   @chopcoor      vc16,
   @chopthrw      r4,
   @chopdirn      r4,
   @ewtilt        r4,
   @nstilt        r4,
   @ew_scale      r4    = 0.0,
   @ns_scale      r4    = 0.0,
   @ew_encode     i4    = 0.0,
   @ns_encode     i4    = 0.0,
   @xpoint        r8,
   @ypoint        r8,
   @uxpnt         r8,
   @uypnt         r8,
   @focusv        r4,
   @focusl        r4,
   @focusr        r4    )
as
/* 
** sql make an entry in the L_TEL table.
**
** usage :    exec putltel @ut="mm/dd/yyyy hh:mm:ss",@xxx=yyy,....
**
*/
  declare @next int, @tel# int, @tup int, @ut_dmf int

  select @next=0

  select @tel#=max(tel#), @tup=max(tuple_id) from L_TEL

    if not exists (select * from L_TEL
                   where tel#=@tel# and 
                         projid like @projid and
                         frontend like @frontend and
                         frontype like @frontype and
                         nofchan=@nofchan and
                         backend like @backend and
                         backtype like @backtype and
                         noifpbes=@noifpbes and
                         nobchan=@nobchan and
                         config=@config and
                         outputt like @outputt and
                         calsrc like @calsrc and
                         shftfrac=@shftfrac and
                         badchv=@badchv and
                         norchan=@norchan and
                         norsect=@norsect and
                         dataunit like @dataunit and
                         swmode like @swmode and
                         caltask like @caltask and
                         caltype like @caltype and
                         redmode like @redmode and
                         waveform like @waveform and
                         chopfreq=@chopfreq and
                         chopcoor like @chopcoor and
                         chopthrw=@chopthrw and
                         chopdirn=@chopdirn and
                         ewtilt=@ewtilt and
                         nstilt=@nstilt and
                         ew_scale=@ew_scale and
                         ns_scale=@ns_scale and
                         ew_encode=@ew_encode and
                         ns_encode=@ns_encode and
                         xpoint=@xpoint and
                         ypoint=@ypoint and
                         uxpnt=@uxpnt and
                         uypnt=@uypnt and
                         focusv=@focusv and
                         focusl=@focusl and
                         focusr=@focusr )
    begin
      if @tel# < 3600000
      begin
        select @next=3600000,  @tup=@tup+1
      end
      else
      begin
        select @next=@tel#+1,  @tup=@tup+1
      end
    end

  if @next <> 0
  begin
     select @ut_dmf=datediff(ss, "01/01/1980 00:00:00", @ut)

     update L_TEL set utstop = @ut, utstop_dmf=@ut_dmf where tel# = @tel#
     insert into L_TEL ( tel#, utstart,
              projid,  scan,  frontend,  frontype,  nofchan,  backend,
              backtype,  noifpbes,  nobchan,  config,  outputt,  calsrc,
              shftfrac,  badchv,  norchan,  norsect,  dataunit,  swmode,
              caltask,  caltype,  redmode,  waveform,  chopfreq,  chopcoor,
              chopthrw,  chopdirn,
              ewtilt,  nstilt,  ew_scale,  ns_scale,  ew_encode,  ns_encode,
              xpoint,  ypoint,  uxpnt,  uypnt,  focusv,  focusl,  focusr,
              fe#,  eff#,  be#,  smu#,  poi#,  foc#,  
              utstart_dmf,  utstop_dmf,  tuple_id )
     values (@next, @ut,
             @projid, @scan, @frontend, @frontype, @nofchan, @backend,
             @backtype, @noifpbes, @nobchan, @config, @outputt, @calsrc,
             @shftfrac, @badchv, @norchan, @norsect, @dataunit, @swmode,
             @caltask, @caltype, @redmode, @waveform, @chopfreq, @chopcoor,
             @chopthrw, @chopdirn, 
             @ewtilt, @nstilt, @ew_scale, @ns_scale, @ew_encode, @ns_encode,
             @xpoint, @ypoint, @uxpnt, @uypnt, @focusv, @focusl, @focusr,
                0,    0,     0,     0,     0 ,    0, 
             @ut_dmf, @ut_dmf, @tup )

     return @next
  end

  return @tel#

go 


sp_procxmode 'putltel', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putlwea'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putlwea" >>>>>'
go 

setuser 'dbo'
go 

create procedure putlwea
(    @ut        dt8,
     @projid   vc16,
     @scan       i4,
     @tamb       r8,
     @pressure   r8,
     @humidity   r8,
     @tau        r4 = -1.0,
     @tau_date vc16 =   "8001010000",
     @tau_rms    r4 =  0.0,
     @pha        r4 = -1.0,
     @pha_date vc16 =   "8001010000"   )

as
/* 
** sql make an entry in the L_WEA table.
**
** usage :    exec putlwea @ut="mm/dd/yyyy hh:mm:ss",@xxx=yyy,....
**
*/
  declare @next int, @wea# int, @tup int, @ut_dmf int,
          @ot r8, @op r8, @oh r8, @proj vc16, @ta r4, @ph r4,
          @tdate dt8, @pdate dt8, @tmin int, @pmin int

  select @next=0

  select @wea#=max(wea#), @tup=max(tuple_id) from L_WEA

    select @proj=projid, 
           @ot=tamb, @op=pressure, @oh=humidity,
           @ta=tau, @ph=pha  
    from L_WEA
    where wea#=@wea#

    if abs(@ot-@tamb) > 1 or abs(@op-@pressure) > 5 or 
       abs(@oh-@humidity) > 2.5 or @proj not like @projid or
       abs(@ta-@tau) > 0.005 or abs(@ph-@pha) > 0.1
    begin
      if @wea# < 3600000
      begin
        select @next=3600000, @tup = @tup+1
      end
      else
      begin
        select @next=@wea#+1, @tup = @tup+1
      end
    end

  if @next <> 0
  begin
     select @ut_dmf=datediff(ss, "01/01/1980 00:00:00", @ut)

     if (char_length(@tau_date) < 10) 
       select @tau_date = "8001010000"
     if (char_length(@pha_date) < 10) 
       select @pha_date = "8001010000"

/*
** Catch timestamp error from APB incorrectly adding 15 minutes to 
** the PC timestamp to arrive at the notice-board value:
** Simply recalculate the date from the day + the total number of
** minutes elapsed since the start of the day.
** Just to be sure: do the same thing for the Tau.
** Should be fixed on the VAX, but...
*/

     select @tdate= convert(datetime,(substring(@tau_date,1,6)+" 00:00:00")),
            @tmin = 60.0*convert(int,(substring(@tau_date,7,2)))+
                    convert(int,(substring(@tau_date,9,2))),
            @pdate= convert(datetime,(substring(@pha_date,1,6)+" 00:00:00")),
            @pmin = 60.0*convert(int,(substring(@pha_date,7,2)))+
                    convert(int,(substring(@pha_date,9,2)))

     select @tdate=dateadd(mi,@tmin,@tdate),
            @pdate=dateadd(mi,@pmin,@pdate)

     update L_WEA set utstop = @ut, utstop_dmf = @ut_dmf where wea# = @wea#
     insert into L_WEA ( wea#,  utstart,  projid,  scan, 
                       tamb,  pressure,  humidity,
                       tau,  tau_rms,  tau_date, pha,  pha_date,  
                       utstart_dmf, utstop_dmf, tuple_id )
              values (@next,  @ut,     @projid, @scan,
                      @tamb, @pressure, @humidity,
                      @tau, @tau_rms, @tdate, @pha, @pdate, 
	              @ut_dmf, @ut_dmf, @tup )
     return @next
  end

  return @wea#

go 


sp_procxmode 'putlwea', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putnoi'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putnoi" >>>>>'
go 

setuser 'dbo'
go 

create procedure putnoi
as
/* 
** sql make an entry in the NOI table.
**
** usage :    exec putnoi
**
*/
  declare @next int, @tup int

  select @next=max(noi#), @tup=max(tuple_id) from NOI

  insert into NOI
  select (noi#+@next),  channel,  chop,  chop_err,  cal,  cal_err,
         quality, ut,  chop_thr,  source,  az, el,
         datediff(ss, "01/01/1980 00:00:00", ut), (tuple_id+@tup)
  from L_NOI

  delete from L_NOI

  select @next=max(noi#) from NOI

  return @next

go 


sp_procxmode 'putnoi', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putscan'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putscan" >>>>>'
go 

setuser 'dbo'
go 

create procedure putscan
as
/* 
** Sql to move date from the TMS tables into the CADC scan table.
** The routine copies entries since the last UT in the scan
** table.
**
*/

/*
** Copy from Loading Tables to Archive in one transaction
*/
   declare @sca_idx i4

   select @sca_idx = max(sca_idx) from scan

   insert into scan select 
       stuff(reverse(stuff(reverse(
          gsdfile),1,(charindex("/",reverse(gsdfile))),NULL)),1,13,NULL),
          reverse(substring(reverse(gsdfile),5,(charindex("/",
          reverse(gsdfile))-5))),
       upper(SCA.projid),  convert(int,SCA.scan),  SCA.sca#,
       convert(datetime,substring( substring("02/02/",1,abs(convert(int,
          abs((datepart(mm,SCA.ut)*100+datepart(dd,SCA.ut)-501.5)/300))*
          6)) + "08/02/", 1, 6) + convert(char(4),datepart(yy,SCA.ut)+1+
          convert(int,(datepart(mm,SCA.ut)*100+datepart(dd,SCA.ut))/802)) +
          " 00:00am"),  upper(obsmode),  SCA.lst,  SCA.ut,
       convert(real,datepart(hh,SCA.ut))+
          convert(real,datepart(mi,SCA.ut))/60.0+
	  convert(real,datepart(ss,SCA.ut))/3600.0,
       raj2000,  decj2000,  gallong,  gallat,  az,  el,  
       epoch,  epocra,  epocdec,  ncycle,  SCA.cycllen,  coordcd,  
       deltax,  deltay,  yposang,  xsource,  ysource,  noxpts, noypts,
       upper(SCA.object),     nscan,
       upper(SCA.frontend),   upper(SCA.frontype),
       upper(SCA.backend),    upper(SCA.backtype),
       velocity,  restfreq,  freqres,  upper(vdef),  upper(vref),
       SCA.nobchan,  SCA.norsect,
       upper(substring(swmode,1,char_length(swmode)*
                      abs(sign(ascii(swmode)-32)))+
             substring("no_chopping",3*chopping+1, 
                      (11-3*chopping)*(1-abs(sign(ascii(swmode)-32))))),
       chopfreq,  upper(filter),  upper(aperture),  SCA.spect,  SCA.trms,
       stsys,  tau,  pha,  tamb,  humidity,  epocra_int,  epocdec_int,
       raj2000_int,  decj2000_int,  gallong_int,  gallat_int,
       SCA.ut_dmf, datediff(ss, "01/01/1980 00:00:00", 
          convert(datetime,substring( substring("02/02/",1,abs(convert(int,
          abs((datepart(mm,SCA.ut)*100+datepart(dd,SCA.ut)-501.5)/300))*
          6)) + "08/02/", 1, 6) + convert(char(4),datepart(yy,SCA.ut)+1+
          convert(int,(datepart(mm,SCA.ut)*100+datepart(dd,SCA.ut))/802)) +
          " 00:00am")),  SCA.tuple_id
   from SCA,SUB,TEL,SPH,SOU,WEA
   where SCA.sca# > @sca_idx and
       SOU.sou# = SCA.sou# and SPH.sca#=SCA.sca# and 
       TEL.tel# = SCA.tel# and WEA.wea# = SCA.wea# and
       SPH.band = convert(int,SCA.norsect/2.0+0.5) and
       SUB.sca# = SCA.sca# and SUB.subscan = 1

   checkpoint
   return 0

go 


sp_procxmode 'putscan', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putscu'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putscu" >>>>>'
go 

setuser 'dbo'
go 

create procedure putscu
as
/* 
** Sql to move data from Loading Table L_SCU into table SCU
**
** usage :    exec putscu
**
*/

   declare @start i4, @minlscu i4, @maxtpu i4

/*
** First update some fields in L_SCU with the proper info.
** The UT field is very complex because a) we cannot deal with more
** than a few decimal places in the seconds, b) some entries come 
** without the decimal, and c) some number come as hh:mm:ss:dd where
** dd is the day part of the utdate(sic!) string!
*/

   select @maxtpu = max(tuple_id) from SCU
   select @minlscu = min(scu#) from L_SCU

   update L_SCU set ut=substring(utdate,6,charindex(":",
                     substring(utdate,6,char_length(utdate)-5))-1)+"/"+
                     reverse(substring(reverse(utdate),1,
                     charindex(":",reverse(utdate))-1))+"/"+
                     substring(utdate,1,4)+" "+
                     substring(utstart,1,sign(charindex(".",utstart))*
                     (charindex(".",utstart)+2)+
                     (1-sign(charindex(".",utstart)))*
                     (5+charindex(":",utstart))),
                    ut_dmf=datediff(ss, "01/01/1980 00:00:00",
                     substring(utdate,6,charindex(":",
                     substring(utdate,6,char_length(utdate)-5))-1)+"/"+
                     reverse(substring(reverse(utdate),1,
                     charindex(":",reverse(utdate))-1))+"/"+
                     substring(utdate,1,4)+" "+
                     substring(utstart,1,sign(charindex(".",utstart))*
                     (charindex(".",utstart)+2)+
                     (1-sign(charindex(".",utstart)))*
                     (5+charindex(":",utstart)))),
                    filt_350  = 0,
                    filt_450  = 0,
                    filt_750  = 0,
                    filt_850  = 0,
                    filt_1100 = 0,
                    filt_1350 = 0,
                    filt_2000 = 0,
                    ra_int=convert(int,raj2000*3.6e6), 
                    dec_int=convert(int,decj2000*3.6e6),
                    tuple_id = @maxtpu+(scu#-@minlscu)
               where scu# > @minlscu

   update L_SCU set 
       release_date=
          convert(datetime,substring( substring("02/02/",1,abs(convert(int,
          abs((datepart(mm,ut)*100+datepart(dd,ut)-501.5)/300))*
          6)) + "08/02/", 1, 6) + convert(char(4),datepart(yy,ut)+1+
          convert(int,(datepart(mm,ut)*100+datepart(dd,ut))/802))
          + " 00:00am"),
       release_date_dmf = datediff(ss, "01/01/1980 00:00:00", 
          convert(datetime,substring( substring("02/02/",1,abs(convert(int,
          abs((datepart(mm,ut)*100+datepart(dd,ut)-501.5)/300))*
          6)) + "08/02/", 1, 6) + convert(char(4),datepart(yy,ut)+1+
          convert(int,(datepart(mm,ut)*100+datepart(dd,ut))/802))
          + " 00:00am"))

   update L_SCU set filt_350 = 1 
               where (charindex("350",filt_1) != 0 
                      and charindex("1350",filt_1) = 0) 
                  or (charindex("350",filt_2) != 0 
                      and charindex("1350",filt_2) = 0) 
                  or (charindex("350",filt_3) != 0 
                      and charindex("1350",filt_3) = 0) 

   update L_SCU set filt_450 = 1 
               where  charindex("450",filt_1) != 0 
                  or  charindex("450",filt_2) != 0 
                  or  charindex("450",filt_3) != 0 

   update L_SCU set filt_750 = 1 
               where  charindex("750",filt_1) != 0 
                  or  charindex("750",filt_2) != 0 
                  or  charindex("750",filt_3) != 0 

   update L_SCU set filt_850 = 1 
               where  charindex("850",filt_1) != 0 
                  or  charindex("850",filt_2) != 0 
                  or  charindex("850",filt_3) != 0 

   update L_SCU set filt_1100 = 1
               where  charindex("1100",filt_1) != 0 
                  or  charindex("1100",filt_2) != 0 
                  or  charindex("1100",filt_3) != 0 

   update L_SCU set filt_1350 = 1 
               where  charindex("1350",filt_1) != 0 
                  or  charindex("1350",filt_2) != 0 
                  or  charindex("1350",filt_3) != 0 
                  or  charindex("1300",filt_1) != 0 
                  or  charindex("1300",filt_2) != 0 
                  or  charindex("1300",filt_3) != 0 

   update L_SCU set filt_2000 = 1 
               where  charindex("2000",filt_1) != 0 
                  or  charindex("2000",filt_2) != 0 
                  or  charindex("2000",filt_3) != 0 
    
/*
** Copy from Loading Tables to archive table in one transaction
*/

   begin transaction scu2db

      if exists (select scu# from SCU where scu# > 0) 
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert SCU
          select L_SCU.scu#, L_SCU.ut, L_SCU.scu_id, L_SCU.sdffile, L_SCU.proj_id, L_SCU.run, L_SCU.release_date, L_SCU.raj2000, L_SCU.decj2000, L_SCU.object, L_SCU.obj_type, L_SCU.accept, L_SCU.align_ax, L_SCU.align_sh, L_SCU.alt_obs, L_SCU.amend, L_SCU.amstart, L_SCU.apend, L_SCU.apstart, L_SCU.atend, L_SCU.atstart, L_SCU.boloms, L_SCU.calibrtr, L_SCU.cal_frq, L_SCU.cent_crd, L_SCU.chop_crd, L_SCU.chop_frq, L_SCU.chop_fun, L_SCU.chop_pa, L_SCU.chop_thr, L_SCU.data_dir, L_SCU.drgroup, L_SCU.drrecipe, L_SCU.end_azd, L_SCU.end_el, L_SCU.end_eld, L_SCU.equinox, L_SCU.exposed, L_SCU.exp_no, L_SCU.exp_time, L_SCU.e_per_i, L_SCU.filter, L_SCU.focus_sh, L_SCU.gain, L_SCU.hstend, L_SCU.hststart, L_SCU.humend, L_SCU.humstart, L_SCU.int_no, L_SCU.jigl_cnt, L_SCU.jigl_nam, L_SCU.j_per_s, L_SCU.j_repeat, L_SCU.locl_crd, L_SCU.long, L_SCU.lat, L_SCU.long2, L_SCU.lat2, L_SCU.map_hght, L_SCU.map_pa, L_SCU.map_wdth, L_SCU.map_x, L_SCU.map_y, L_SCU.max_el, L_SCU.meandec, L_SCU.meanra, L_SCU.meas_no, L_SCU.min_el, L_SCU.mjd1, L_SCU.mjd2, L_SCU.mode, L_SCU.n_int, L_SCU.n_measur, L_SCU.observer, L_SCU.sam_crds, L_SCU.sam_dx, L_SCU.sam_dy, L_SCU.sam_mode, L_SCU.sam_pa, L_SCU.scan_rev, L_SCU.start_el, L_SCU.state, L_SCU.stend, L_SCU.strt_azd, L_SCU.strt_eld, L_SCU.ststart, L_SCU.swtch_md, L_SCU.swtch_no, L_SCU.s_per_e, L_SCU.utdate, L_SCU.utend, L_SCU.utstart, L_SCU.wvplate, L_SCU.wpltname, L_SCU.align_dx, L_SCU.align_dy, L_SCU.align_x, L_SCU.align_y, L_SCU.az_err, L_SCU.chopping, L_SCU.el_err, L_SCU.focus_dz, L_SCU.focus_z, L_SCU.seeing, L_SCU.see_date, L_SCU.tau_225, L_SCU.tau_date, L_SCU.tau_rms, L_SCU.uaz, L_SCU.uel, L_SCU.ut_date, L_SCU.chop_lg, L_SCU.chop_pd, L_SCU.cntr_du3, L_SCU.cntr_du4, L_SCU.etatel_1, L_SCU.etatel_2, L_SCU.etatel_3, L_SCU.filt_350, L_SCU.filt_450, L_SCU.filt_750, L_SCU.filt_850, L_SCU.filt_1100, L_SCU.filt_1350, L_SCU.filt_2000, L_SCU.filt_1, L_SCU.filt_2, L_SCU.filt_3, L_SCU.flat, L_SCU.meas_bol, L_SCU.n_bols, L_SCU.n_subs, L_SCU.phot_bbf, L_SCU.rebin, L_SCU.ref_adc, L_SCU.ref_chan, L_SCU.sam_time, L_SCU.simulate, L_SCU.sub_1, L_SCU.sub_2, L_SCU.sub_3, L_SCU.s_gd_bol, L_SCU.s_guard, L_SCU.tauz_1, L_SCU.tauz_2, L_SCU.tauz_3, L_SCU.t_amb, L_SCU.t_cold_1, L_SCU.t_cold_2, L_SCU.t_cold_3, L_SCU.t_hot, L_SCU.t_tel, L_SCU.wave_1, L_SCU.wave_2, L_SCU.wave_3, L_SCU.ut_dmf, L_SCU.ra_int, L_SCU.dec_int, L_SCU.release_date_dmf, L_SCU.msbid, L_SCU.tuple_id, L_SCU.obsid from L_SCU where scu# > 
          (select max(scu#) from SCU)
          order by scu#
        end
      else
        begin
          /* Adaptive Server has expanded all '*' elements in the following statement */ insert SCU select L_SCU.scu#, L_SCU.ut, L_SCU.scu_id, L_SCU.sdffile, L_SCU.proj_id, L_SCU.run, L_SCU.release_date, L_SCU.raj2000, L_SCU.decj2000, L_SCU.object, L_SCU.obj_type, L_SCU.accept, L_SCU.align_ax, L_SCU.align_sh, L_SCU.alt_obs, L_SCU.amend, L_SCU.amstart, L_SCU.apend, L_SCU.apstart, L_SCU.atend, L_SCU.atstart, L_SCU.boloms, L_SCU.calibrtr, L_SCU.cal_frq, L_SCU.cent_crd, L_SCU.chop_crd, L_SCU.chop_frq, L_SCU.chop_fun, L_SCU.chop_pa, L_SCU.chop_thr, L_SCU.data_dir, L_SCU.drgroup, L_SCU.drrecipe, L_SCU.end_azd, L_SCU.end_el, L_SCU.end_eld, L_SCU.equinox, L_SCU.exposed, L_SCU.exp_no, L_SCU.exp_time, L_SCU.e_per_i, L_SCU.filter, L_SCU.focus_sh, L_SCU.gain, L_SCU.hstend, L_SCU.hststart, L_SCU.humend, L_SCU.humstart, L_SCU.int_no, L_SCU.jigl_cnt, L_SCU.jigl_nam, L_SCU.j_per_s, L_SCU.j_repeat, L_SCU.locl_crd, L_SCU.long, L_SCU.lat, L_SCU.long2, L_SCU.lat2, L_SCU.map_hght, L_SCU.map_pa, L_SCU.map_wdth, L_SCU.map_x, L_SCU.map_y, L_SCU.max_el, L_SCU.meandec, L_SCU.meanra, L_SCU.meas_no, L_SCU.min_el, L_SCU.mjd1, L_SCU.mjd2, L_SCU.mode, L_SCU.n_int, L_SCU.n_measur, L_SCU.observer, L_SCU.sam_crds, L_SCU.sam_dx, L_SCU.sam_dy, L_SCU.sam_mode, L_SCU.sam_pa, L_SCU.scan_rev, L_SCU.start_el, L_SCU.state, L_SCU.stend, L_SCU.strt_azd, L_SCU.strt_eld, L_SCU.ststart, L_SCU.swtch_md, L_SCU.swtch_no, L_SCU.s_per_e, L_SCU.utdate, L_SCU.utend, L_SCU.utstart, L_SCU.wvplate, L_SCU.wpltname, L_SCU.align_dx, L_SCU.align_dy, L_SCU.align_x, L_SCU.align_y, L_SCU.az_err, L_SCU.chopping, L_SCU.el_err, L_SCU.focus_dz, L_SCU.focus_z, L_SCU.seeing, L_SCU.see_date, L_SCU.tau_225, L_SCU.tau_date, L_SCU.tau_rms, L_SCU.uaz, L_SCU.uel, L_SCU.ut_date, L_SCU.chop_lg, L_SCU.chop_pd, L_SCU.cntr_du3, L_SCU.cntr_du4, L_SCU.etatel_1, L_SCU.etatel_2, L_SCU.etatel_3, L_SCU.filt_350, L_SCU.filt_450, L_SCU.filt_750, L_SCU.filt_850, L_SCU.filt_1100, L_SCU.filt_1350, L_SCU.filt_2000, L_SCU.filt_1, L_SCU.filt_2, L_SCU.filt_3, L_SCU.flat, L_SCU.meas_bol, L_SCU.n_bols, L_SCU.n_subs, L_SCU.phot_bbf, L_SCU.rebin, L_SCU.ref_adc, L_SCU.ref_chan, L_SCU.sam_time, L_SCU.simulate, L_SCU.sub_1, L_SCU.sub_2, L_SCU.sub_3, L_SCU.s_gd_bol, L_SCU.s_guard, L_SCU.tauz_1, L_SCU.tauz_2, L_SCU.tauz_3, L_SCU.t_amb, L_SCU.t_cold_1, L_SCU.t_cold_2, L_SCU.t_cold_3, L_SCU.t_hot, L_SCU.t_tel, L_SCU.wave_1, L_SCU.wave_2, L_SCU.wave_3, L_SCU.ut_dmf, L_SCU.ra_int, L_SCU.dec_int, L_SCU.release_date_dmf, L_SCU.msbid, L_SCU.tuple_id, L_SCU.obsid from L_SCU
          order by scu#
        end

      if (@@transtate <> 0) 
        begin
          rollback transaction scu2db
          if (@@transtate <> 3)
            return -101
          else
            return -1
        end

   commit transaction scu2db

   if (@@transtate <> 1) 
     begin
       rollback transaction scu2db
       if (@@transtate <> 3)
         return -110
       else
         return -10
     end

/*
** Prepare Loading tables for next read.
*/


   begin transaction empty

      delete from L_SCU
          where scu# < (select max(scu#) from L_SCU)

      if (@@transtate <> 0) 
        begin
          rollback transaction empty
          if (@@transtate <> 3)
            return -201
          else
            return -11
        end

   commit transaction empty

   if (@@transtate <> 1) 
     begin
       rollback transaction empty
       if (@@transtate <> 3)
         return -210
       else
         return -20
     end


   return 0


go 


sp_procxmode 'putscu', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.putsta'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.putsta" >>>>>'
go 

setuser 'dbo'
go 

create procedure putsta
(    @sca#        id,
     @tdv         r4    )
as
/* 
** sql make an entry in the STAndards table.
**
** usage :    exec putsta @sca#=100,@tdv=10.0
**
*/
  declare @next int, @sta# int, @tup int, @sbid int, 
          @ut datetime, @sb char(3), @ut_dmf int


  select  @sta#=-1, @next=0

  if exists (select * from SCA where sca#= @sca#)
  begin
    select @next=0
    select @sta#=max(sta#), @tup=max(tuple_id) from STA
    select @next=@sta#+1, @tup=@tup+1
  end

  if @next>0
  begin
     select @ut=ut, @ut_dmf=ut_dmf, @sbid = befesb from SPH 
     where sca#=@sca# and band=1

     select @sb = "   "
     if @sbid = 1
     begin
       select @sb = "USB"
     end
     else
     begin
       select @sb = "LSB"
     end

     insert into STA ( sta#,  ut,  sca#,  tdv,  sb,  ut_dmf,  tuple_id )
               values(@next, @ut, @sca#, @tdv, @sb, @ut_dmf, @tup )
     return @next
  end

  return @sta#

go 


sp_procxmode 'putsta', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.ra2rad'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.ra2rad" >>>>>'
go 

setuser 'dbo'
go 

create procedure ra2rad
(
     @sra      vc16,
     @result     r8 output
)
as
/* 
** Convert RA (hh:mm:ss.s)to radians
*/
     declare @ra r8

     exec hex2decim @sra, @result = @ra output
     select @result = radians(15.0*@ra)

go 

Grant Execute on dbo.ra2rad to jcmtstaff Granted by dbo
go
Grant Execute on dbo.ra2rad to observers Granted by dbo
go
Grant Execute on dbo.ra2rad to visitors Granted by dbo
go

sp_procxmode 'ra2rad', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.reldate'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.reldate" >>>>>'
go 

setuser 'dbo'
go 

create procedure reldate
(
   @ut datetime,
   @reldate datetime output
)
as
/* 
** sql to calculate the release date of an observation
** (1 year completion semester)
**
** usage :    exec putlses @ut="01/01/1998"
**
*/

   select @reldate=
     convert(datetime,substring( substring("02/02/",1,
     abs(convert(int,abs((datepart(mm,@ut)*100+datepart(dd,@ut)-501.5)/300))*
     6)) + "08/02/", 1, 6) + convert(char(4),datepart(yy,@ut)+1+
     convert(int,(datepart(mm,@ut)*100+datepart(dd,@ut))/802)) +
     " 00:00am")

   return 0

go 

Grant Execute on dbo.reldate to public Granted by dbo
go

sp_procxmode 'reldate', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- DDL for Stored Procedure 'jcmt_tms.dbo.rs_check_repl_stat'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.rs_check_repl_stat" >>>>>'
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
-- DDL for Stored Procedure 'jcmt_tms.dbo.rs_get_lastcommit'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.rs_get_lastcommit" >>>>>'
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
-- DDL for Stored Procedure 'jcmt_tms.dbo.rs_initialize_threads'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.rs_initialize_threads" >>>>>'
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
-- DDL for Stored Procedure 'jcmt_tms.dbo.rs_marker'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.rs_marker" >>>>>'
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
-- DDL for Stored Procedure 'jcmt_tms.dbo.rs_send_repserver_cmd'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.rs_send_repserver_cmd" >>>>>'
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
-- DDL for Stored Procedure 'jcmt_tms.dbo.rs_ticket'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.rs_ticket" >>>>>'
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
-- DDL for Stored Procedure 'jcmt_tms.dbo.rs_ticket_report'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.rs_ticket_report" >>>>>'
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
-- DDL for Stored Procedure 'jcmt_tms.dbo.rs_ticket_v1'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.rs_ticket_v1" >>>>>'
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
-- DDL for Stored Procedure 'jcmt_tms.dbo.rs_update_lastcommit'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.rs_update_lastcommit" >>>>>'
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
-- DDL for Stored Procedure 'jcmt_tms.dbo.rs_update_threads'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.rs_update_threads" >>>>>'
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
-- DDL for Stored Procedure 'jcmt_tms.dbo.vaxtime'
-----------------------------------------------------------------------------

print '<<<<< CREATING Stored Procedure - "jcmt_tms.dbo.vaxtime" >>>>>'
go 

setuser 'dbo'
go 

create procedure vaxtime
(    @ut        dt8  = "1/1/2050"    )
as
/* 
** sql procedure which returns ut in VAX HST format.
** If ut is not supplied, the latest ut from the SCA table
** is converted and returned.
**
** usage :    exec vaxtime @ut="mm/dd/yyyy hh:mm:ss"
**
*/
  declare @vhst varchar(32), @hst dt8, @sca# id, @utdiff r8
  declare @dd varchar(2), @mm varchar(3), @yy varchar(4)
  declare @hh varchar(2), @mi varchar(2), @ss varchar(2), @ms varchar(3)

  select @utdiff = datediff(yy, @ut, "1/1/2050")

  if @utdiff = 0
  begin
     select @sca# = max(sca#) from SCA

     if @sca# = 0
     begin
        return -1
     end

     select @ut = ut from SCA where sca# = @sca#
  end

  select @hst = dateadd(hh, -10, @ut)

  select @dd = convert(varchar(2),datepart(dd,@hst))
  select @mm = convert(varchar(3),datename(mm,@hst))
  select @yy = convert(varchar(4),datepart(yy,@hst))
  select @hh = convert(varchar(2),datepart(hh,@hst))
  select @mi = convert(varchar(2),datepart(mi,@hst))
  select @ss = convert(varchar(2),datepart(ss,@hst))
  select @ms = convert(varchar(3),datepart(ms,@hst))
  
  select @vhst = (@dd + "-" + @mm + "-" + @yy + ":" + 
                  @hh + ":" + @mi + ":" + @ss + "." + @ms)

  print "VAXTIME= %1!",@vhst

  return 0

go 


sp_procxmode 'vaxtime', unchained
go 

setuser
go 

-----------------------------------------------------------------------------
-- Dependent DDL for Object(s)
-----------------------------------------------------------------------------
use jcmt_tms
go 

sp_addthreshold jcmt_tms, 'logsegment', 51016, sp_thresholdaction
go 

sp_addthreshold jcmt_tms, 'logsegment', 921600, sp_thresholdaction
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
Grant Select on dbo.CAL to public Granted by dbo
go
Grant Select on dbo.MIXER to public Granted by dbo
go
Grant Select on dbo.LINE to public Granted by dbo
go
Grant Select on dbo.STSOU to public Granted by dbo
go
Grant Execute on dbo.getsta to public Granted by dbo
go
Grant Execute on dbo.reldate to public Granted by dbo
go
Grant Select on dbo.standards to public Granted by dbo
go
Grant Select on dbo.SOU to jcmtstaff Granted by dbo
go
Grant Select on dbo.SPH to jcmtstaff Granted by dbo
go
Grant Execute on dbo.hex2decim to jcmtstaff Granted by dbo
go
Grant Execute on dbo.ra2rad to jcmtstaff Granted by dbo
go
Grant Execute on dbo.dec2rad to jcmtstaff Granted by dbo
go
Grant Execute on dbo.lst_elev to jcmtstaff Granted by dbo
go
Grant Select on dbo.SUB to jcmtstaff Granted by dbo
go
Grant Execute on dbo.lst_rise to jcmtstaff Granted by dbo
go
Grant Execute on dbo.lst_set to jcmtstaff Granted by dbo
go
Grant Select on dbo.TAU to jcmtstaff Granted by dbo
go
Grant Select on dbo.TEL to jcmtstaff Granted by dbo
go
Grant Select on dbo.WEA to jcmtstaff Granted by dbo
go
Grant Select on dbo.CSONIGHT to jcmtstaff Granted by dbo
go
Grant Select on dbo.CSOTAU to jcmtstaff Granted by dbo
go
Grant References on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Select on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Insert on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Delete on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Update on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Delete Statistics on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Truncate Table on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Update Statistics on dbo.CRYO to jcmtstaff Granted by dbo
go
Grant Select on dbo.FLUX to jcmtstaff Granted by dbo
go
Grant Select on dbo.scan to jcmtstaff Granted by dbo
go
Grant Select on dbo.NOI to jcmtstaff Granted by dbo
go
Grant Select on dbo.PHA to jcmtstaff Granted by dbo
go
Grant Select on dbo.STA to jcmtstaff Granted by dbo
go
Grant Select on dbo.SAOPHA to jcmtstaff Granted by dbo
go
Grant Execute on dbo.checkut to jcmtstaff Granted by dbo
go
Grant Execute on dbo.findobj_het to jcmtstaff Granted by dbo
go
Grant Execute on dbo.gettrx to jcmtstaff Granted by dbo
go
Grant Select on dbo.SCA to jcmtstaff Granted by dbo
go
Grant Select on dbo.SCU to jcmtstaff Granted by dbo
go
Grant Select on dbo.SES to jcmtstaff Granted by dbo
go
Grant Select on dbo.SOU to observers Granted by dbo
go
Grant Select on dbo.SPH to observers Granted by dbo
go
Grant Execute on dbo.hex2decim to observers Granted by dbo
go
Grant Execute on dbo.ra2rad to observers Granted by dbo
go
Grant Execute on dbo.dec2rad to observers Granted by dbo
go
Grant Execute on dbo.lst_elev to observers Granted by dbo
go
Grant Select on dbo.SUB to observers Granted by dbo
go
Grant Execute on dbo.lst_rise to observers Granted by dbo
go
Grant Execute on dbo.lst_set to observers Granted by dbo
go
Grant Select on dbo.TAU to observers Granted by dbo
go
Grant Select on dbo.TEL to observers Granted by dbo
go
Grant Select on dbo.WEA to observers Granted by dbo
go
Grant Select on dbo.CSONIGHT to observers Granted by dbo
go
Grant Select on dbo.CSOTAU to observers Granted by dbo
go
Grant Select on dbo.CRYO to observers Granted by dbo
go
Grant Select on dbo.FLUX to observers Granted by dbo
go
Grant Select on dbo.MOTOR to observers Granted by dbo
go
Grant Select on dbo.scan to observers Granted by dbo
go
Grant Select on dbo.NOI to observers Granted by dbo
go
Grant Select on dbo.PHA to observers Granted by dbo
go
Grant Select on dbo.STA to observers Granted by dbo
go
Grant Select on dbo.SAOPHA to observers Granted by dbo
go
Grant Execute on dbo.checkut to observers Granted by dbo
go
Grant Execute on dbo.gettrx to observers Granted by dbo
go
Grant Select on dbo.SCA to observers Granted by dbo
go
Grant Select on dbo.SCU to observers Granted by dbo
go
Grant Select on dbo.SES to observers Granted by dbo
go
Grant Select on dbo.SOU to visitors Granted by dbo
go
Grant Select on dbo.SPH to visitors Granted by dbo
go
Grant Execute on dbo.hex2decim to visitors Granted by dbo
go
Grant Execute on dbo.ra2rad to visitors Granted by dbo
go
Grant Execute on dbo.dec2rad to visitors Granted by dbo
go
Grant Execute on dbo.lst_elev to visitors Granted by dbo
go
Grant Select on dbo.SUB to visitors Granted by dbo
go
Grant Execute on dbo.lst_rise to visitors Granted by dbo
go
Grant Execute on dbo.lst_set to visitors Granted by dbo
go
Grant Select on dbo.TAU to visitors Granted by dbo
go
Grant Select on dbo.TEL to visitors Granted by dbo
go
Grant Select on dbo.WEA to visitors Granted by dbo
go
Grant Select on dbo.CSONIGHT to visitors Granted by dbo
go
Grant Select on dbo.CSOTAU to visitors Granted by dbo
go
Grant Select on dbo.CRYO to visitors Granted by dbo
go
Grant Select on dbo.FLUX to visitors Granted by dbo
go
Grant Select on dbo.MOTOR to visitors Granted by dbo
go
Grant Select on dbo.scan to visitors Granted by dbo
go
Grant Select on dbo.NOI to visitors Granted by dbo
go
Grant Select on dbo.PHA to visitors Granted by dbo
go
Grant Select on dbo.STA to visitors Granted by dbo
go
Grant Insert on dbo.STA to visitors Granted by dbo
go
Grant Select on dbo.SAOPHA to visitors Granted by dbo
go
Grant Execute on dbo.gettrx to visitors Granted by dbo
go
Grant Select on dbo.SCA to visitors Granted by dbo
go
Grant Select on dbo.SCU to visitors Granted by dbo
go
Grant Select on dbo.SES to visitors Granted by dbo
go
Grant Execute on dbo.findobj to staff Granted by dbo
go
exec sp_addalias 'omp_maint', 'dbo'
go 



-- DDLGen Completed
-- at 03/08/16 1:54:14 HST