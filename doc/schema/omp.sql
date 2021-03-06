CREATE TABLE `ompaffiliationalloc` (
  `telescope` varchar(32) NOT NULL,
  `semester` varchar(32) NOT NULL,
  `affiliation` varchar(32) NOT NULL,
  `allocation` double NOT NULL,
  `observed` double NOT NULL DEFAULT 0,
  PRIMARY KEY (`telescope`,`semester`,`affiliation`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompauth` (
  `userid` varchar(32) NOT NULL,
  `token` varchar(32) NOT NULL,
  `expiry` datetime NOT NULL,
  `addr` varchar(64) DEFAULT NULL,
  `agent` varchar(255) DEFAULT NULL,
  `is_staff` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`token`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompfault` (
  `faultid` double NOT NULL,
  `category` varchar(32) NOT NULL,
  `subject` varchar(128) DEFAULT NULL,
  `faultdate` datetime DEFAULT NULL,
  `type` int(11) NOT NULL,
  `fsystem` int(11) NOT NULL,
  `status` int(11) NOT NULL,
  `urgency` int(11) NOT NULL,
  `timelost` double NOT NULL,
  `entity` varchar(64) DEFAULT NULL,
  `condition` int(11) DEFAULT NULL,
  `location` int(11) DEFAULT NULL,
  `shifttype` varchar(70) DEFAULT NULL,
  `remote` varchar(70) DEFAULT NULL,
  PRIMARY KEY (`faultid`),
  FULLTEXT KEY `idx_ompfault_subject` (`subject`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompfaultassoc` (
  `associd` bigint(20) NOT NULL AUTO_INCREMENT,
  `faultid` double NOT NULL,
  `projectid` varchar(32) NOT NULL,
  PRIMARY KEY (`associd`),
  KEY `idx_faultid` (`faultid`),
  KEY `idx_projectid` (`projectid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompfaultbody` (
  `respid` bigint(20) NOT NULL AUTO_INCREMENT,
  `faultid` double NOT NULL,
  `date` datetime NOT NULL,
  `author` varchar(32) NOT NULL,
  `isfault` int(11) NOT NULL,
  `text` longtext NOT NULL,
  PRIMARY KEY (`respid`),
  KEY `idx_ompfaultbody_1` (`faultid`),
  FULLTEXT KEY `idx_ompfaultbody_text` (`text`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompfeedback` (
  `commid` bigint(20) NOT NULL AUTO_INCREMENT,
  `projectid` varchar(32) NOT NULL,
  `author` varchar(32) DEFAULT NULL,
  `date` datetime NOT NULL,
  `subject` varchar(128) DEFAULT NULL,
  `program` varchar(50) NOT NULL,
  `sourceinfo` varchar(60) NOT NULL,
  `status` int(11) DEFAULT NULL,
  `text` longtext NOT NULL,
  `msgtype` int(11) DEFAULT NULL,
  `entrynum` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`commid`),
  KEY `feedback_idx` (`projectid`),
  KEY `idx_date` (`date`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompkey` (
  `keystring` varchar(64) NOT NULL,
  `expiry` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompmsb` (
  `msbid` bigint(20) NOT NULL AUTO_INCREMENT,
  `projectid` varchar(32) NOT NULL,
  `remaining` int(11) NOT NULL,
  `checksum` varchar(64) NOT NULL,
  `obscount` int(11) NOT NULL,
  `taumin` double NOT NULL,
  `taumax` double NOT NULL,
  `seeingmin` double NOT NULL,
  `seeingmax` double NOT NULL,
  `priority` int(11) NOT NULL,
  `telescope` varchar(16) NOT NULL,
  `moonmax` int(11) NOT NULL,
  `cloudmax` int(11) NOT NULL,
  `timeest` double NOT NULL,
  `title` varchar(255) DEFAULT NULL,
  `datemin` datetime NOT NULL,
  `datemax` datetime NOT NULL,
  `minel` double DEFAULT NULL,
  `maxel` double DEFAULT NULL,
  `approach` int(11) DEFAULT NULL,
  `moonmin` int(11) NOT NULL,
  `cloudmin` int(11) NOT NULL,
  `skymin` double NOT NULL,
  `skymax` double NOT NULL,
  PRIMARY KEY (`msbid`),
  UNIQUE KEY `idx_msbid` (`msbid`),
  KEY `idx_cloudmax` (`cloudmax`),
  KEY `idx_cloudmin` (`cloudmin`),
  KEY `idx_datemax` (`datemax`),
  KEY `idx_datemin` (`datemin`),
  KEY `idx_moonmax` (`moonmax`),
  KEY `idx_moonmin` (`moonmin`),
  KEY `idx_obscount` (`obscount`),
  KEY `idx_projectid` (`projectid`),
  KEY `idx_remaining` (`remaining`),
  KEY `idx_seeingmax` (`seeingmax`),
  KEY `idx_seeingmin` (`seeingmin`),
  KEY `idx_skymax` (`skymax`),
  KEY `idx_skymin` (`skymin`),
  KEY `idx_taumax` (`taumax`),
  KEY `idx_taumin` (`taumin`),
  KEY `idx_telescope` (`telescope`),
  KEY `idx_timeest` (`timeest`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompmsbdone` (
  `commid` bigint(20) NOT NULL AUTO_INCREMENT,
  `checksum` varchar(64) NOT NULL,
  `status` int(11) NOT NULL,
  `projectid` varchar(32) NOT NULL,
  `date` datetime NOT NULL,
  `target` varchar(64) NOT NULL,
  `instrument` varchar(64) NOT NULL,
  `waveband` varchar(64) NOT NULL,
  `comment` longtext NOT NULL,
  `title` varchar(255) DEFAULT NULL,
  `userid` varchar(32) DEFAULT NULL,
  `msbtid` varchar(32) DEFAULT NULL,
  PRIMARY KEY (`commid`),
  KEY `msbdone_idx` (`projectid`),
  KEY `msbtid_idx` (`msbtid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompobs` (
  `msbid` int(11) NOT NULL,
  `projectid` varchar(32) NOT NULL,
  `instrument` varchar(32) NOT NULL,
  `type` varchar(32) NOT NULL,
  `pol` tinyint(4) NOT NULL,
  `wavelength` double NOT NULL,
  `disperser` varchar(32) DEFAULT NULL,
  `coordstype` varchar(32) NOT NULL,
  `target` varchar(32) NOT NULL,
  `ra2000` double DEFAULT NULL,
  `dec2000` double DEFAULT NULL,
  `el1` double DEFAULT NULL,
  `el2` double DEFAULT NULL,
  `el3` double DEFAULT NULL,
  `el4` double DEFAULT NULL,
  `el5` double DEFAULT NULL,
  `el6` double DEFAULT NULL,
  `el7` double DEFAULT NULL,
  `el8` double DEFAULT NULL,
  `timeest` double NOT NULL,
  `obsid` bigint(20) NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`obsid`),
  KEY `idx_instument` (`instrument`),
  KEY `idx_msbid` (`msbid`),
  KEY `idx_projectid` (`projectid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompobslog` (
  `obslogid` bigint(20) NOT NULL AUTO_INCREMENT,
  `runnr` int(11) NOT NULL,
  `instrument` varchar(32) NOT NULL,
  `telescope` varchar(32) DEFAULT NULL,
  `date` datetime NOT NULL,
  `obsactive` int(11) NOT NULL,
  `commentdate` datetime NOT NULL,
  `commentauthor` varchar(32) NOT NULL,
  `commenttext` longtext DEFAULT NULL,
  `commentstatus` int(11) NOT NULL,
  `obsid` varchar(48) DEFAULT NULL,
  PRIMARY KEY (`obslogid`),
  KEY `idx_obsid` (`obsid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompproj` (
  `projectid` varchar(32) NOT NULL,
  `pi` varchar(32) NOT NULL,
  `title` varchar(255) DEFAULT NULL,
  `semester` varchar(10) NOT NULL,
  `allocated` double NOT NULL,
  `remaining` double NOT NULL,
  `pending` double NOT NULL,
  `telescope` varchar(16) NOT NULL,
  `taumin` double NOT NULL,
  `taumax` double NOT NULL,
  `seeingmin` double NOT NULL,
  `seeingmax` double NOT NULL,
  `cloudmax` int(11) NOT NULL,
  `state` tinyint(4) NOT NULL,
  `cloudmin` int(11) NOT NULL,
  `skymin` double NOT NULL,
  `skymax` double NOT NULL,
  `expirydate` datetime DEFAULT NULL,
  PRIMARY KEY (`projectid`),
  KEY `idx_allocated` (`allocated`),
  KEY `idx_pending` (`pending`),
  KEY `idx_remaining` (`remaining`),
  KEY `idx_semester` (`semester`),
  KEY `idx_telescope` (`telescope`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompprojaffiliation` (
  `projectid` varchar(32) NOT NULL,
  `affiliation` varchar(32) NOT NULL,
  `fraction` double NOT NULL,
  PRIMARY KEY (`projectid`,`affiliation`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompprojqueue` (
  `uniqid` bigint(20) NOT NULL AUTO_INCREMENT,
  `projectid` varchar(32) NOT NULL,
  `country` varchar(32) NOT NULL,
  `tagpriority` int(11) NOT NULL,
  `isprimary` tinyint(4) NOT NULL,
  `tagadj` int(11) NOT NULL,
  PRIMARY KEY (`uniqid`),
  KEY `idx_country` (`country`),
  KEY `idx_projectid` (`projectid`),
  KEY `idx_tagadj` (`tagadj`),
  KEY `idx_tagpriority` (`tagpriority`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompprojuser` (
  `uniqid` bigint(20) NOT NULL AUTO_INCREMENT,
  `projectid` varchar(32) NOT NULL,
  `userid` varchar(32) NOT NULL,
  `capacity` varchar(16) NOT NULL,
  `contactable` tinyint(4) NOT NULL,
  `capacity_order` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `affiliation` varchar(32) DEFAULT NULL,
  `omp_access` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`uniqid`),
  UNIQUE KEY `idx_ompprojuser_2` (`projectid`,`userid`,`capacity`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompsciprog` (
  `projectid` varchar(32) NOT NULL,
  `timestamp` int(11) NOT NULL,
  `sciprog` longtext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompshiftlog` (
  `shiftid` bigint(20) NOT NULL AUTO_INCREMENT,
  `date` datetime NOT NULL,
  `author` varchar(32) NOT NULL,
  `telescope` varchar(32) NOT NULL,
  `text` longtext NOT NULL,
  PRIMARY KEY (`shiftid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `omptimeacct` (
  `date` datetime NOT NULL,
  `projectid` varchar(32) NOT NULL,
  `timespent` int(11) NOT NULL,
  `confirmed` tinyint(4) NOT NULL,
  `shifttype` varchar(70) NOT NULL DEFAULT '',
  `comment` text DEFAULT NULL,
  PRIMARY KEY (`date`,`projectid`,`shifttype`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `omptle` (
  `target` varchar(32) NOT NULL,
  `el1` double NOT NULL,
  `el2` double NOT NULL,
  `el3` double NOT NULL,
  `el4` double NOT NULL,
  `el5` double NOT NULL,
  `el6` double NOT NULL,
  `el7` double NOT NULL,
  `el8` double NOT NULL,
  `retrieved` datetime NOT NULL,
  UNIQUE KEY `tle_idx` (`target`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `ompuser` (
  `userid` varchar(32) NOT NULL,
  `uname` varchar(255) NOT NULL,
  `email` varchar(64) DEFAULT NULL,
  `alias` varchar(32) DEFAULT NULL,
  `cadcuser` varchar(20) DEFAULT NULL,
  `obfuscated` tinyint(4) NOT NULL DEFAULT 0,
  `no_fault_cc` tinyint(4) NOT NULL DEFAULT 0,
  `staff_access` tinyint(4) NOT NULL DEFAULT 0,
  PRIMARY KEY (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
