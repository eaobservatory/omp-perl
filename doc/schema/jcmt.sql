CREATE TABLE `ACSIS` (
  `obsid_subsysnr` varchar(50) NOT NULL,
  `obsid` varchar(48) NOT NULL,
  `max_subscan` int(11) NOT NULL,
  `obsend` int(11) DEFAULT NULL,
  `molecule` varchar(70) DEFAULT NULL,
  `transiti` varchar(70) DEFAULT NULL,
  `tempscal` varchar(70) DEFAULT NULL,
  `drrecipe` varchar(70) DEFAULT NULL,
  `bwmode` varchar(70) DEFAULT NULL,
  `subsysnr` int(11) DEFAULT NULL,
  `subbands` varchar(70) DEFAULT NULL,
  `nsubband` int(11) DEFAULT NULL,
  `subrefp1` int(11) DEFAULT NULL,
  `subrefp2` int(11) DEFAULT NULL,
  `nchnsubs` int(11) DEFAULT NULL,
  `refchan` int(11) DEFAULT NULL,
  `ifchansp` double DEFAULT NULL,
  `fft_win` varchar(70) DEFAULT NULL,
  `bedegfac` double DEFAULT NULL,
  `msroot` varchar(70) DEFAULT NULL,
  `sb_mode` varchar(70) DEFAULT NULL,
  `iffreq` double DEFAULT NULL,
  `n_mix` int(11) DEFAULT NULL,
  `obs_sb` varchar(70) DEFAULT NULL,
  `lofreqs` double DEFAULT NULL,
  `lofreqe` double DEFAULT NULL,
  `recptors` varchar(70) DEFAULT NULL,
  `refrecep` varchar(70) DEFAULT NULL,
  `medtsys` double DEFAULT NULL,
  `doppler` varchar(70) DEFAULT NULL,
  `ssysobs` varchar(16) DEFAULT NULL,
  `skyrefx` varchar(70) DEFAULT NULL,
  `skyrefy` varchar(70) DEFAULT NULL,
  `num_nods` int(11) DEFAULT NULL,
  `ncalstep` int(11) DEFAULT NULL,
  `nrefstep` int(11) DEFAULT NULL,
  `stbetref` int(11) DEFAULT NULL,
  `stbetcal` int(11) DEFAULT NULL,
  `freq_sig_lower` double DEFAULT NULL,
  `freq_sig_upper` double DEFAULT NULL,
  `freq_img_lower` double DEFAULT NULL,
  `freq_img_upper` double DEFAULT NULL,
  `zsource` double DEFAULT NULL,
  `restfreq` double DEFAULT NULL,
  `nchannels` int(11) DEFAULT NULL,
  `ssyssrc` varchar(16) DEFAULT NULL,
  `medtrx` double DEFAULT NULL,
  `specid` tinyint(4) DEFAULT NULL,
  `asn_id` varchar(32) DEFAULT NULL,
  `track_sb` varchar(70) DEFAULT NULL,
  `rot_pa` double DEFAULT NULL,
  `rot_crd` varchar(70) DEFAULT NULL,
  `rot_iast` double DEFAULT NULL,
  `rot_iaen` double DEFAULT NULL,
  PRIMARY KEY (`obsid_subsysnr`),
  KEY `idx_ACSIS_3` (`obsid`,`subsysnr`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `COMMON` (
  `obsid` varchar(48) NOT NULL,
  `telescop` varchar(6) DEFAULT NULL,
  `origin` varchar(60) DEFAULT NULL,
  `obsgeo_x` double DEFAULT NULL,
  `obsgeo_y` double DEFAULT NULL,
  `obsgeo_z` double DEFAULT NULL,
  `alt_obs` double DEFAULT NULL,
  `lat_obs` double DEFAULT NULL,
  `long_obs` double DEFAULT NULL,
  `etal` double DEFAULT NULL,
  `project` varchar(32) DEFAULT NULL,
  `recipe` varchar(70) DEFAULT NULL,
  `drgroup` int(11) DEFAULT NULL,
  `msbid` varchar(40) NOT NULL,
  `survey` varchar(10) DEFAULT NULL,
  `rmtagent` varchar(10) DEFAULT NULL,
  `agentid` varchar(70) DEFAULT NULL,
  `object` varchar(70) DEFAULT NULL,
  `standard` int(11) DEFAULT NULL,
  `obsnum` int(11) DEFAULT NULL,
  `utdate` int(11) DEFAULT NULL,
  `date_obs` datetime(3) NOT NULL,
  `date_end` datetime(3) NOT NULL,
  `instap` varchar(8) DEFAULT NULL,
  `instap_x` double DEFAULT NULL,
  `instap_y` double DEFAULT NULL,
  `amstart` double DEFAULT NULL,
  `amend` double DEFAULT NULL,
  `azstart` double DEFAULT NULL,
  `azend` double DEFAULT NULL,
  `elstart` double DEFAULT NULL,
  `elend` double DEFAULT NULL,
  `hststart` datetime(3) DEFAULT NULL,
  `hstend` datetime(3) DEFAULT NULL,
  `lststart` double DEFAULT NULL,
  `lstend` double DEFAULT NULL,
  `int_time` double DEFAULT NULL,
  `atstart` double DEFAULT NULL,
  `atend` double DEFAULT NULL,
  `humstart` double DEFAULT NULL,
  `humend` double DEFAULT NULL,
  `bpstart` double DEFAULT NULL,
  `bpend` double DEFAULT NULL,
  `wndspdst` double DEFAULT NULL,
  `wndspden` double DEFAULT NULL,
  `wnddirst` double DEFAULT NULL,
  `wnddiren` double DEFAULT NULL,
  `tau225st` double DEFAULT NULL,
  `tau225en` double DEFAULT NULL,
  `taudatst` datetime DEFAULT NULL,
  `taudaten` datetime DEFAULT NULL,
  `tausrc` varchar(16) DEFAULT NULL,
  `wvmtaust` double DEFAULT NULL,
  `wvmtauen` double DEFAULT NULL,
  `wvmdatst` datetime DEFAULT NULL,
  `wvmdaten` datetime DEFAULT NULL,
  `seeingst` double DEFAULT NULL,
  `seeingen` double DEFAULT NULL,
  `seedatst` datetime DEFAULT NULL,
  `seedaten` datetime DEFAULT NULL,
  `frlegtst` double DEFAULT NULL,
  `frlegten` double DEFAULT NULL,
  `bklegtst` double DEFAULT NULL,
  `bklegten` double DEFAULT NULL,
  `sam_mode` varchar(8) DEFAULT NULL,
  `sw_mode` varchar(8) DEFAULT NULL,
  `obs_type` varchar(10) DEFAULT NULL,
  `chop_crd` varchar(12) DEFAULT NULL,
  `chop_frq` double DEFAULT NULL,
  `chop_pa` double DEFAULT NULL,
  `chop_thr` double DEFAULT NULL,
  `jigl_cnt` int(11) DEFAULT NULL,
  `jigl_nam` varchar(70) DEFAULT NULL,
  `jig_pa` double DEFAULT NULL,
  `jig_crd` varchar(12) DEFAULT NULL,
  `map_hght` double DEFAULT NULL,
  `map_pa` double DEFAULT NULL,
  `map_wdth` double DEFAULT NULL,
  `locl_crd` varchar(12) DEFAULT NULL,
  `map_x` double DEFAULT NULL,
  `map_y` double DEFAULT NULL,
  `scan_crd` varchar(12) DEFAULT NULL,
  `scan_vel` double DEFAULT NULL,
  `scan_dy` double DEFAULT NULL,
  `scan_pa` double DEFAULT NULL,
  `scan_pat` varchar(28) DEFAULT NULL,
  `align_dx` double DEFAULT NULL,
  `align_dy` double DEFAULT NULL,
  `focus_dz` double DEFAULT NULL,
  `daz` double DEFAULT NULL,
  `del` double DEFAULT NULL,
  `uaz` double DEFAULT NULL,
  `uel` double DEFAULT NULL,
  `steptime` double DEFAULT NULL,
  `num_cyc` int(11) DEFAULT NULL,
  `jos_mult` int(11) DEFAULT NULL,
  `jos_min` int(11) DEFAULT NULL,
  `startidx` int(11) DEFAULT NULL,
  `focaxis` char(1) DEFAULT NULL,
  `nfocstep` int(11) DEFAULT NULL,
  `focstep` double DEFAULT NULL,
  `ocscfg` varchar(70) DEFAULT NULL,
  `status` varchar(8) DEFAULT NULL,
  `pol_conn` int(11) DEFAULT NULL,
  `pol_mode` varchar(9) DEFAULT NULL,
  `rotafreq` double DEFAULT NULL,
  `instrume` varchar(8) DEFAULT NULL,
  `backend` varchar(8) DEFAULT NULL,
  `release_date` datetime DEFAULT NULL,
  `last_modified` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `obsra` double DEFAULT NULL,
  `obsdec` double DEFAULT NULL,
  `obsratl` double DEFAULT NULL,
  `obsrabl` double DEFAULT NULL,
  `obsratr` double DEFAULT NULL,
  `obsrabr` double DEFAULT NULL,
  `obsdectl` double DEFAULT NULL,
  `obsdecbl` double DEFAULT NULL,
  `obsdectr` double DEFAULT NULL,
  `obsdecbr` double DEFAULT NULL,
  `dut1` double DEFAULT NULL,
  `msbtid` varchar(32) DEFAULT NULL,
  `jig_scal` double DEFAULT NULL,
  `inbeam` varchar(64) DEFAULT NULL,
  `inbeam_orig` varchar(64) DEFAULT NULL,
  `moving_target` tinyint(1) DEFAULT NULL,
  `last_caom_mod` datetime DEFAULT NULL,
  `req_mintau` double DEFAULT NULL,
  `req_maxtau` double DEFAULT NULL,
  `msbtitle` varchar(70) DEFAULT NULL,
  `oper_loc` varchar(70) DEFAULT NULL,
  `oper_sft` varchar(70) DEFAULT NULL,
  `doorstst` varchar(70) DEFAULT NULL,
  `doorsten` varchar(70) DEFAULT NULL,
  `roofstst` varchar(70) DEFAULT NULL,
  `roofsten` varchar(70) DEFAULT NULL,
  `grid_cnt` int(11) DEFAULT NULL,
  PRIMARY KEY (`obsid`),
  KEY `idx_jcmt_COMMON_proj` (`project`),
  KEY `idx_jcmt_COMMON_inst` (`instrume`),
  KEY `caom_mod_idx` (`last_caom_mod`),
  KEY `idx_jcmt_COMMON_date_end` (`date_end`),
  KEY `idx_jcmt_COMMON_date_obs` (`date_obs`),
  KEY `idx_utdate` (`utdate`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `FILES` (
  `file_id` varchar(70) NOT NULL,
  `obsid` varchar(48) NOT NULL,
  `subsysnr` int(11) NOT NULL,
  `nsubscan` int(11) NOT NULL,
  `obsid_subsysnr` varchar(50) NOT NULL,
  `md5sum` varchar(40) DEFAULT NULL,
  `filesize` int(11) DEFAULT NULL,
  PRIMARY KEY (`file_id`),
  KEY `obsid_idx` (`obsid`),
  KEY `obsidss_idx` (`obsid_subsysnr`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `RXH3` (
  `obsid_subsysnr` varchar(50) NOT NULL,
  `obsid` varchar(48) NOT NULL,
  `xleft` double DEFAULT NULL,
  `xright` double DEFAULT NULL,
  `ybottom` double DEFAULT NULL,
  `ytop` double DEFAULT NULL,
  `nfreq` int(11) DEFAULT NULL,
  `fperiod` double DEFAULT NULL,
  `c4x` double DEFAULT NULL,
  `c4y` double DEFAULT NULL,
  `c4z` double DEFAULT NULL,
  `tmux` double DEFAULT NULL,
  `tmuy` double DEFAULT NULL,
  `rxh3_x` double DEFAULT NULL,
  `rxh3_y` double DEFAULT NULL,
  `rowlen` double DEFAULT NULL,
  `rowvel` double DEFAULT NULL,
  `rowspcng` double DEFAULT NULL,
  `nsxfreqs` int(11) DEFAULT NULL,
  `nrows` int(11) DEFAULT NULL,
  `reverse` int(11) DEFAULT NULL,
  `freqband` double DEFAULT NULL,
  `sxperiod` double DEFAULT NULL,
  `freerun` int(11) DEFAULT NULL,
  `ncalrows` int(11) DEFAULT NULL,
  `ncalpnts` int(11) DEFAULT NULL,
  `horzmap` int(11) DEFAULT NULL,
  `smuzpos` double DEFAULT NULL,
  `sxtrggrd` int(11) DEFAULT NULL,
  `freqfile` varchar(255) DEFAULT NULL,
  `ovrsmple` int(11) DEFAULT NULL,
  `calpos_x` double DEFAULT NULL,
  `calpos_y` double DEFAULT NULL,
  PRIMARY KEY (`obsid_subsysnr`),
  KEY `obsid_idx` (`obsid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `SCUBA2` (
  `obsid_subsysnr` varchar(50) NOT NULL,
  `filter` varchar(10) NOT NULL,
  `subarray_a` tinyint(1) DEFAULT 0,
  `subarray_b` tinyint(1) DEFAULT 0,
  `subarray_c` tinyint(1) DEFAULT 0,
  `subarray_d` tinyint(1) DEFAULT 0,
  `arrayid_a` varchar(32) DEFAULT NULL,
  `arrayid_b` varchar(32) DEFAULT NULL,
  `arrayid_c` varchar(32) DEFAULT NULL,
  `arrayid_d` varchar(32) DEFAULT NULL,
  `max_subscan` int(11) NOT NULL,
  `wavelen` double NOT NULL,
  `shutter` double NOT NULL,
  `bandwid` double NOT NULL,
  `bbheat` double NOT NULL,
  `basetemp` double DEFAULT NULL,
  `pixheat_a` int(11) DEFAULT NULL,
  `pixheat_b` int(11) DEFAULT NULL,
  `pixheat_c` int(11) DEFAULT NULL,
  `pixheat_d` int(11) DEFAULT NULL,
  `bias_a` int(11) DEFAULT NULL,
  `bias_b` int(11) DEFAULT NULL,
  `bias_c` int(11) DEFAULT NULL,
  `bias_d` int(11) DEFAULT NULL,
  `flat_a` varchar(32) DEFAULT NULL,
  `flat_b` varchar(32) DEFAULT NULL,
  `flat_c` varchar(32) DEFAULT NULL,
  `flat_d` varchar(32) DEFAULT NULL,
  `obsid` varchar(48) NOT NULL DEFAULT '',
  `asn_id` varchar(6) DEFAULT NULL,
  PRIMARY KEY (`obsid_subsysnr`),
  KEY `filter_idx` (`filter`),
  KEY `obsid_idx` (`obsid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `keep_in_hilo` (
  `project` varchar(32) NOT NULL,
  `comment` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`project`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `keep_in_hilo_obs` (
  `obsid` varchar(48) NOT NULL,
  `project` varchar(32) NOT NULL,
  PRIMARY KEY (`obsid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
CREATE TABLE `transfer` (
  `file_id` varchar(70) NOT NULL,
  `status` char(1) DEFAULT NULL,
  `created` datetime NOT NULL DEFAULT current_timestamp(),
  `modified` datetime DEFAULT NULL ON UPDATE current_timestamp(),
  `location` varchar(200) DEFAULT NULL,
  `error` tinyint(1) DEFAULT 0,
  `comment` varchar(250) DEFAULT NULL,
  `keep_jac` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`file_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
