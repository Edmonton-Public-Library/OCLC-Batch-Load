#!/usr/bin/perl -w
########################################################################
# Purpose: Upload bibliographic records from EPL to OCLC.
# Method:  EPL's catalog MARC records are uploaded monthly to OCLC for 
#          the purposes of searching and other InterLibrary Loans (ILL).
#
# Steps (each explained later):
# 1) oclc.pl -a [-d"start,end"]
# 2) oclc.pl -s $defaultCatKeysFile
# 3) oclc.pl -c
# 4) oclc.pl -f
#
# Author:  Andrew Nisbet
# Date:    June 4, 2012
# Rev:     0.0 - develop
########################################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;
use File::Basename;  # Used in ftp() for local and remote file identification.
use POSIX;           # for ceil()

my $VERSION = 0.0;
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
##### Server side parameters
my $edxAccount     = qq{cnedm};
my $userName       = "t".$edxAccount."1";      # User name.
my $ftpUrl         = qq{edx.oclc.org};
my $ftpDir         = qq{edx.ebsb.$edxAccount.ftp};
##### Client side parameters
my $maxRecords     = 16000;            # Max number records we can upload at a time, use -s to change.
my $date           = getTimeStamp;     # current date in ascii.
my $oclcDir        = "."; #qq{/s/sirsi/Unicorn/EPLwork/OCLC};
my $passwordPath   = qq{$oclcDir/password.txt};
my $logDir         = $oclcDir;
my $logFile        = qq{$logDir/oclc$date.log};  # Name and location of the log file.
my $catalogKeys    = qq{catalog_keys.lst}; # master list of catalog keys.
my $APILogfilename = qq{oclcAPI.log};
my $defaultCatKeysFile = qq{cat_keys.lst};
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

usage: $0 [-acADltx] [-s file] [-f files] [-z <n>] [-d"[start_date],[end_date]"]

 -a            : Run the API commands to generate a file of catalog keys called $catalogKeys.
                 If -t is selected, the intermediate temporary files are not deleted.
 -A            : Do everything: run api catalog dump, split to default sized
                 files and upload the split files and labels. Same as running
			     -a -f 
 -c            : Catalog dump the cat keys found in any data files (like DATA.D120829.FILE5) 
                 in the current directory, replacing the contents with the dumped catalog records.
 -D            : Creates deleted items for OCLC upload. Like -A but for deletes. 
 -d [start,end]: Comma separated start and end date. Restricts search for items by create and 
                 modify dates. Defaults to one month ago as specified by 'transdate -m-1' and 
				 today's date for an end date. Both are optional but must be valid ANSI dates or
				 the defaults are used.
 -t            : Debug
 -f            : Finds DATA and matching LABEL files in current directory, and FTPs them to OCLC.
 -lyymmdd.LAST : Create a label file for a given file name. NOTE: use the yymmdd.FILEn, or yymmdd.LAST
                 since $0 needs to count the number of records; the DATA.D MARC file has 1 line.
 -s [file]     : Split input into maximum number of records per DATA file(default 90000).
 -x            : This (help) message.
 -z [int]      : Set the maximum output file size in lines, not bytes, this allows for splitting 
                 a set of catalogue keys into sets of 90000 records, which are then piped to catalogdump.

