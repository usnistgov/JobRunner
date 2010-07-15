#!/usr/bin/env perl
# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs

# Job Runner
#
# Author(s): Martial Michel
#
# This software was developed at the National Institute of Standards and Technology by
# employees and/or contractors of the Federal Government in the course of their official duties.
# Pursuant to Title 17 Section 105 of the United States Code this software is not subject to 
# copyright protection within the United States and is in the public domain.
#
# "JobRunner" is an experimental system.
# NIST assumes no responsibility whatsoever for its use by any party.
#
# THIS SOFTWARE IS PROVIDED "AS IS."  With regard to this software, NIST MAKES NO EXPRESS
# OR IMPLIED WARRANTY AS TO ANY MATTER WHATSOEVER, INCLUDING MERCHANTABILITY,
# OR FITNESS FOR A PARTICULAR PURPOSE.

use strict;

# Note: Designed for UNIX style environments (ie use cygwin under Windows).

##########
# Version

# $Id$
my $version     = "0.1b";

if ($version =~ m/b$/) {
  (my $cvs_version = '$Revision$') =~ s/[^\d\.]//g;
  $version = "$version (CVS: $cvs_version)";
}

my $versionid = "Job Runner Version: $version";

##########
# Check we have every module (perl wise)

my ($f4b, @f4bv);
BEGIN {
  $f4b = "F4DE_BASE";
  push @f4bv, (exists $ENV{$f4b}) 
    ? ($ENV{$f4b} . "/lib") 
      : ("../../../common/lib");
}
use lib (@f4bv);

