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
#          0.2 - Changed email recipients to ilsadmins. 
#          0.1 - Dev. 
#
####################################################

CRON_DIR=/s/sirsi/Unicorn/EPLwork/cronjobscripts
OCLC_DIR=$CRON_DIR/OCLC
source $CRON_DIR/setscriptenvironment.sh
# this file deliberately not called .log because oclc.pl -w deletes those.
SUMMARY_LOG=$OCLC_DIR/summary.txt
cd $OCLC_DIR
# clean up from the last run
MSG="["`date`"] started OCLC directory cleaned up"
echo $MSG > $SUMMARY_LOG
echo      >> $SUMMARY_LOG
if [ $# -ne 1 ]
then
	echo "**error: Invalid number of arguments on command line." >> $SUMMARY_LOG
	echo "   Usage: $0 ['cancel'|'mixed']"
	exit 4
fi

$OCLC_DIR/oclc.pl -w

# If we can ls files here something went wrong.
if ls DATA* LABEL* 2>/dev/null
then
	echo "$OCLC_DIR/oclc.pl -w failed to remove data and label files." >> $SUMMARY_LOG
	echo "$OCLC_DIR/oclc.pl -w failed to remove data and label files." | mailx -s "OCLC Mixed Upload fail" "ilsadmins@epl.ca"
	exit 1
else
	echo "$OCLC_DIR/oclc.pl -w cleaned label and data files." >> $SUMMARY_LOG
fi
# create list of Cancels for the last month
MSG="["`date`"] started cancel list"
echo $MSG >> $SUMMARY_LOG
echo      >> $SUMMARY_LOG
if [ $1 == "cancel" ]
then
	$OCLC_DIR/oclc.pl -D
elif [ $1 == "mixed" ]
then
	$OCLC_DIR/oclc.pl -A
else
	echo "**error: Invalid argument on command line." >> $SUMMARY_LOG
	echo "   Usage: $0 ['cancel'|'mixed']"
	exit 4
fi

# ftp the lists to OCLC
MSG="["`date`"] ftp'ed files to OCLC"
echo $MSG >> $SUMMARY_LOG
echo      >> $SUMMARY_LOG
$OCLC_DIR/oclc.pl -f

MSG="["`date`"] generated summary"
echo $MSG >> $SUMMARY_LOG
echo      >> $SUMMARY_LOG

# report what you did
cat $SUMMARY_LOG | mailx -s "OCLC Cancels Upload" "ilsadmins@epl.ca"
