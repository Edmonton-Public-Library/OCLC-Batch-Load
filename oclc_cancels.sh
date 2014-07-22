#!/usr/bin/bash

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

$OCLC_DIR/oclc.pl -w

if ls DATA* LABEL* 2>/dev/null
then
	echo "$OCLC_DIR/oclc.pl -w cleaned label and data files." >> $SUMMARY_LOG
else
	echo "$OCLC_DIR/oclc.pl -w failed to remove data and label files." >> $SUMMARY_LOG
	echo "$OCLC_DIR/oclc.pl -w failed to remove data and label files." | mailx -s "OCLC Mixed Upload fail" "anisbet@epl.ca"
	exit 1
fi
# create list of Cancels for the last month
MSG="["`date`"] started cancel list"
echo $MSG >> $SUMMARY_LOG
echo      >> $SUMMARY_LOG
$OCLC_DIR/oclc.pl -D

# ftp the lists to OCLC
MSG="["`date`"] ftp'ed files to OCLC"
echo $MSG >> $SUMMARY_LOG
echo      >> $SUMMARY_LOG
$OCLC_DIR/oclc.pl -f

MSG="["`date`"] generated summary"
echo $MSG >> $SUMMARY_LOG
echo      >> $SUMMARY_LOG

# report what you did
cat $SUMMARY_LOG | mailx -s "OCLC Cancels Upload" "anisbet@epl.ca"
