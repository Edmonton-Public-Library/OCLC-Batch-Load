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
# use File::Basename;
use Net::FTP;

# Prints usage message then exits.
# param:
# return:
sub usage
{
    print STDERR << "EOF";

Uploads bibliographic records to OCLC.

usage: $0 [-aADx] [-s file] [-f files]

 -a [file] : Run the API commands to generate the catalog dump.
             This will do a complete dump.
 -A        : Do everything: run api catalog dump, split to default size
             files and upload the split files and labels. Same as running
			 -a -f 
 -D        : Debug
 -f [files]: FTP files to OCLC at default FTP URL. Predicated on 
             files existing in the OCLC directory.
 -s [file] : Split input into maximum number of records per DATA file
            (90000).
 -x        : this (help) message

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

my $userName    = qq{TCNEDM1};      # User name.
my $ftpUrl;
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
    my $opt_string = 'AaDf:xs:';
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

# make a dump of the catalog.
if ($opt{'a'})
{
	print "-a selected -run API.\n" if ($opt{'D'});
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
	my $password = getPassword($passwordPath, 1);
	print     getTimeStamp(1)." password read.\n";
	print LOG getTimeStamp(1)." password read.\n";
	foreach my $file (@ftpList)
	{
		print "$file\n";#ftp($userName, $password, $url, $file);
	}
	print "$password\n";
}

close(LOG);
1; # exit with successful status.

# ======================== Functions =========================

#
#
#
sub ftp
{
	my ($host, $dir, $userName, $password, @fileList) = @_;
	
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

# Opens the password file reads the old password and computes
# the new password and saves it - clobbering the old name and file.
# param: string path location of password file.
# return: string new password.
sub getNewPassword
{
	return "";
}