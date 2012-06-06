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
use File::Basename;

# Prints usage message then exits.
# param:
# return:
sub usage
{
    print STDERR << "EOF";

Uploads bibliographic records to OCLC.

usage: $0 [-xd] [-s integer] [-i input]

 -d        : Debug
 -i <file> : Path to the OCLC files to upload. This allows the
             upload of pre-existing catalog dump, otherwise the default
             is to read from STDIN.
 -s size   : Maximum number of records per DATA file (default 90000).
 -x        : this (help) message

example: $0 -x -i catalog_dump.lst

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

my $USER_NAME   = qq{TCNEDM1};      # User name.
my $PASSWORD;                       # Password for OCLC.
my $maxRecords  = 90000;            # Max number records we can upload at a time, use -s to change.
my $date        = getTimeStamp;     # current date in ascii.
my $listFile;                       # Initial OCLC list file.
my $oclcDir     = qq{/s/sirsi/Unicorn/EPLwork/OCLC};
my $logDir      = $oclcDir;
my $logFile     = "$logDir/oclc$date.log";  # Name and location of the log file.
open LOG, ">>$logFile";
# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'di:xs:';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ($opt{x});
    $maxRecords = $opt{'s'} if ($opt{s});
}
init();
my @lines;
# determine if we are reading from a file or from the command line.
if ($opt{i})
{
	$listFile = $opt{'i'};
	chomp($listFile);
    open(IN, "<$listFile") or die " error reading '$listFile': $!\n";
    @lines = <IN>;
	close(IN);
	print     getTimeStamp(1)." read ".@lines." lines from $listFile, using file size: $maxRecords\n";
	print LOG getTimeStamp(1)." read ".@lines." lines from $listFile, using file size: $maxRecords\n";
}
else
{
    @lines = <STDIN>;
	print     getTimeStamp(1)." read ".@lines." lines from STDIN, using file size: $maxRecords\n";
	print LOG getTimeStamp(1)." read ".@lines." lines from STDIN, using file size: $maxRecords\n";
}


# Stores the file name (complete path) as a key to the number of items in the file.
my $fileCounts = splitFile($oclcDir, $maxRecords, $date, @lines);
# now create the LABEL files
foreach my $fileName (keys %$fileCounts)
{
	createLabelFile($fileName, $fileCounts->{$fileName});
}
close(LOG);
1; # exit with successful status.

# ======================== Functions =========================

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
		print ">>>'$labelFileName'\n";
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

# Opens the password file reads the old password and computes
# the new password and saves it - clobbering the old name and file.
# param: string path location of password file.
# return: string new password.
sub getNewPassword
{
	return "";
}