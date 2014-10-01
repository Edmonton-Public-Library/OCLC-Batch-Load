#!/bin/bash
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
# Updates the FTP password at OCLC.
#
export HOME=/home/ilsdev
export LOGNAME=ilsdev
export PATH=$PATH:/usr/bin:/bin:/home/ilsdev/projects/oclc/javaftp
export SHELL=/bin/sh
export PWD=/home/ilsdev
USER=sirsi
EMAILS="ilsadmins@epl.ca"
SERVER=eplapp.library.ualberta.ca
LOCAL_DIR=/home/ilsdev/projects/oclc/javaftp
REMOTE_DIR=/s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC
PASSWORD_FILE=password.txt
cd $LOCAL_DIR
scp $USER@$SERVER:$REMOTE_DIR/$PASSWORD_FILE $LOCAL_DIR
if [ "$?" -ne 0 ]
then
	echo "error retrieving OCLC password file from production server." | /usr/bin/mailx -s "OCLC Password change Error `date`" $EMAILS
	exit -1
fi
/usr/bin/java -cp /home/ilsdev/projects/oclc/javaftp/dist/JavaFTP.jar epl.ftp.FtpPassword
if [ ! -s "$LOCAL_DIR/$PASSWORD_FILE" ]
then
	echo "error changing password file on ILSDEV1 `pwd`." | /usr/bin/mailx -s "OCLC Password change Error `date`" $EMAILS
	exit -1
else
	scp $LOCAL_DIR/$PASSWORD_FILE $USER@$SERVER:$REMOTE_DIR
	if [ "$?" -ne 0 ]
	then
		echo "error returning OCLC password file to production server." | /usr/bin/mailx -s "OCLC Password change Error `date`" $EMAILS
		exit -1
	fi
	echo "OCLC password changed to '`cat $LOCAL_DIR/$PASSWORD_FILE`' on `date`.\nThis is informational only, no action is required." | /usr/bin/mailx -s "OCLC Password change" $EMAILS
fi
# EOF