example: To just split an arbitrary text file into files of 51 lines each: $0 -z51 -s51 file.lst
         Split an arbitrary text file into files of 90000 lines each and create OCLC labels: $0 -sfile.lst -l
         To produce a cat key file for the last 30 days: $0 -a
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
# param:  path string - location of the password file.
# param:  isNewPasswordRequest anyType - pass in a 1 if you want a new password generated
#         The old password is read from file, a new password is generated, the old password
#         file is deleted and the new password is written to the file specified by param: path. 
# return: password string.
sub getPassword
{
	my $path = shift;
	my $isNewPasswordRequest = shift;
	my $oldPassword;
	my $newPassword;
	open( PASSWORD, "<$path" ) or die "error: getPassword($path) failed: $!\n";
	my @lines = <PASSWORD>;
	close( PASSWORD );
	die "error: password file must contain the password as the first line.\n" if (! @lines or $lines[0] eq "");
	$oldPassword = $lines[0];
	chomp( $oldPassword );
	if ( defined( $isNewPasswordRequest ) )
	{
		my @passwdChars = split('', $oldPassword);
		++$passwdChars[$#passwdChars];
		$newPassword = join('',@passwdChars);
		open(PASSWORD, ">$path") or print "error: getPassword($path) failed: $!, the new password is $newPassword\n";
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
sub resetPassword
{
	
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


# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'Aactd:fl:xs:z:';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ($opt{'x'});
	if ( $opt{'z'} )
	{
		$maxRecords = $opt{'z'};
		logit( "maximum file size set to $opt{'z'}" );
	}
	if ( $opt{'l'} ) # expects <yymmdd>.FILEn
	{
		if ( $opt{'l'} =~ m/\d[6]/ )
		{
			logit( "looks like '$opt{'l'}' is not a valid data file name. Exiting" );
			exit( 0 );
		}
		logit( "creating label file for '$opt{'l'}'" );
		# we need $dataFileName, $numRecords so 
		open( DATA, "<$opt{'l'}" ) or die "Error opening '$opt{'l'}': $!\n";
		my $lineCount = 0;
		while(<DATA>)
		{
			$lineCount++;
		}
		close( DATA );
		my ($fileName, $directory, $suffix) = fileparse( $opt{'l'} );
		createOCLCLableFiles( $fileName, $lineCount );
	}
}
init();

# If the user specified a specific file to split. It will split
# ANY text file into 90000 line files.
if ($opt{'A'})
{
	logit( "-A started" ) if ( $opt{'t'} );
	# select the catalog keys.
	selectCatKeys();
	# split the files into the desired number of records each.
	my $date = getTimeStamp(); # get century most significant digits stripped date.
	logit( "reading '$defaultCatKeysFile', using file size: $maxRecords" );
	my $fileCounts = splitFile( $maxRecords, $date, $defaultCatKeysFile );
	logit( "'$defaultCatKeysFile' split into " . keys( %$fileCounts ) . " parts" );
	# create the catalog dump of the keys for each set.
	dumpCatalog( $fileCounts );
	# get the list of files to FTP.
	my @fileList = selectFTPList();
	# FTP the files
	# logit( "ftp successful" ) if ( ftp( $ftpUrl, $ftpDir, $userName, $password, @fileList ) );
	# Test ftp site.
	logit( "ftp successful" ) if ( ftp( "ftp.epl.ca", "atest", "mark", "R2GnBVtt", @fileList ) );
	logit( "-A finished" ) if ( $opt{'t'} );
	exit 1;
}

# Creates and uploads the delete items for OCLC.
if ($opt{'D'})
{
	logit( "-D started" ) if ( $opt{'t'} );
	## Select deleted items from the history log.
	logit( "-D finished" ) if ( $opt{'t'} );
	exit 1;
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
	my @fileList = <[0-9][0-9][0-9][0-9][0-9][0-9]\.*>;
	if ( not @fileList )
	{
		logit( "no data files to catalogdump. Did you forget to create list(s) with -a and -s?" );
		exit( 0 );
	}
	my $fileCountHashRef;
	foreach my $file (@fileList)
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
	my $password = getPassword( $passwordPath );
	logit( "password read from '$passwordPath'" );
	logit( "ftp successful" ) if ( ftp( $ftpUrl, $ftpDir, $userName, $password, @fileList ) );
	# Test ftp site.
	# logit( "ftp successful" ) if ( ftp( "ftp.epl.ca", "atest", "mark", "R2GnBVtt", @fileList ) );
	logit( "-f finished" ) if ( $opt{'t'} );
}

close(LOG);
1; # exit with successful status.

# ======================== Functions =========================

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
	my @dataList = <DATA.D*>;
	my @labelList= <LABEL.D*>;
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
		my $thisDataName = substr( $dataFile, 4 );
		foreach my $labelFile ( @labelList )
		{
			my $thisLabelName = substr( $labelFile, 5 );
			if ( $thisDataName eq $thisLabelName )
			{
				push( @ftpList, $dataFile );
				push( @ftpList, $labelFile );
				logit( "'$dataFile' and '$labelFile' selected" );
			}
		}
	}
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
	# my $APILogfilename        = qq{oclcAPI.log};
	my $initialItemCatKeys = qq{tmp_a};
	my $sortedItemCatKeys  = qq{tmp_b};
	my $dateRefinedCatKeys = qq{tmp_c};
	# my $catalogKeys = qq{catalog_keys.lst}; # master list of catalog keys.
	print "-a selected -run API.\n" if ($opt{'t'});
	my $unicornItemTypes = "PAPERBACK,JPAPERBACK,BKCLUBKIT,COMIC,DAISYRD,EQUIPMENT,E-RESOURCE,FLICKSTOGO,FLICKTUNE,JFLICKTUNE,JTUNESTOGO,PAMPHLET,RFIDSCANNR,TUNESTOGO,JFLICKTOGO,PROGRAMKIT,LAPTOP,BESTSELLER,JBESTSELLR";
	# my $unicornItemTypes = "PAPERBACK";
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
	open( SORTED_DATED_CAT_KEYS, ">$catalogKeys" ) or die "Error opening file to write sorted, date refined CAT keys, $!\n";
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
	logit( "catalogue key selection saved in '$catalogKeys'" );
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
		logit( "dumping catalogue keys found in '$fileName' to 'DATA.D$fileName'" );
        `cat $fileName | catalogdump -om > DATA.D$fileName 2>>$APILogfilename`;
		# create a label for the file.
		createOCLCLableFiles( $fileName, $numRecords );
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
	my $startDate = `transdate -d-30`;
	chomp( $startDate );
	my $endDate   = `transdate -d-0`;
	chomp( $endDate );
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
	open( FTP, "| ftp -n $host\n" ) or die "Error failed to open stream to $host: $!\n";
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
	foreach my $file ( @fileList )
	{
		logit( "putting $file" );
		print FTP "put $file\n";
	}
	print FTP "ls\n";
	print FTP "bye\n";
	logit( "connection closed" );
	close( FTP );
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
		push( @fileNames, qq{$baseName.FILE$i} ); # [120623.FILE1 ...] 120623.LAST, for generic files
		# -c will prepend the correct 'DATA.D' when dumping the catalog records.
	}
	# the last file is always called *.LAST even if there is only one file.
	push( @fileNames, qq{$baseName.LAST} );
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
# param:  dataFileName string - like 120829.FILE1
# param:  recordCount integer - number of records in the file
# return: 
# side effect: creates a label file named LABEL.D<dataFileName>
#### TEST ####
sub createOCLCLableFiles
{
	my ( $dataFileName, $numRecords ) = @_;
	my ($fileName, $directory, $suffix) = fileparse($dataFileName);
	my $labelFileName = $directory.qq{LABEL.D}.$fileName;
	open( LABEL, ">$labelFileName" ) or die "error couldn't create label file '$labelFileName': $!\n";
	print LABEL "DAT  ".getTimeStamp(0)."000000.0\n"; # 14.1 - '0' right fill.
	print LABEL "RBF  $numRecords\n"; # like: 88947
	print LABEL "DSN  DATA.D$fileName\n"; # DATA.D110405.LAST
	print LABEL "ORS  CNEDM\n";
	print LABEL "FDI  P012569\n";
	close( LABEL );
	logit( "created LABEL file '$labelFileName'" );
}
