#!/usr/bin/perl -w
########################################################################
# Purpose: Upload bibliographic records from EPL to OCLC.
# Method:  EPL's catalog MARC records are uploaded monthly to OCLC for 
#          the purposes of searching and other InterLibrary Loans (ILL).
# Upload bibliographic records from EPL to OCLC.
#    Copyright (C) 2013, 2014  Andrew Nisbet
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
# Author:  Andrew Nisbet, Edmonton Public Library
#
# Steps (each explained later) for uploading Adds and Changes (MIXED) project:
# 1) oclc.pl -a [-d"start,end"]
# 2) oclc.pl -s $defaultCatKeysFile
# 3) oclc.pl -c
# 4) oclc.pl -f
#
# Steps (also explained later) for uploading deletes (CANCELS) project:
# 1) oclc.pl -D [-d"start,end"]
# 2) oclc.pl -f
#
# Author:  Andrew Nisbet
# Date:    June 4, 2012
# Rev:     
#          0.6 - Updated comments, removed trailing module '1' EOF marker. 
#          0.5 - '-w' also cleans up last months submission. 
#          0.4 - Code modified to account for absolute pathing of files and -r changed to -M. 
#          0.3 - ENV vars added for cron. 
#          0.2 - Includes new features such as a clean up switch, and 
#                OCLC number update.
#          0.1 - Beta includes deletes (CANCELS).
#          0.0 - develop
########################################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;
use File::Basename;  # Used in ftp() for local and remote file identification.
use POSIX;           # for ceil()


my $VERSION = 0.6;
# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
$ENV{'PATH'} = ":/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/s/sirsi/Unicorn/Search/Bin:/usr/bin";
$ENV{'UPATH'} = "/s/sirsi/Unicorn/Config/upath";
###############################################
##### function must be first because logging uses it almost immediately.
# Returns a timestamp for the log file only. The Database uses the default
# time of writing the record for its timestamp in SQL. That was done to avoid
# the snarl of differences between MySQL and Perl timestamp details.
# Param:  isLogDate integer 0 = yyyymmdd, 1 = yymmdd, and passing nothing returns [yyyy-mm-dd hh:mm:ss].
# Return: string of the current date and time as: '[yyyy-mm-dd hh:mm:ss]' or 'yyyymmdd'.
sub getTimeStamp
{
	my $isLogDate = $_[0];
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	$year += 1900;
	$mon  += 1;
	if ($min < 10)
	{
		$min = "0$min";
	}
	if ($sec < 10)
	{
		$sec = "0$sec";
	}
	if ($mday < 10)
	{
		$mday = "0$mday";
	}
	if ($mon < 10)
	{
		$mon = "0$mon";
	}
	my $date = "$year-$mon-$mday";
	my $time = "$hour:$min:$sec";
	if (! defined($isLogDate))
	{
		# strip of century most significant digits.
		my @yy  = split('',$year);
		$year  = join('', @yy[2..3]);
		if ($year < 10)
		{
			$year = "0$year";
		}
		return "$year$mon$mday";
	}
	if ($isLogDate == 1)
	{
		return "[$date $time]";
	}
	else
	{
		return "$year$mon$mday";
	}
}
##### Server (OCLC) side parameters
my $edxAccount         = qq{cnedm};
my $projectIdMixed     = qq{P012569};
my $projectIdCancel    = qq{P012570};
my $userName           = "t".$edxAccount."1";      # User name for FTP
my $ftpUrl             = qq{edx.oclc.org};
my $ftpDir             = qq{edx.ebsb.$edxAccount.ftp};
##### Client (our) side parameters
my $maxRecords         = 16000;            # Max number records we can upload at a time, use -s to change.
my $date               = getTimeStamp;     # current date in ascii.
############### change to your favourite since cron needs to know where to put all the results.
my $oclcDir            = qq{/s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC};
my $passwordPath       = qq{$oclcDir/password.txt};
my $logDir             = $oclcDir;
my $logFile            = qq{$logDir/oclc$date.log};  # Name and location of the log file.
my $defaultCatKeysFile = qq{$oclcDir/catalog_keys.lst}; # master list of catalog keys.
my $APILogfilename     = qq{$oclcDir/oclcAPI.log};
my $FTPLogfilename     = qq{$logDir/ftp.log};
my $flatUpateFile      = qq{$oclcDir/overlay_records.flat};
# preset these values and getDateBounds() will redefine then as necessary.
chomp( my $startDate   = `transdate -m-1` );
chomp( my $endDate     = `transdate -m-0` );
chomp( my $tmpDir      = `getpathname tmp` );
open LOG, ">>$logFile";

# Prints usage message then exits.
# param:
# return:
sub usage
{
    print STDERR << "EOF";

Uploads bibliographic records to OCLC.

To run the process manually do:
1) oclc.pl -a [-d"start,end"]
2) oclc.pl -s $defaultCatKeysFile
3) oclc.pl -c
4) oclc.pl -f

usage: $0 [-acADrtuwx] [-M file] [-s file] [-f files] [-z <n>] [-d"[start_date],[end_date]"] [-[lm] file]

 -a            : Run the API commands to generate a file of catalog keys called $defaultCatKeysFile.
                 If -t is selected, the intermediate temporary files are not deleted.
 -A            : Do everything: run api catalog dump, split to default sized
                 files and upload the split files and labels. Same as running
                 -a -f 
 -c            : Catalog dump the cat keys found in any data files (like 120829.FILE5) 
                 in the current directory, replacing the contents with the dumped catalog records.
 -D            : Creates deleted items for OCLC upload. Like -A but for Cancels (deletes). 
 -d [start,end]: Comma separated start and end date. Restricts search for items by create and 
                 modify dates. Defaults to one month ago as specified by 'transdate -m-1' and 
                 today's date for an end date. Both are optional but must be valid ANSI dates or
                 the defaults are used.
 -f            : Finds DATA and matching LABEL files in current directory, and FTPs them to OCLC.
 -lyymmdd.LAST : Create a label file for a given CANCEL or Delete file. NOTE: use the yymmdd.FILEn, or yymmdd.LAST
                 since $0 needs to count the number of records; the DATA.D MARC file has 1 line.
 -myymmdd.LAST : Create a label file for a given MIXED or adds/changes project file. NOTE: use the yymmdd.FILEn,
                 or yymmdd.LAST since $0 needs to count the number of records; the DATA.D MARC file has 1 line.
 -U            : Updates bibrecords with missing OCLC numbers extracted from OCLC CrossRef Reports 
                 (like D120913.R468704.XREFRPT.txt).
 -M [file]     : Creates a MARC DATA.D file ready for uploading from a given flex keys file (like 120829.FILE5).
 -r            : Reset OCLC password.
 -s [file]     : Split input into maximum number of records per DATA file(default 90000).
 -t            : Debug
 -w            : Sweep up the current directory of OCLC litter from the last run.
                 Removes LABEL, DATA, log and 123456.LAST files. Exits after running.
 -x            : This (help) message.
 -z [int]      : Set the maximum output file size in lines, not bytes, this allows for splitting 
                 a set of catalogue keys into sets of 90000 records, which are then piped to catalogdump.

