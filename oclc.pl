#!/usr/bin/perl -w
########################################################################
# Purpose: Upload bibliographic records from EPL to OCLC.
# Method:  EPL's catalog MARC records are uploaded monthly to OCLC for 
#          the purposes of searching and other InterLibrary Loans (ILL).
#
# Steps (each explained later):
# 1.  Contact FTP address ftp.edx.oclc.org.
# 2.  Login with user name: TCNEDM1
# 3.  Type password.
# 3a. Change password. Do this with each upload.
# 4.  Change directory to 'EDX.EBSB.CNEDM.FTP'.
# 5.  Set transfer mode to binary.
# 6.  Put  DATA.D120623.aa
# 7.  Put LABEL.D120623.aa
# 8.  Repeat over all split files.
# 9.  Exit gracefully.
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
use Net::FTP;

# Prints usage message then exits.
# param:
# return:
sub usage
{
    print STDERR << "EOF";

Uploads bibliographic records to OCLC.

usage: $0 [-aADx] [-s file] [-f files]

 -a [file]     : Run the API commands to generate the catalog dump.
                 This will do a complete dump.
 -A            : Do everything: run api catalog dump, split to default size
                 files and upload the split files and labels. Same as running
			     -a -f 
 -d [start,end]: Comma separated start and end date. Restricts search for items by create and 
                 modify dates. Defaults to one month ago as specified by 'transdate -m-1' and 
				 today's date for an end date. Both are optional but must be valid ANSI dates or
				 the defaults are used.
 -D            : Debug
 -f [files]    : FTP files to OCLC at default FTP URL. Predicated on 
                 files existing in the OCLC directory.
 -s [file]     : Split input into maximum number of records per DATA file
                 (90000).
 -x            : this (help) message

example: $0 -s catalog_dump.lst
         $0 -f "file1 label1 file2 label2"
         $0 -a
         $0 -A
EOF
    exit;
}

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
	my $newPassword;
	open(PASSWORD, "<$path") or die "error: getPassword($path) failed: $!\n";
	my @lines = <PASSWORD>;
	close(PASSWORD);
	die "error: password file must contain the password as the first line.\n" if (! @lines or $lines[0] eq "");
	$newPassword = $lines[0];
	chomp($newPassword);
	if (defined($isNewPasswordRequest))
	{
		my @passwdChars = split('', $newPassword);
		++$passwdChars[$#passwdChars];
		$newPassword = join('',@passwdChars);
		warn "error: getPassword($path) failed to remove old password file: $!\n" if (! unlink($path));
		# this will allow the user to get a new password even if there was a problem removing the old file
		# or saving to a new file.
		open(PASSWORD, ">$path") or print "error: getPassword($path) failed: $!, the new password is $newPassword\n";
		print PASSWORD "$newPassword\n";
		close(PASSWORD);
	}
	return $newPassword;
}

##### Server side parameters
my $edxAccount  = qq{cnedm};
my $userName    = "t".$edxAccount."1";      # User name.
my $ftpUrl      = qq{edx.oclc.org};
my $ftpDir      = qq{edx.ebsb.$edxAccount.ftp};
##### Client side parameters
my $maxRecords  = 90000;            # Max number records we can upload at a time, use -s to change.
my $date        = getTimeStamp;     # current date in ascii.
my $oclcDir     = qq{/s/sirsi/Unicorn/EPLwork/OCLC};
my $passwordPath= "$oclcDir/password.txt";
my $logDir      = $oclcDir;
my $logFile     = "$logDir/oclc$date.log";  # Name and location of the log file.
open LOG, ">>$logFile";
# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'AaDf:xs:d:';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ($opt{'x'});
}
init();

# If the user specified a specific file to split. It will split
# ANY text file into 90000 line files.
if ($opt{'A'})
{
	print "-A selected do everything.\n" if ($opt{'D'});
	exit 1;
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
	return ">$startDate<$endDate";
}