sub eo2pe {
  my $oe = join(" ", @_);
  return( ($oe !~ m%^Can\'t\s+locate%) ? "\n----- Original Error:\n $oe\n-----" : "");
}

## Then try to load everything
my $have_everything = 1;
my $partofthistool = "It should have been part of this tools' files. Please check your $f4b environment variable.";
my $warn_msg = "";
sub _warn_add { $warn_msg .= "[Warning] " . join(" ", @_) ."\n"; }

# Part of this tool
foreach my $pn ("MMisc") {
  unless (eval "use $pn; 1") {
    my $pe = &eo2pe($@);
    &_warn_add("\"$pn\" is not available in your Perl installation. ", $partofthistool, $pe);
    $have_everything = 0;
  }
}

# usualy part of the Perl Core
foreach my $pn ("Getopt::Long") {
  unless (eval "use $pn; 1") {
    &_warn_add("\"$pn\" is not available on your Perl installation. ", "Please look it up on CPAN [http://search.cpan.org/]\n");
    $have_everything = 0;
  }
}

# Something missing ? Abort
if (! $have_everything) {
  print "\n$warn_msg\nERROR: Some Perl Modules are missing, aborting\n";
  exit(1);
}

# Use the long mode of Getopt
Getopt::Long::Configure(qw(auto_abbrev no_ignore_case));

########################################
# Options processing

my $onlycheck_rc = 2;
my $usage = &set_usage();

# Default values for variables
# none here

my $blockdir = "";
my @checkfiles = ();
my $toprint = "";
my $verb = 0;
my $redobad = 0;
my $okquit = 0;
my @destdir = ();
my $onlycheck = 0;

# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz  #
# Used:   C           O      V     bc    h   l no      v      #

my %opt = ();
GetOptions
  (
   \%opt,
   'help',
   'version',
   'lockdir=s'   => \$blockdir,
   'checkfile=s' => \@checkfiles,
   'name=s'      => \$toprint,
   'Verbose'     => \$verb,
   'badErase'    => \$redobad,
   'okquit'      => \$okquit,
   'CreateDir=s' => \@destdir,
   'OnlyCheck'   => \$onlycheck,
  ) or MMisc::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");
MMisc::ok_quit("\n$usage\n") if ($opt{'help'});
MMisc::ok_quit("\n$usage\n") if ((! $onlycheck) && (scalar @ARGV == 0));
MMisc::ok_quit("$versionid\n") if ($opt{'version'});
# Remaining of command line is the command to start

$blockdir =~ s%\/$%%; # remove trailing /
MMisc::error_quit("No \'lockdir\' specified, aborting")
  if (MMisc::is_blank($blockdir));

my $name = &adapt_name($toprint);
MMisc::error_quit("No \'name\' specified, aborting")
  if (MMisc::is_blank($name));

my $err = MMisc::check_dir_w($blockdir);
MMisc::error_quit("Problem with \'lockdir\' : $err")
  if (! MMisc::is_blank($err));

my $lockdir = "$blockdir/$name";
MMisc::error_quit("The lockdir directory ($lockdir) must not exist to use this tool")
  if (MMisc::does_dir_exists($lockdir));

my @dir_end = ("done", "skip", "bad", "inprogress");
my $ds_sep  = "_____";
my @all = ();
foreach my $end (@dir_end) {
  my $tmp = "${ds_sep}$end";
  MMisc::error_quit("Requested lockdir can not end in \'$tmp\' ($lockdir)")
      if ($lockdir =~ m%$end$%i);
  push @all, "$lockdir$tmp";
}
my ($dsDone, $dsSkip, $dsBad, $dsRun) = @all;

my $logfile = "logfile";

foreach my $file (@checkfiles) {
  my $err = MMisc::check_file_r($file);
  MMisc::error_quit("Problem with \'checkfiles\' [$file] : $err")
      if (! MMisc::is_blank($err));
}

if (! MMisc::is_blank($toprint)) {
  vprint("%% In progress: $toprint\n");
  $toprint = "$toprint -- "; # convert to print ready
}

my @mulcheck = ();
foreach my $tmpld (qw/$dsDone $dsSkip $dsBad $dsRun/) {
  push @mulcheck, $tmpld
    if (MMisc::does_dir_exists($tmpld));
}
MMisc::error_quit("${toprint}Can not run program, lockdir already exists in multiple states:\n - " . join("\n - ", @mulcheck))
  if (scalar @mulcheck > 1);


##########
## Skip ?
MMisc::ok_quit("${toprint}Skip requested")
  if (MMisc::does_dir_exists($dsSkip));



##########
## Previously bad ?
if (MMisc::does_dir_exists($dsBad)) {
  MMisc::ok_quit("${toprint}Previous bad run present, skipping")
      if (! $redobad);

  vprint("!! Deleting previous run lockdir [$dsBad]");
  
  `rm -rf $dsBad`;
  MMisc::error_quit("${toprint}Problem deleting \'bad\' lockdir [$dsBad], still present ?")
      if (MMisc::does_dir_exists($dsBad));
}



##########
## Previously done ?
if (MMisc::does_dir_exists($dsDone)) {
  MMisc::ok_quit("${toprint}Previously succesfully completed")
      if (scalar @checkfiles == 0);

  my $flf = "$dsDone/$logfile";
  if (MMisc::does_file_exists($flf)) {
    MMisc::ok_quit("${toprint}Previously succesfully completed, and no files listed in \'checkfiles\' is newer than the logfile, not re-runing")
        if (MMisc::newest($flf, @checkfiles) eq $flf);
    vprint("!! ${toprint}Previously succesfully completed, but at least one file listed in \'checkfiles\' is newer than the logfile => re-runing");
  } else {
    vprint("!! ${toprint}Previously succesfully completed, but logfile absent => considering as new run");
  }
  
  vprint("!! Deleting previous run lockdir [$dsDone]");
  `rm -rf $dsDone`;
  MMisc::error_quit("${toprint}Problem deleting lockdir [$dsDone], still present ?")
      if (MMisc::does_dir_exists($dsDone));
}



##########
## Already in progress ?
MMisc::ok_quit("${toprint}Run already in progress, Skipping")
  if (MMisc::does_dir_exists($dsRun));

##########
# Actual run
if ($onlycheck) {
  vprint("${toprint}Would actually have to run tool, exiting with expected return code ($onlycheck_rc)\n");
  exit($onlycheck_rc);
}

vprint("++ Creating \"In Progress\" lock dir");
MMisc::error_quit("${toprint}Could not create writable dir ($dsRun)")
  if (! MMisc::make_wdir($dsRun));
my $flf = "$dsRun/$logfile";

foreach my $ddir (@destdir) {
  MMisc::error_quit("${toprint}Could not create requested \'CreateDir\' dir ($ddir)")
    if (! MMisc::make_wdir($ddir));
}

my ($rv, $tx, $so, $se, $retcode, $flogfile)
  = MMisc::write_syscall_smart_logfile($flf, @ARGV);
vprint("-- Final Logfile different from expected one: $flogfile")
  if ($flogfile ne $flf);

if ($retcode == 0) {
  &rod($dsRun, $dsDone); # Move to "ok" status
  MMisc::ok_quit("${toprint}Run succesfully completed");
}

## If we are here, it means it was a BAD run
&rod($dsRun, $dsBad); # Move to "bad" status
$flogfile =~ s%$dsRun%$dsBad%;
&error_quit($retcode, "${toprint}Error during run, see logfile ($flogfile)");

########################################

sub adapt_name {
  my $tmp = $_[0];
  $tmp =~ s%^\s+%%;
  $tmp =~ s%\s+$%%;
  $tmp =~ s%[^a-z0-9-_]%_%ig;
  return($tmp);
}

#####

sub rod { # rename or die
  my ($e1, $e2) = @_;

  MMisc::error_quit("${toprint}Could not rename [$e1] to [$e2] : $!")
    if (! rename($e1, $e2));
}

##########

sub vprint {
  return if (! $verb);
  print join("", @_), "\n";
}

#####

sub error_quit {
  my $ec = shift @_;
  print('[ERROR] ', join(' ', @_), "\n");
  exit(0) if ($okquit);
  exit($ec);
}

########################################

sub set_usage {  
  my $tmp=<<EOF
$versionid

$0 [--help | --version] [--Verbose] [--okquit] [--Onlycheck] --lockdir dir --name text [--checkfile file [--checkfile file [...]]] [--badErase]  [--CreateDir dir [--CreateDir dir [...]]] -- command_line_to_run

Will execute command_line_to_run if it can be run (not already in progress, completed, bad)

Where:
  --help     This help message
  --version  Version information
  --Verbose  Print more verbose status updates
  --Onlycheck  Do the entire check list but before doing the actual run, exit with a return code value of \"$onlycheck_rc\" (reminder: 1 means that there was an issue, 0 means that the program exited succesfuly, ie in this case a previous run completed -- it can still be a bad run, use \'--badErase\' to insure redoing those)
  --okquit   In case the command line to run return a bad status, return the "ok" (exit code 0) status, otherwise return the actual command return code (note that this only applies to the command run, all other issues will return the error exit code)
  --lockdir  base lock directory in which is stored the commandline and logfile
  --name     name (converted adapted) to the base lock directory
  --checkfile  check file when a succesful run is present to decide if a re-run is necessary, comparing date of files to that of logfile
  --badErase   If a bad run is present, erase run and retry
  --CreateDir  Before (and only if) running the command line to run, create the required directory
EOF
;

  return($tmp);
}