example: To just split an arbitrary text file into files of 51 lines each: $0 -z51 -s51 file.lst
         Split an arbitrary text file into files of 90000 lines each and create OCLC labels: $0 -sfile.lst -l
         To produce a cat key file for the last 30 days: $0 -a
         Produce the Cancels for last month: $0 -D
         To produce a cat key file for the beginning of 2011 to now: $0 -a -d"20110101,"
         To produce a cat key file for the January 2012: $0 -a -d"20120101,20120201"
         To create marc record files from existing key files: $0 -c
         To FTP existing marc DATA and LABEL files to OCLC: $0 -f
         To do everything: $0 -A
		 
 Version: $VERSION
EOF
    exit;
}

# Returns the password, or a new password, based on the contents of the password file 
# specified in the 'path' parameter. Only the first line of the password
# file is checked and any characters on the first line (with the exception of the 
# new line character) are considered part of the password. Any other lines in the 
# file are ignored and will be deleted if the isNewPasswordRequest paramater is passed.
#
# param:  isNewPasswordRequest anyType - pass in a 1 if you want a new password generated
#         The old password is read from file, a new password is generated, the old password
#         file is deleted and the new password is written to the file specified by param: path. 
# return: password string.
sub getPassword( $ )
{
	my $isNewPasswordRequest = shift;
	my $oldPassword;
	my $newPassword;
	open( PASSWORD, "<$passwordPath" ) or die "error failed to read '$passwordPath' $!\n";
	my @lines = <PASSWORD>;
	close( PASSWORD );
	die "error: password file must contain the password as the first line.\n" if (! @lines or $lines[0] eq "");
	$oldPassword = $lines[0];
	chomp( $oldPassword );
	if ( $isNewPasswordRequest )
	{
		my @passwdChars = split('', $oldPassword);
		++$passwdChars[$#passwdChars];
		$newPassword = join('',@passwdChars);
		# now perl helpfully changes ++{z} to {aa}, great but makes password too long for OCLC so 
		# now we will shorten it by removing the second character. WARNING if the second character
		# of your password is your one-and-only required digit, your password will fail.
		$newPassword = join( '',@passwdChars[0,2..$#passwdChars] ) if ( length( $newPassword ) > 8 );
		open(PASSWORD, ">$passwordPath") or print "error failed to write '$passwordPath' $!, the new password is $newPassword\n";
		print PASSWORD "$newPassword\n";
		close(PASSWORD);
		return $newPassword;
	}
	return $oldPassword;
}

#
# bash-3.00$ ftp edx.oclc.org
# Connected to edx.oclc.org.
# 220-TCPIPFTP IBM FTP CS V1R11 at ESA1.DEV.OCLC.ORG, 17:25:30 on 2012-08-31.
# 220 Connection will close if idle for more than 10 minutes.
# Name (edx.oclc.org:sirsi): tcnedm1
# 331 Send password please.
# Password:
# 230-Password was changed.
# 230 TCNEDM1 is logged on.  Working directory is "TCNEDM1.".
# Remote system type is MVS.
# ftp> quit
# 221 Quit command received. Goodbye.
# bash-3.00$
# You only get 5 chances then your account is barred and you have to phone 1-800-
sub resetPassword
{
	# my $oldPassword = getPassword( 0 );
	# print "oldPassword = '$oldPassword'\n";
	# my $newPassword = getPassword( 1 );
	# print "newPassword = '$newPassword'\n";
	# return;
	# open( FTP, "| ftp -n $ftpUrl >$FTPLogfilename" ) or die "Error failed to open stream to $ftpUrl: $!\n";
	# logit( "stream opened." );
	# print FTP "quote USER $userName\n";
	# print FTP "quote PASS oldPassword/3dmontov/3dmontov\n";
	# print FTP "quote PASS $oldPassword/$newPassword/$newPassword\n";
	# print FTP "bye\n";
	# print close( FTP )."\n";
	# print ">>>$?\n";
	# logit( "connection closed" );
}

#
# Prints the argument message to stdout and log file.
# param:  message string.
# return: 
#
sub logit
{
	my $msg = $_[0];
	print     getTimeStamp(1) . " $msg\n";
	print LOG getTimeStamp(1) . " $msg\n";
}

#
# Trim function to remove whitespace from the start and end of the string.
# param:  string to trim.
# return: string without leading or trailing spaces.
sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'AactDd:fl:M:m:xrs:tUwz:';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ($opt{'x'});
	if ( $opt{'z'} )
	{
		$maxRecords = $opt{'z'};
		logit( "maximum file size set to $opt{'z'}" );
	}
	if ( $opt{'l'} ) # expects <yymmdd>.FILEn for cancel project id.
	{
		createStandAloneLabelFile( $opt{'l'}, $projectIdCancel );
	}
	if ( $opt{'m'} )# expects <yymmdd>.FILEn for mixed project id.
	{
		createStandAloneLabelFile( $opt{'m'}, $projectIdMixed );
	}
	if ( $opt{'r'} )# expects <yymmdd>.FILEn for mixed project id.
	{
		exit( 0 ) if ( not resetPassword( $projectIdMixed ) );
		exit( 1 );
	}
	if ( $opt{'M'} )# create a MARC file and LABEL file for uploading from a [date].LAST file.
	{
		createStandAloneMARCFile( $opt{'M'} );
		exit( 1 );
	}
	if ( $opt{'U'} )# create a MARC file and LABEL file for uploading from a [date].LAST file.
	{
		exit( 0 ) if ( not overlayOCLCControlNumber( ) );
		exit( 1 );
	}
	if ( $opt{'w'} ) # clean up directory
	{
		unlink( $defaultCatKeysFile ) if ( -e $defaultCatKeysFile ); # master list of catalog keys.
		unlink( $APILogfilename ) if ( -e $APILogfilename );
		unlink( $flatUpateFile ) if ( -e $flatUpateFile );
		my @fileList = <*\.log>;
		foreach my $file ( @fileList )
		{
			unlink( $file ) if ( -e $file );
		}
		@fileList = <DATA\.D[0-9][0-9][0-9][0-9][0-9][0-9]\.*>;
		foreach my $file ( @fileList )
		{
			unlink( $file ) if ( -e $file );
		}
		@fileList = <LABEL\.D[0-9][0-9][0-9][0-9][0-9][0-9]\.*>;
		foreach my $file ( @fileList )
		{
			unlink( $file ) if ( -e $file );
		}
		@fileList = <[0-9][0-9][0-9][0-9][0-9][0-9]\.*>;
		foreach my $file ( @fileList )
		{
			unlink( $file ) if ( -e $file );
		}
		exit( 1 );
	}
	# set dates conditionally on default or user specified dates.
	getDateBounds();
}
init();

# If the user specified a specific file to split. It will split
# ANY text file into 90000 line files.
if ($opt{'A'})
{
	logit( "-A started" ) if ( $opt{'t'} );
	# select the catalog keys.
	selectCatKeys();
	my $date = getTimeStamp(); # get century most significant digits stripped date.
	logit( "reading '$defaultCatKeysFile', using file size: $maxRecords" );
	# split the files into the desired number of records each.
	my $fileCounts = splitFile( $maxRecords, $date, $defaultCatKeysFile );
	logit( "'$defaultCatKeysFile' split into " . keys( %$fileCounts ) . " parts" );
	# create the catalog dump of the keys for each set.
	dumpCatalog( $fileCounts );
	print "=== Please FTP files manually. Check -x option for more details ===\n";
	logit( "-A finished" ) if ( $opt{'t'} );
	exit 1; # because running other commnads clobbers the files you just created.
}

# Creates and uploads the delete items for OCLC.
if ($opt{'D'})
{
	logit( "-D started" ) if ( $opt{'t'} );
	## Select deleted items from the history log.
	# Select the history files we need. If the requested files are from April 5 onward, we need to specify /{HIST}/201105.hist.Z
	my @histLogs = getRelevantHistoryLogFiles();
	# collect codes of deleted items.
	my $allFlexKeysFromHistory = collectDeletedItems( @histLogs );	
	# Now we will check for call nums that arn't in the catalog since those are are the flexkeys 
	# for titles that no longer exist, and by definition, have been deleted.
	my $initialFlexKeyFile       = qq{$tmpDir/tmp_a};
	my $flexKeysNotInCatalogFile = qq{$tmpDir/tmp_b};
	open( ALL_FLEX_KEYS, ">$initialFlexKeyFile" ) or die "Unable to write to '$initialFlexKeyFile': $!\n";
	while ( my ( $key, $value ) = each( %$allFlexKeysFromHistory ) )
	{
		print ALL_FLEX_KEYS "$key|$value\n";
	}
	close( ALL_FLEX_KEYS );
	# now read all the cat keys into selcatalog so we can catch the error.
	`cat $initialFlexKeyFile | selcatalog -iF 2>$flexKeysNotInCatalogFile`;
	# if the file wasn't created or had no entries then there are no deletes to do.
	if ( not -s $flexKeysNotInCatalogFile )
	{
		logit( "no deletes found for date selection" );
		exit 1;
	}
	# parse out the flex key from the error message
	my $deletedFlexKeys;
	open( DELETED_FLEX_KEYS, "<$flexKeysNotInCatalogFile" ) or die "Couldn't open '$flexKeysNotInCatalogFile': $!\n";
	while (<DELETED_FLEX_KEYS>)
	{
		# now parse out the flex key from: **error number 111 on catalog not found, key=526625 flex=ADI-7542
		next if ( not m/flex=/ ); # because there are sirsi codes at the bottom, so skip them
		my $deletedFlexKey = trim( substr( $_, ( index( $_, "flex=" ) + length( "flex=" )) ) );
		chomp $deletedFlexKey;
		# look it up in the allFlexKeysFromHistory hash reference.
		$deletedFlexKeys->{ $deletedFlexKey } = $allFlexKeysFromHistory->{ $deletedFlexKey };
	}
	close( DELETED_FLEX_KEYS );
	if ( not $opt{'t'} )
	{
		unlink( $initialFlexKeyFile );
		unlink( $flexKeysNotInCatalogFile );
	}
	logit( "total deleted titles: " . scalar ( keys( %$deletedFlexKeys ) ) );
	#### Blow away pre-existing file (from today).
	open( MASTER_MARC, ">$defaultCatKeysFile" ) or die "Unable to write to '$defaultCatKeysFile' to write deleted items: $!\n";
	while ( my ( $flexKey, $oclcCode ) = each( %$deletedFlexKeys ) )
	{
		print MASTER_MARC "$flexKey|$oclcCode\n";
	}
	close( MASTER_MARC );
	my $fileCounts = splitFile( $maxRecords, $date, $defaultCatKeysFile );
	makeMARC( $fileCounts );
	print "=== Please FTP files manually. Check -x option for more details ===\n";
	logit( "-D finished" ) if ( $opt{'t'} );
	exit 1; # because running other commnads clobbers the files you just created.
}

#
# Select the catalog keys for the items that we are going to upload to OCLC.
# param:  
if ( $opt{'a'} )
{
	selectCatKeys();
}

#
# Finds and catalogdumps the cat keys files that match 
# [0-9][0-9][0-9][0-9][0-9][0-9]\.* (like 120829.FILE5 or 120829.LAST)
# in the current directory. The output is a marc file called 'DATA.D<file_name>'
# example: DATA.D120829.FILE5. After the marc file is created, a matching 
# OCLC label is created.
# param:  none
if ( $opt{'c'} )
{
	logit( "-c started" ) if ( $opt{'t'} );
	my @fileList = <$oclcDir/[0-9][0-9][0-9][0-9][0-9][0-9]\.*>;
	if ( not @fileList )
	{
		logit( "no data files to catalogdump. Did you forget to create list(s) with -a and -s?" );
		exit( 0 );
	}
	my $fileCountHashRef;
	foreach my $file ( @fileList )
	{
		# open file and find the number of records.
		open( KEY_FILE, "<$file" ) or die "Error opening '$file': $!\n";
		my $recordCount = 0;
		while(<KEY_FILE>)
		{
			$recordCount++;
		}
		logit( "found $recordCount cat keys in '$file'" );
		$fileCountHashRef->{ $file } = $recordCount;
	}
	# now pass that to dumpCatalog()
	dumpCatalog( $fileCountHashRef );
	logit( "-c finished" ) if ( $opt{'t'} );
}

#
# Splits a given file into parts. The split occurs on new lines only. The outputted files
# are named <yymmdd>.FILE1, ... <yymmdd>.LAST, or <yymmdd>.LAST if there is only one file.
# param:  inputFileName string - name of the file to split.
if ( $opt{'s'} )
{
	logit( "-s started" ) if ( $opt{'t'} );
	my $date = getTimeStamp(); # get century most significant digits stripped date.
	logit( "reading '$opt{'s'}', using file size: $maxRecords" );
	# Stores the file name (complete path) as a key and the number of items in the file as the value.
	# Use return value for -A switch to get the list of files and their size otherwise you can just use this 
	# to split an arbitrary file.
	my $fileCounts = splitFile( $maxRecords, $date, $opt{'s'} );
	logit( "'$opt{'s'}' split into " . keys( %$fileCounts ) . " parts" );
	logit( "-s finished" ) if ( $opt{'t'} );
}

#
# FTP the DATA and LABEL files if there are matching sets.
if ( $opt{'f'} )
{
	logit( "-f started" ) if ( $opt{'t'} );
	my @fileList = selectFTPList();
	my $password = getPassword( 0 );
	logit( "password read from '$passwordPath'" );
	logit( "ftp successful" ) if ( ftp( $ftpUrl, $ftpDir, $userName, $password, @fileList ) );
	# Test ftp site.
	# logit( "ftp successful" ) if ( ftp( "ftp.epl.ca", "atest", "mark", "R2GnBVtt", @fileList ) );
	logit( "-f finished" ) if ( $opt{'t'} );
}

close(LOG);

# ======================== Functions =========================

# bash-3.00$ head D120906.R466902.XREFRPT.txt
#     OCLC XREF REPORT
#
#  OCLC        Submitted
#  Control #   001 Field
# 727705591    2011023163
# 795038896    2011033697
# 809219600    2011033698
# 746489730    2011033699
# 746489731    2011033700
# 746489732    2011033701
sub overlayOCLCControlNumber
{
	# find all the files that match the D120906.R466902.XREFRPT.txt file name.
	my @fileList = getMixedReports();
	my $tmpFile = qq{$tmpDir/tmp_a};
	while ( @fileList )
	{
		my $report = shift( @fileList );
		logit( "reading '$report'" );
		# read in each report and fill a hash ref with our 001 field and the OCLC number equiv.
		my $oclcNumberHash = getXRefRecords( $report );
		# hash contains 001Field->{OCLC#}
		# optimize seltext query: format hash keys into a file ready for pipeing into seltext
		open( SEARCH, ">$tmpFile" ) or die "Couldn't open '$tmpFile' to write: $!\n";
		for my $key ( keys %$oclcNumberHash )
		{
			print SEARCH "$key {001}\n";
		}
		close( SEARCH );
		logit( "found ".scalar( keys %$oclcNumberHash )." OCLC records" );
		# Create hash of cat keys and OCLC numbers for dumping into a flat MARC file for editmarc.
		my $catKeyHash = get001CatKeys( $oclcNumberHash, $tmpFile );
		logit( "seltext found ".scalar( keys %$catKeyHash )." cat keys" );
		# now match the .001. record to the OCLC number and write it to a flat marc file.
		open( MARC_FLAT, ">$flatUpateFile" ) or die "Error: unable to write to '$flatUpateFile': $!\n";
		while( my ($catKey, $oclcNumber) = each %$catKeyHash ) 
		{
			print MARC_FLAT get001OverlayMARCRecord( $catKey, $oclcNumber );
		}
		close( MARC_FLAT );
		logit( "updating ".scalar( keys %$catKeyHash )." catalogue records" );
		`cat $flatUpateFile | catalogmerge -aMARC -fd -if -t035 -r -un -bc 2>err.log` if ( not -z $flatUpateFile );
		unlink( $tmpFile );
	}
	logit( "update of .035. records complete" );
	return 1;
}

# Creates a reference table of catalogue keys and their corresponding corrected OCLC numbers where required.
# That is to say, only 035 records that need to be updated will be added to the table.
# param:  name of file for seltext to process with 'seltext -lBOTH -oA 2>/dev/null'
# return: hash reference (new) .001.->cat key numbers.
sub get001CatKeys
{
	my ( $oclc001RecordHash, $oclcNumberFile ) = @_;
	my $hash = {};
	my $seltextFoundResult = `cat $oclcNumberFile | seltext -lBOTH | prtmarc.pl -e"001,035" -oCT 2>/dev/null`;
	# which looks like this when successful:
	# 951674|sbb00213613|\a(CaAE) a1002664|\a(OCoLC)751833924|
	my @foundCatalogueEntries = split( '\n', $seltextFoundResult );
	logit( scalar( @foundCatalogueEntries )." found" );
	foreach my $line ( @foundCatalogueEntries )
	{
		my @record = split( '\|', $line );
		# 951674|sbb00213613|\a(OCoLC)751833924|
		my ( $catKey, $zeroZeroOne, @catalogOclcNumbers ) = split( '\|', $line );
		my $catalogOclcNumber = join( ' ', @catalogOclcNumbers );
		# this is important since seltext can search with values that include leading whitespace
		# but the leading whitespace will not match records saved as a hash key.
		$zeroZeroOne = trim( $zeroZeroOne );
		my $reportedOclcNumber = $oclc001RecordHash->{ $zeroZeroOne };
		next if ( not $reportedOclcNumber );
		$hash->{ $catKey } = $reportedOclcNumber if ( $catalogOclcNumber !~ m/($reportedOclcNumber)/ );
	}
	return $hash;
}

# Creates a reference table of the .001. and corresponding OCLC numbers from an OCLC report.
# param:  the name of the file to be read; must be a valid XRef file sent from OCLC like D120913.R468637.XREFRPT.txt.
# return: hash reference of 001 numbers and correct OCLC numbers.
sub getXRefRecords($)
{
	my $file = shift;
	my $hash = {};
	open( REPORT, "<$file" ) or die "Error: unable to open '$file': $!\n";
	while (<REPORT>)
	{
		my $line = trim( $_ )."\n"; # Trim takes off the white space and newline.
		# skip blank lines and lines that don't start with numbers 
		next if ( $line !~ m/^\d/ ); # skip if the line doesn't start with a number.
		# lets split the line on the white space swap the values so the 001 field is first.
		my @oclc001 = split( /\s{4}/, $line );
		chomp( $oclc001[1] );
		$hash->{$oclc001[1]} = $oclc001[0];
	}
	close( REPORT );
	return $hash;
}

# Creates a minimal list of well formed flat MARC record of 001 and 035 fields for overlay.
# param:  oclc record string oclc number.
# param:  001 record string catalog 001 field.
# return: string well formatted flat marc record.
sub get001OverlayMARCRecord
{
	# Updating by cat key is more reliable but produces errors like:
	# **Entry ID not found in format MARC: 1003
	# because there is no entry for 1003 in the entry id config for MARC - it's a Sirsi number
	# not related to MARC records.
	my ( $catKey, $oclcNumber ) = @_;
	return "" if ( not $catKey or not $oclcNumber ); # if either not fufilled then return early.
	my $marc = "*** DOCUMENT BOUNDARY ***\n";
	$marc .= "FORM=MARC\n";
	$marc .= ".1003. |a$catKey\n"; 
	$marc .= ".035.   |a(OCoLC)$oclcNumber\n";
	return $marc;
}

# Fetch the valid Mixed reports - not Cancels and not summaries.
# param:  
# return: list valid reports to parse out OCLC numbers.
# TODO:   fix so that it ftps reports from psw.oclc.org.
sub getMixedReports
{
	my @fileList = ();
	my @tmp = <$oclcDir/D[0-9][0-9][0-9][0-9][0-9][0-9]\.R*>;
	# my @tmp = <test.XREFRPT.txt>;
	while ( @tmp )
	{
		# separate the XREFRPT files.
		my $file = shift( @tmp );
		# TODO get files from the report site itself with wget --user=100313990 --password=some_password http://psw.oclc.org/download.aspx?setd=netbatch
		# returns a page requesting login.
		next if ( $file !~ m/XREFRPT/ );
		push( @fileList, $file );
	}
	logit( "found ".scalar( @fileList )." reports: @fileList" );
	return @fileList;
}

#*** DOCUMENT BOUNDARY ***
#FORM=MARC
#.000. |aamI 0d
#.001. |aACY-7433
#.008. |a120831nuuuu    xx            000 u und u
#.035.   |a(OCoLC)30913700
#.852.   |aCNEDM
#
# param:  HashRef of file names and lengths
# return: 
# side effect: creates MARC file and LABEL.
sub makeMARC
{
	my $fileCountHashRef = shift;
	logit( "dumping MARC records" ) if ( $opt{'t'} );
	while( my ($fName, $numRecords) = each %$fileCountHashRef )
	{
		# open and read the keys in the file
		my ($fileName, $directory, $suffix) = fileparse($fName);
		my $outputFileName = qq{$oclcDir/DATA.D$fileName};
		my $outputFileFlat = "$outputFileName.flat";
		logit( "dumping keys found in '$fileName' to '$outputFileFlat'" );
		open( SPLIT_FILE, "<$fName" ) or die "unable to open split file '$fName': $!\n";
		open( MARC_FILE, ">$outputFileFlat" ) or die "unable to write to '$outputFileFlat': $!\n";
		while (<SPLIT_FILE>)
		{
			chomp( $_ );
			print MARC_FILE getFlatMARC( $_, $date );
		}
		close( MARC_FILE );
		close( SPLIT_FILE );
		# convert with flatskip.
		`cat $outputFileFlat | flatskip -aMARC -if -om > $outputFileName 2>>$APILogfilename`;
		logit( "converted '$outputFileFlat' to MARC" );
		# create a label for the file.
		unlink( $outputFileFlat );
		createOCLCLableFiles( qq{$oclcDir/$fileName}, $numRecords, $projectIdCancel );
	}
	logit( "dumping of MARC records finished" ) if ( $opt{'t'} );
}

# Gets a well-formed flat MARC record of the argument record and date string.
# This subroutine is used in the Cancels process.
# param:  The record is a flex key and oclcNumber separated by a pipe: AAN-1945|(OCoLC)3329882|
# return: flat MARC record as a string.
sub getFlatMARC
{
	my ( $record, $date ) = @_;
	my ( $flexKey, $oclcNumber ) = split( '\|', $record );
	my $returnString = "*** DOCUMENT BOUNDARY ***\n";
	$returnString .= "FORM=MARC\n";
	$returnString .= ".000. |aamI 0d\n";
	$returnString .= ".001. |a$flexKey\n";
	$returnString .= ".008. |a".$date."nuuuu    xx            000 u und u\n"; # like 120831
	$returnString .= ".035.   |a$oclcNumber\n"; # like (OCoLC)32013207
	$returnString .= ".852.   |aCNEDM\n";
	return $returnString;
}

#
# Search the arg list of log files for entries of remove item (FV) and remove title option (NOY).
# param:  log files List - list of log files to search.
# return: Hash reference of cat keys as key and history log entry as value.
sub collectDeletedItems
{
	my @logFiles = @_;
	my $items;
	my $searchIsOn = 0;
	# to stop when it reaches the endDate, but collect all the values including the endDate so select records of the endDate +1.
	my $myEndDate = `transdate -p$endDate+1`;
	chomp( $myEndDate );
	while ( @logFiles )
	{
		my $file = shift( @logFiles );
		my $result = `gzgrep FVFF $file`;
		my @potentialItems  = split( '\n', $result );
		foreach my $logLine ( @potentialItems )
		{
			# Note that in the .035. record below, (Sirsi) numbers are output if there is no OCLC number.
			# If a OCLC number exists it is output regardless of if a Sirsi number exists. If one doesn't 
			# exist then the Sirsi number is output.
			$searchIsOn = 1 if ( not $searchIsOn and $logLine =~ m/^E($startDate)/ );
			$searchIsOn = 0 if ( $searchIsOn and $logLine =~ m/^E($myEndDate)/ );
			if ( $searchIsOn )
			{
				if ( $logLine =~ m/\^aA\(OCoLC\)/ or $logLine =~ m/\^aA\(Sirsi\)/ or $logLine =~ m/\^aAocm/ )
				{
					my ( $flexKey, $oclcNumber ) = getFlexKeyOCLCNumberPair( $logLine );
					$items->{ $flexKey } = $oclcNumber;
				}
			}
		}
	}
	logit( "found ".scalar( keys( %$items ) )." in logs" );
	return $items;
}

# Returns the flex key and oclc number pair.
# param:  log record line string.
# return: (key, value) flexkey and oclc number.
sub getFlexKeyOCLCNumberPair
{
	my $logRecord = $_[0];
	my $key;
	my $value;
	my @entries = split( /\^/, $logRecord );
	foreach my $entry ( @entries )
	{
		$key   = $entry if ( $entry =~ s/^IU// );
		if ( $entry =~ s/^aA// )
		{
			$entry =~ s/\s//g;        # get rid of whitespace.
			$entry =~ s/Sirsi/OCoLC/; # Change sirsi id to OCoLC prefix.
			$value = $entry;
		}
	}
	return ( $key, $value );
}

#
# Returns a list of History logs that are required to meet the date criteria.
# param:  
# return: fully qualified paths of the history files required by date criteria.
sub getRelevantHistoryLogFiles
{
	# get the inclusive dates and an entire list of history files from the hist directory.
	# find the history files that are > the start date and < end date and place them on a list.
	# if the end date is today's date then we need to add a specially named log file that looks like
	# 20120904.hist
	my @files = ();
	return $opt{'f'} if ( $opt{'f'} );
	chomp( my $histDirectory = `getpathname hist` );
	# Start will be the first 6 chars of an ANSI date: 20120805 and 20120904
	my $startFileName = substr( $startDate, 0, 6 );
	my $endFileName   = substr( $endDate,   0, 6 );
	my @fileList = <$histDirectory/[0-9][0-9][0-9][0-9][0-9][0-9]\.hist*>;
	my ( $fileName, $directory, $suffix );
	foreach my $file ( @fileList )
	{
		( $fileName, $directory, $suffix ) = fileparse( $file );
		my $nameDate = substr( $fileName, 0, 6 );
		push( @files, $file ) if ( scalar( $nameDate ) >= scalar( $startFileName ) and scalar( $nameDate ) <= scalar( $endFileName ));
	}
	# for today's log file we have to compose the file name
	chomp( my $today = `transdate -d-0` );
	if ( $endDate eq $today )
	{
		# append today's log which looks like 20120904.hist
		push ( @files, "$histDirectory/$today.hist" );
	}
	logit( "found the following logs that match date criteria: @files" );
	return @files;
}

#
# Selects valid files to FTP to OCLCC. Valid set is a complete set of 
# DATA files along with a matching set of LABEL files.
# param:  
# return: ftpList array - List of files eligible for FTP to OCLC.
sub selectFTPList
{
	logit( "selectFTPList started" ) if ( $opt{'t'} );
	my @ftpList;
	logit( "generating eligible list of marc DATA and LABEL files" );
	my @dataList = <$oclcDir/DATA.D*>;
	my @labelList= <$oclcDir/LABEL.D*>;
	logit( "dataList  contains: '@dataList'" ) if ( $opt{'t'} );
	logit( "labelList contains: '@labelList'" ) if ( $opt{'t'} );
	# rough test that there are the same number of DATA files as LABEL files,
	# if there are not, there may files left in the directory from earlier in the day.
	if ( scalar( @dataList ) != scalar( @labelList ) )
	{
		logit( "Error: mismatch of DATA and LABEL files" );
		exit( 0 );
	}
	# match up the data and label files.
	foreach my $dataFile ( @dataList )
	{
		# compare names so the files are pushed onto the list in order, each DATA with its LABEL.
		my ( $thisDataName, $directory, $suffix ) = fileparse( $dataFile );
		my $dataName = substr( $thisDataName, 4 );
		foreach my $labelFile ( @labelList )
		{
			my ( $thisLabelName, $directory, $suffix ) = fileparse( $labelFile );
			my $labelName = substr( $thisLabelName, 5 );
			if ( $dataName eq $labelName )
			{
				push( @ftpList, $dataFile );
				push( @ftpList, $labelFile );
				logit( "'$dataFile' and '$labelFile' selected" );
			}
		}
	}
	logit( "ftpList contains: '@ftpList'" );
	if ( scalar( @dataList ) * 2 != scalar( @ftpList ) )
	{
		logit( "Error: mismatch of DATA and LABEL files" );
		exit( 0 );
	}
	logit( "FTP list: @ftpList" );
	logit( "selectFTPList finished" ) if ( $opt{'t'} );
	return @ftpList;
}

#
# Select all the catalog keys based on the dates specified.
# param:  
# return:
#
sub selectCatKeys
{
	logit( "-a started" ) if ( $opt{'t'} );
	my $initialItemCatKeys = qq{$tmpDir/tmp_a};
	my $sortedItemCatKeys  = qq{$tmpDir/tmp_b};
	my $dateRefinedCatKeys = qq{$tmpDir/tmp_c};
	print "-a selected -run API.\n" if ($opt{'t'});
	my $unicornItemTypes = "PAPERBACK,JPAPERBACK,BKCLUBKIT,COMIC,DAISYRD,EQUIPMENT,E-RESOURCE,FLICKSTOGO,FLICKTUNE,JFLICKTUNE,JTUNESTOGO,PAMPHLET,RFIDSCANNR,TUNESTOGO,JFLICKTOGO,PROGRAMKIT,LAPTOP,BESTSELLER,JBESTSELLR";
	logit( "exclude item types: $unicornItemTypes" );
	my $unicornLocations = "BARCGRAVE,CANC_ORDER,DISCARD,EPLACQ,EPLBINDERY,EPLCATALOG,EPLILL,INCOMPLETE,LONGOVRDUE,LOST,LOST-ASSUM,LOST-CLAIM,LOST-PAID,MISSING,NON-ORDER,ON-ORDER,BINDERY,CATALOGING,COMICBOOK,INTERNET,PAMPHLET,DAMAGE,UNKNOWN,REF-ORDER,BESTSELLER,JBESTSELLR,STOLEN";
	logit( "exclude locations: $unicornLocations" );
	# gets all the keys of items that don't match the location list or item type lists.
	logit( "selecting initial catalogue keys" );
	`selitem -t~$unicornItemTypes -l~$unicornLocations -oC >$initialItemCatKeys`;
	open( INITIAL_CAT_KEYS, "<$initialItemCatKeys" ) or die "No items found.\n";
	logit( "sorting initial catalogue key selection" );
	my %initialKeys;
	while (<INITIAL_CAT_KEYS>)
	{
		chop $_; # remove new line for numeric sort
		chop $_; # remove pipe for numeric sort
		$initialKeys{$_} = 1;
	}
	close( INITIAL_CAT_KEYS );
	# we sort keys numerically.
	open( SORTED_CAT_KEYS, ">$sortedItemCatKeys" ) or die "No items to sort.\n";
	# sort the keys in numerical order, sort | uniq produces a pseudo-sort.
	foreach my $key (sort {$a <=> $b} keys(%initialKeys))
	{
		print SORTED_CAT_KEYS $key."|\n";
	}
	close( SORTED_CAT_KEYS );
	my $dateBoundaries = getDateBounds();
	# select all catalog keys for items that were either modified or created between the dates selected.
	logit( "adding keys that were created within date criteria '$dateBoundaries'" );
	`cat $sortedItemCatKeys | selcatalog -iC -oC -p"$dateBoundaries" > $dateRefinedCatKeys 2>>$APILogfilename`;
	logit( "adding keys that were modified within date criteria '$dateBoundaries'" );
	`cat $sortedItemCatKeys | selcatalog -iC -oC -r"$dateBoundaries" >>$dateRefinedCatKeys 2>>$APILogfilename`;
	logit( "sorting date refined catalogue key selection" );
	open( DATED_CAT_KEYS, "<$dateRefinedCatKeys" ) or die "No items found refined by date: $!\n";
	my %dateRefinedKeys;
	while (<DATED_CAT_KEYS>)
	{
		chop $_; # remove new line for numeric sort
		chop $_; # remove pipe for numeric sort
		$dateRefinedKeys{$_} = 1;
	}
	close( DATED_CAT_KEYS );
	# sort the uniq catalog keys numerically.
	open( SORTED_DATED_CAT_KEYS, ">$defaultCatKeysFile" ) or die "Error opening file to write sorted, date refined CAT keys, $!\n";
	foreach my $finalKey (sort {$a <=> $b} keys(%dateRefinedKeys))
	{
		print SORTED_DATED_CAT_KEYS $finalKey."|\n";
	}
	close( SORTED_DATED_CAT_KEYS );
	if ( not $opt{'t'} )
	{
		unlink( $initialItemCatKeys );
		unlink( $sortedItemCatKeys  );
		unlink( $dateRefinedCatKeys );
	}
	logit( "catalogue key selection saved in '$defaultCatKeysFile'" );
	logit( "-a finished" ) if ( $opt{'t'} );
}

#
# Dumps the cat keys from a list of files and creates labels for those files.
# param:  fileCountHashRef hash - key: file name like 120829.LAST, value: number
#         of records in the file.
# return: 
# side effect: creates DATA.D<fileName> files.
#
sub dumpCatalog
{
	my $fileCountHashRef = $_[0];
	logit( "dumpCatalog started" ) if ( $opt{'t'} );
	while( my ($fileName, $numRecords) = each %$fileCountHashRef )
	{
		# open and read the keys in the file
		
		my ($fName, $directory, $suffix) = fileparse( $fileName );
		logit( "dumping catalogue keys found in '$fileName' to 'DATA.D$fName'" );
        `cat $fileName | catalogdump -om > $directory/DATA.D$fName 2>>$APILogfilename`;
		# create a label for the file.
		createOCLCLableFiles( $fileName, $numRecords, $projectIdMixed );
	}
	logit( "dumpCatalog finished" ) if ( $opt{'t'} );
}

#
# Returns '<', '>' dates based on -d switch specified by the user. 
# The format is -d"<start_ANSI>,<end_ANSI>", like -d"20120101,20120201".
# not specifying a start date defaults to one month ago, as defined by transdate -d-30.
# Not specifying end date defaults to today. The start date is the furthest date back in time.
# The end date is the most recent.
# param:  none
# return: ">startDate<endDate"
#
sub getDateBounds
{
	if  ( $opt{'d'} )
	{
		my @dates = split( ',', $opt{'d'});
		if ( $dates[0] and $dates[0] ne "" and $dates[0] =~ m/\d{8}/ )
		{
			$startDate = $dates[0];
		}
		if ( $dates[1] and $dates[1] ne "" and $dates[1] =~ m/\d{8}/ )
		{
			$endDate = $dates[1];
		}
	}
	logit( "date boundaries set to '>$startDate<$endDate'" );
	return ">$startDate<$endDate";
}

#
# FTPs a list of files to a remote host.
# param:  host - string name of the FTP host.
# param:  directory - string remote directory.
# param:  userName - string user id for FTP login.
# param:  password - string.
# param:  fileList - List of files to FTP to remote directory on remote host.
# return: 
#
sub ftp
{
	my ($host, $directory, $userName, $password, @fileList) = @_;
	open( FTP, "| ftp -n $host\n >$FTPLogfilename" ) or die "Error failed to open stream to $host: $!\n";
	logit( "stream opened." );
	print FTP "quote USER $userName\n";
	logit( "passed user name" );
	print FTP "quote PASS $password\n";
	logit( "password sent" );
	print FTP "bin\n";
	logit( "binary mode set" );
	# does this work? No.
	# print FTP "quote PASS R2GnBVtt/iLovePuppets/iLovePuppets\n";
	# This isn't understood by the epl.ca ftp server.
	print FTP "quote site cyl pri=20 sec=20\n";
	logit( "set pri and sec for oversized files" );
	print FTP "cd '$directory'\n";
	logit( "cd'd to '$directory'" );
	my ( $file, $localDirectory, $suffix ) = fileparse( $fileList[0] );
	# don't use quotes for local directory.
	print FTP "lcd $localDirectory\n";
	logit( "lcd'd to $localDirectory" );
	foreach my $fileOnList ( @fileList )
	{
		( $file, $localDirectory, $suffix ) = fileparse( $fileOnList );
		logit( "putting $file" );
		print FTP "put $file\n";
	}
	print FTP "ls\n";
	print FTP "bye\n";
	logit( "connection closed" );
	close( FTP );
	# $Directives{'status'} = $?;
	return 1;
}

# Takes the list and splits it into 'n' sized record files.
# param:  max number of records per file.
# param:  baseName string - what you want the base name of the file to be.
# param:  file input name. split files created in current directory.
# return: hash reference of fileSizes.
sub splitFile
{
	my ($maxRecords, $baseName, $fileInput) = @_;
	logit( "splitFile started" ) if ( $opt{'t'} );
	my $fileSizeRef;         # hash ref of file names and record sizes.
	my $lineCount      = 0;  # current number of lines written to the current file fragment.
	my $numLinesInput  = 0;  # number of input lines to process.
	my $fileCount      = 0;  # number of files to create.
	my @fileNames      = (); # precomposed list of file names
	my $fileName;            # The current file name within the loop
	# find out how many files we need, this saves us a lot of time renaming the last file.
	open(INPUT, "<$fileInput") or die "Error opening file to split: $!\n";
	while(<INPUT>)
	{
		$numLinesInput++;
	}
	close( INPUT );
	$fileCount = ceil( $numLinesInput / $maxRecords );
	# precompose the split file names
	for ( my $i = 1; $i < $fileCount; $i++ ) 
	{
		push( @fileNames, qq{$oclcDir/$baseName.FILE$i} ); # [120623.FILE1 ...] 120623.LAST, for generic files
		# -c will prepend the correct 'DATA.D' when dumping the catalog records.
	}
	# the last file is always called *.LAST even if there is only one file.
	push( @fileNames, qq{$oclcDir/$baseName.LAST} );
	# open the input file and prepare read the contents into each file fragment.
	open(INPUT, "<$fileInput") or die "Error opening file to split: $!\n";
	while(<INPUT>)
	{
		if ( $lineCount == $maxRecords )
		{
			$fileSizeRef->{ $fileName } = $lineCount;
			$lineCount = 0;
			close( OUT );
			logit( "created DATA file: '$fileName'" );
		}
		if ( $lineCount == 0 )
		{
			$fileName = shift( @fileNames );
			open( OUT, ">$fileName" ) or die "error opening '$fileName': $!\n";
		}
		$lineCount++;
		print OUT "$_";
	}
	# If there were no more records, the previous code would create a zero size file.
	if ( $lineCount > 0 )
	{
		close( OUT );
		$fileSizeRef->{ $fileName } = $lineCount;
		logit( "created DATA file: '$fileName'" );
	}
	close(INPUT);
	logit( "splitFile finished" ) if ( $opt{'t'} );
	return $fileSizeRef;
}

# Creates a valid OCLC MARC file and LABEL for upload for Cancels projects.
# param:  file string - name of the file with fully qualified path
# return: 
# side effect: creates MARC file and LABEL file.
sub createStandAloneMARCFile
{
	my ( $file ) = @_;
	if ( $file =~ m/\d[6]/ )
	{
		logit( "looks like '$file' is not a valid Cancels data file name. Exiting" );
		exit( 0 );
	}
	logit( "creating Cancels file from '$file'" );
	# we need $dataFileName, $numRecords so 
	open( DATA, "<$file" ) or die "Error opening '$file': $!\n";
	my $lineCount = 0;
	while(<DATA>)
	{
		$lineCount++;
	}
	close( DATA );
	my $fileHashRef;
	$fileHashRef->{$file} = $lineCount;
	makeMARC( $fileHashRef );
}

# Creates a valid OCLC label file for a specific project type. Projects are either 
# mixed for adds and changes, or cancel for deleted catalog items.
# param:  file string - name of the file with fully qualified path
# param:  projectType string - project id for either cancels or mixed.
# return: 
# side effect: creates label file.
sub createStandAloneLabelFile
{
	my ( $file, $projectType ) = @_;
	if ( $file =~ m/\d[6]/ )
	{
		logit( "looks like '$file' is not a valid data file name. Exiting" );
		exit( 0 );
	}
	logit( "creating label file for '$file'" );
	# we need $dataFileName, $numRecords so 
	open( DATA, "<$file" ) or die "Error opening '$file': $!\n";
	my $lineCount = 0;
	while(<DATA>)
	{
		$lineCount++;
	}
	close( DATA );
	createOCLCLableFiles( $file, $lineCount, $projectType );
}

# Creates the label file to specifications:
# The LABEL file should be created as a flat text file. It contains 
# the metadata of the uploaded DATA file. There are five mandatory 
# records, DAT, RBF, DSN, ORS and FDI. They must appear in upper case.
#
# DAT  20replacewithdate000000.0
# RBF  replacewithcount
# DSN  DATA.Dreplacewithdate
# ORS  CNEDM
# FDI  P012569
#
# Example:
# DAT  20110405000000.0
# RBF  88947   
# DSN  DATA.D110405
# ORS  CNEDM
# FDI  P012569
#
# param:  dataFileName string - like /s/sirsi/Unicorn/120829.FILE1
# param:  recordCount integer - number of records in the file
# return: 
# side effect: creates a label file named LABEL.D<dataFileName>
#### TEST ####
sub createOCLCLableFiles
{
	my ( $dataFileName, $numRecords, $projectId ) = @_;
	my ($fileName, $directory, $suffix) = fileparse($dataFileName);
	my $labelFileName = qq{$oclcDir/LABEL.D}.$fileName;
	open( LABEL, ">$labelFileName" ) or die "error couldn't create label file '$labelFileName': $!\n";
	print LABEL "DAT  ".getTimeStamp(0)."000000.0\n"; # 14.1 - '0' right fill.
	print LABEL "RBF  $numRecords\n"; # like: 88947
	print LABEL "DSN  DATA.D$fileName\n"; # DATA.D110405.LAST
	print LABEL "ORS  ".uc( $edxAccount )."\n";   # Institution id.
	print LABEL "FDI  ".uc( $projectId )."\n"; # project code number.
	close( LABEL );
	logit( "created LABEL file '$labelFileName'" );
}