# make a dump of the catalog.
if ($opt{'a'})
{
	my $logfilename        = qq{oclc.log};
	my $initialItemCatKeys = qq{tmp_a};
	my $sortedItemCatKeys  = qq{tmp_b};
	my $dateRefinedCatKeys = qq{tmp_c};
	my $sortedDatedCatKeys = qq{tmp_d};
	print "-a selected -run API.\n" if ($opt{'D'});
	# my $unicornItemTypes = "PAPERBACK,JPAPERBACK,BKCLUBKIT,COMIC,DAISYRD,EQUIPMENT,E-RESOURCE,FLICKSTOGO,FLICKTUNE,JFLICKTUNE,JTUNESTOGO,PAMPHLET,RFIDSCANNR,TUNESTOGO,JFLICKTOGO,PROGRAMKIT,LAPTOP,BESTSELLER,JBESTSELLR";
	my $unicornItemTypes = "PAPERBACK";
	my $unicornLocations = "BARCGRAVE,CANC_ORDER,DISCARD,EPLACQ,EPLBINDERY,EPLCATALOG,EPLILL,INCOMPLETE,LONGOVRDUE,LOST,LOST-ASSUM,LOST-CLAIM,LOST-PAID,MISSING,NON-ORDER,ON-ORDER,BINDERY,CATALOGING,COMICBOOK,INTERNET,PAMPHLET,DAMAGE,UNKNOWN,REF-ORDER,BESTSELLER,JBESTSELLR,STOLEN";
	print "$unicornItemTypes\n" if ($opt{'D'});
	# gets all the keys of items that don't match the location list or item type lists.
	print "selecting initial catalogue keys...\n";
	# `selitem -t~$unicornItemTypes -l~$unicornLocations -oC >$initialItemCatKeys`;
	open( INITIAL_CAT_KEYS, "<$initialItemCatKeys" ) or die "No items found.\n";
	print "sorting initial catalogue key selection...\n";
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
	print "refining item selection based on '$dateBoundaries'...\n";
	print "$dateBoundaries\n" if ( $opt{'D'} );
	# select all catalog keys for items that were either modified or created between the dates selected.
	print "create date criteria...\n";
	`cat $sortedItemCatKeys | selcatalog -iC -oC -p"$dateBoundaries" > $dateRefinedCatKeys 2>>$logfilename`;
	print "modified date criteria...\n";
	`cat $sortedItemCatKeys | selcatalog -iC -oC -r"$dateBoundaries" >>$dateRefinedCatKeys 2>>$logfilename`;
	# cat $dateRefinedCatKeys | sort | uniq > tmp_initialcatkeys_sorted
	print "sorting date refined catalogue key selection...\n";
	open( DATED_CAT_KEYS, "<$dateRefinedCatKeys" ) or die "No items found refined by date: $!\n";
	my %dateRefinedKeys;
	while (<DATED_CAT_KEYS>)
	{
		chop $_; # remove new line for numeric sort
		chop $_; # remove pipe for numeric sort
		$dateRefinedKeys{$_} = 1;
	}
	close( DATED_CAT_KEYS );
	open( SORTED_DATED_CAT_KEYS, ">$sortedDatedCatKeys" ) or die "Error opening file to write sorted, date refined CAT keys, $!\n";
	foreach my $finalKey (sort {$a <=> $b} keys(%dateRefinedKeys))
	{
		print SORTED_DATED_CAT_KEYS $finalKey."|\n";
	}
	close( SORTED_DATED_CAT_KEYS );
	if ( not $opt{'D'} )
	{
		unlink( $tmp_a );
		unlink( $tmp_b );
		unlink( $tmp_c );
		# next do a catalog dump to do tomorrow.
		# unlink( $tmp_d ); # so far this contains the final results.
	}
	print "...done.\n";
	exit;
}


# split a given file into parts.
if ($opt{'s'})
{
	print "-s selected -split file $opt{s}.\n" if ($opt{'D'});
	my @lines;
	open(STDIN, "<$opt{'s'}") or die " error reading '".$opt{'s'}."': $!\n";
	@lines = <>;
	close(STDIN);
	print     getTimeStamp(1)." read ".@lines." lines read, using file size: $maxRecords\n";
	print LOG getTimeStamp(1)." read ".@lines." lines read, using file size: $maxRecords\n";
	# Stores the file name (complete path) as a key to the number of items in the file.
	my $fileCounts = splitFile($oclcDir, $maxRecords, $date, @lines);
	# now create the LABEL files
	foreach my $fileName (keys %$fileCounts)
	{
		createLabelFile($fileName, $fileCounts->{$fileName});
	}
}
# FTP the files.
if ($opt{'f'})
{
	print "-f selected -ftp files: '$opt{f}'\n" if ($opt{'D'});
	my @ftpList = split(' ', $opt{'f'});
	exit 1 if (! @ftpList);
	my $password = getPassword($passwordPath);
	print LOG getTimeStamp(1)." password read.\n";
	foreach my $file (@ftpList)
	{
		print "$file\n";#ftp($ftpUrl, $ftpDir, $userName, $password, @files);
	}
	print "$password\n";
	#ftp($ftpUrl, $ftpDir, $userName, $password, @files);
	ftp("ftp.epl.ca", "atest", "mark", "R2GnBVtt", "./test.j");
	# ftp("ftp.epl.cb", "atest", "mark", "R2GnBVtt", "./test.j"); #fail
	# ftp("ftp.epl.ca", "btest", "mark", "R2GnBVtt", "./test.j"); #fail
	# ftp("ftp.epl.ca", "atest", "amark", "R2GnBVtt", "./test.j"); #fail
	# ftp("ftp.epl.ca", "atest", "mark", "aR2GnBVtt", "./test.j"); #fail
	# ftp("ftp.epl.ca", "atest", "mark", "R2GnBVtt", "./test.a"); #fail
}

