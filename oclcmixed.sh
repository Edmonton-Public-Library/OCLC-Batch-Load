#!/usr/bin/bash
####################################################
#
# Bash script source file for project discarddbloader 
# Purpose: Coordinate OCLC Mixed and Cancel uploads.
# Copyright (C) 2014  Andrew Nisbet
# Method:  Run API against Exception files, and create a comprehensive file.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# Note: This script uses SSH to execute some commands so SSH keys must
# installed.
#
# Author:  Andrew Nisbet, Edmonton Public Library
# Created: Fri Jan 25 09:00:08 MST 2013
# Rev: 
#            
#          0.1 - Copied from oclc.sh to oclcmixed.sh. 
#
####################################################

CRON_DIR=/s/sirsi/Unicorn/EPLwork/cronjobscripts
OCLC_DIR=$CRON_DIR/OCLC
source $CRON_DIR/setscriptenvironment.sh
export PIPE=/s/sirsi/Unicorn/Bincustom/pipe.pl
# this file deliberately not called .log because oclc.pl -w deletes those.
SUMMARY_LOG=$OCLC_DIR/summary.txt
cd $OCLC_DIR
# clean up from the last run
MSG="["`date`"] started OCLC directory cleaned up"
echo $MSG > $SUMMARY_LOG
echo      >> $SUMMARY_LOG
# Clean the old submissions from the working directory.
$OCLC_DIR/oclc.pl -w

MSG="["`date`"] started mixed (project #012569) list"
echo $MSG >> $SUMMARY_LOG
echo      >> $SUMMARY_LOG
$OCLC_DIR/oclc.pl -A
cat `ls -tc1 LABEL.* | $PIPE -L+1` | $PIPE -L2 >> $SUMMARY_LOG
# ftp the lists to OCLC
MSG="["`date`"] ftp'ed files to OCLC"
echo $MSG >> $SUMMARY_LOG
echo      >> $SUMMARY_LOG
$OCLC_DIR/oclc.pl -f

MSG="["`date`"] generated summary"
echo $MSG >> $SUMMARY_LOG
echo      >> $SUMMARY_LOG

# report what you did
cat $SUMMARY_LOG | mailx -s "OCLC mixed upload complete." "ilsadmins@epl.ca"