close(LOG);
1; # exit with successful status.

# ======================== Functions =========================

#
#
#
sub ftp
{
	my ($host, $directory, $userName, $password, @fileList) = @_;
	my $newError = 0;
	my $ftp = Net::FTP->new($host, Timeout=>240) or die "can't ftp to $host: $!\n";
	print "connected to $host\n";
	$ftp->login($userName, $password) or $newError = 1;
	if ($newError)
	{
		print LOG getTimeStamp(1)."Can't login to $host: $!\n";
		$ftp->quit;
	}
	print "logged in\n";
	$ftp->cwd($directory) or $newError = 1; 
	if ($newError)
	{
		print LOG getTimeStamp(1)."can't change to $directory on $host: $!\n";
		$ftp->quit;
	}
	$ftp->binary;
	foreach my $localFile (@fileList)
	{
		# locally we use the fully qualified path but
		# remotely we just put the file in the directory.
		my ($remoteFile, $directories, $suffix) = fileparse($localFile);
		print "...putting: $remoteFile\n";
		$ftp->put($localFile, $remoteFile) or $newError = 1;
		if ($newError)
		{
			print LOG getTimeStamp(1)."ftp->put: failed to upload $localFile to $host: $!\n";
			$ftp->quit;
		}
		print LOG getTimeStamp(1)."ftp->put: uploaded $localFile to $host\n";
	}
	$ftp->quit;
}

# Takes the list and splits it into 'n' sized record files, creating
# the LABEL files as it goes.
# param:  maxRecords
# param:  filePath string of path to file.
# param:  fileSizes hash of file name to size of record.
# return: hash reference of fileSizes.
sub splitFile
{
	my ($dir, $maxRecords, $date, @lines) = @_;
	my $fileSizeRef;
	my $lineCount      = 0;
	my $totalLineCount = 0;
	my $suffix         = "aa";
	my $filePath       = qq{$dir/DATA.D$date.$suffix}; # DATA.D120623.aa
	open OUT, ">$filePath" || die "error opening '$filePath': $!\n";
	print     getTimeStamp(1)." creating DATA file: '$filePath'\n";
	print LOG getTimeStamp(1)." creating DATA file: '$filePath'\n";
	foreach my $line (@lines)
	{
		chomp($line);
		$lineCount++;
		print OUT "$line\n";
		# The or statement is for the case where the last file has less than
		# the maximum number of allowed records, we need the count from that
		# file as well.
		if ($lineCount >= $maxRecords or $totalLineCount + $lineCount == @lines)
		{
			close(OUT);
			# Save the file count for making LABEL files.
			$fileSizeRef->{ $filePath } = $lineCount;
			$totalLineCount += $lineCount;
			# If there are more records, make a new file for them. To not check leaves
			# one empty file left over.
			if ($totalLineCount < @lines)
			{
				# Increment the file extension.
				$suffix = ++$suffix;
				# Create a new file name and path.
				$filePath = qq{$dir/DATA.D$date.$suffix};
				$lineCount = 0;
				open OUT, ">".$filePath or die "error opening '$filePath': $!\n";
				print     getTimeStamp(1)." creating DATA file: '$filePath'\n";
				print LOG getTimeStamp(1)." creating DATA file: '$filePath'\n";
			}
		}
	}
	close(OUT);
	if ($opt{'d'})
	{
		print "===there are ".keys(%$fileSizeRef)." keys\n";
		while ( my ($key, $value) = each(%$fileSizeRef) ) 
		{
			print "===$key => $value\n";
		}
	}
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
# param:  dataFileName string name of the data file the label is for.
# param:  numRecords integer number of records in the file.
# return: string name of the label file.
sub createLabelFile
{
	my ($dataFileName, $numRecords) = @_;
	my ($fileName, $directory, $suffix) = fileparse($dataFileName);
	my $labelFileName = $directory.qq{LABEL}.substr($fileName, 4);
	if ($opt{'d'})
	{
		print "LABEL: '$labelFileName'\n";
	}
	open LABEL, ">$labelFileName" or die "error couldn't create label file $fileName: $!\n";
	print LABEL "DAT  ".getTimeStamp(0)."000000.0\n"; # TODO finish me.
	print LABEL "RBF  $numRecords\n"; # like: 88947
	print LABEL "DSN  $fileName\n"; # DATA.D110405
	print LABEL "ORS  CNEDM\n";
	print LABEL "FDI  P012569\n";
	close LABEL;
	print     getTimeStamp(1)." creating LABEL file: '$labelFileName'\n";
	print LOG getTimeStamp(1)." creating LABEL file: '$labelFileName'\n";
	return $labelFileName;
}
