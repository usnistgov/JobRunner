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
MMisc::ok_quit("\n$usage\n") if (scalar @ARGV == 0);

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
my $executable = undef;
my $rlogfile = "";
my $outconf = "";
my $dirchange = "";
my @runiftrue = ();

# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz  #
# Used:   C        L  O  R   V     bcde  h   l no  rs uv      #

my @cc = ();
&process_options();

if (! MMisc::is_blank($dirchange)) {
  my $err = MMisc::check_dir_r($dirchange);
  MMisc::error_quit("Problem with \'dirChange\' directory ($dirchange): $err")
    if (! MMisc::is_blank($err));
  chdir($dirchange);
  MMisc::warn_print("Current directory changed to \'$dirchange\'");
}

# Remaining of command line is the command to start
MMisc::error_quit("\'executable\' and command line can not be used at the same time")
  if ((defined $executable) && (scalar @ARGV > 0));
MMisc::error_quit("Neither \'executable\', nor command line are specified, and we are not in \'OnlyCheck\' mode")
  if ((! defined $executable) && (scalar @ARGV == 0) && (! $onlycheck));

if (defined $executable) {
  my $err = MMisc::check_file_x($executable);
  MMisc::error_quit("Problem with \'executable\' ($executable): $err")
    if (! MMisc::is_blank($err));
}

foreach my $rit (@runiftrue) {
  my $err = MMisc::check_file_x($rit);
  MMisc::error_quit("Problem with \'RunIfTrue\' executable ($rit): $err")
    if (! MMisc::is_blank($err));
}


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
      if ($lockdir =~ m%$tmp$%i);
  push @all, "$lockdir$tmp";
}
my ($dsDone, $dsSkip, $dsBad, $dsRun) = @all;
#print "[+] ", join("\n[+] ", @all), "\n";

my $blogfile = "logfile";

foreach my $file (@checkfiles) {
  my $err = MMisc::check_file_r($file);
  MMisc::error_quit("Problem with \'checkfiles\' [$file] : $err")
      if (! MMisc::is_blank($err));
}

if (! MMisc::is_blank($outconf)) {
  push @cc, @ARGV;
  MMisc::error_quit("Problem writing configuration file ($outconf)")
    if (! MMisc::dump_memory_object($outconf, "", \@cc,
                                    "# Job Runner Configuration file\n\n",
                                    undef, 0));
  MMisc::ok_quit("Wrote \'saveConfig\' file ($outconf)");
}

my $toprint2 = (! MMisc::is_blank($toprint)) ? "$toprint -- " : ""; 

my @mulcheck = ();
foreach my $tmpld (@all) {
  push(@mulcheck, $tmpld)
    if (MMisc::does_dir_exists($tmpld));
}
MMisc::error_quit("${toprint2}Can not run program, lockdir already exists in multiple states:\n - " . join("\n - ", @mulcheck))
  if (scalar @mulcheck > 1);
#print "[*] ", join("\n[*] ", @mulcheck), "\n";


##########
## Skip ?
MMisc::ok_quit("${toprint2}Skip requested")
  if (MMisc::does_dir_exists($dsSkip));



##########
## Previously bad ?
if (MMisc::does_dir_exists($dsBad)) {
  MMisc::ok_quit("${toprint2}Previous bad run present, skipping")
      if (! $redobad);

  vprint("!! Deleting previous run lockdir [$dsBad]");
  
  `rm -rf $dsBad`;
  MMisc::error_quit("${toprint2}Problem deleting \'bad\' lockdir [$dsBad], still present ?")
      if (MMisc::does_dir_exists($dsBad));
}



##########
## Previously done ?
if (MMisc::does_dir_exists($dsDone)) {
  MMisc::ok_quit("${toprint2}Previously succesfully completed")
    if (scalar @checkfiles == 0);
  
  my $flf = (MMisc::is_blank($rlogfile)) ? "$dsDone/$blogfile" : $rlogfile;
  
  if (MMisc::does_file_exists($flf)) {
    MMisc::ok_quit("${toprint2}Previously succesfully completed, and no files listed in \'checkfiles\' is newer than the logfile, not re-runing")
      if (MMisc::newest($flf, @checkfiles) eq $flf);
    vprint("!! ${toprint2}Previously succesfully completed, but at least one file listed in \'checkfiles\' is newer than the logfile => re-runing");
  } else {
    vprint("!! ${toprint2}Previously succesfully completed, but logfile absent => considering as new run");
  }
  
  vprint("!! Deleting previous run lockdir [$dsDone]");
  `rm -rf $dsDone`;
  MMisc::error_quit("${toprint2}Problem deleting lockdir [$dsDone], still present ?")
    if (MMisc::does_dir_exists($dsDone));
}



##########
## Already in progress ?
MMisc::ok_quit("${toprint2}Run already in progress, Skipping")
  if (MMisc::does_dir_exists($dsRun));

##########
# Actual run
&check_RunIfTrue();

if ($onlycheck) {
  vprint("${toprint2}Would actually have to run tool, exiting with expected return code ($onlycheck_rc)\n");
  exit($onlycheck_rc);
}

vprint("%% In progress: $toprint\n");

# In case the user use Ctrl+C do not return "ok"
sub SIGINTh { MMisc::error_quit("\'Ctrl+C\'-ed, exiting with error status"); }
$SIG{'INT'} = 'SIGINTh';

vprint("++ Creating \"In Progress\" lock dir");
#MMisc::error_quit("[$dsRun]");
MMisc::error_quit("${toprint2}Could not create writable dir ($dsRun)")
  if (! MMisc::make_wdir($dsRun));
my $flf = (MMisc::is_blank($rlogfile)) ? "$dsRun/$blogfile" : $rlogfile;

foreach my $ddir (@destdir) {
  MMisc::error_quit("${toprint2}Could not create requested \'CreateDir\' dir ($ddir)")
    if (! MMisc::make_wdir($ddir));
}

my ($rv, $tx, $so, $se, $retcode, $flogfile)
  = MMisc::write_syscall_logfile
  ($flf, (defined $executable) ? $executable : @ARGV);
vprint("-- Final Logfile different from expected one: $flogfile")
  if ($flogfile ne $flf);

if ($retcode == 0) {
  &rod($dsRun, $dsDone); # Move to "ok" status
  MMisc::ok_quit("${toprint2}Run succesfully completed");
}

## If we are here, it means it was a BAD run
&rod($dsRun, $dsBad); # Move to "bad" status
$flogfile =~ s%$dsRun%$dsBad%;
&error_quit($retcode, "${toprint2}Error during run, see logfile ($flogfile)");

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

  MMisc::error_quit("${toprint2}Could not rename [$e1] to [$e2] : $!")
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

####################

sub check_RunIfTrue {
  return() if (scalar @runiftrue == 0);

  foreach my $rit (@runiftrue) {
    my ($rc, $so, $se) = MMisc::do_system_call($rit);
    if ($rc == 0) {
      vprint("== \'RunIfTrue\' check OK ($rit)");
    } else {
      vprint("== \'RunIfTrue\' check FAILED ($rit)\n stdout:$so\n stderr:$se");
      MMisc::ok_quit("${toprint2} \'RunIfTrue\' check did not succeed ($rit), will not run job, but exiting with success return code");
    }
  }
}

########################################

sub _cc1 { push @cc, "--" . $_[0]; }
sub _cc2 { push @cc, "--" . $_[0]; push @cc, $_[1]; } 

#####

sub process_options {
  my %opt = ();

  GetOptions
    (
     \%opt,
     'help',
     'version',
     'lockdir=s'   => sub {$blockdir = $_[1]; &_cc2(@_);},
     'checkfile=s' => sub {push @checkfiles, $_[1]; &_cc2(@_);},
     'name=s'      => sub {$toprint = $_[1]; &_cc2(@_)},
     'Verbose'     => sub {$verb++; &_cc1(@_);},
     'badErase'    => sub {$redobad++; &_cc1(@_);},
     'okquit'      => sub {$okquit++; &_cc1(@_);},
     'CreateDir=s' => sub {push @destdir, $_[1]; &_cc2(@_);},
     'OnlyCheck'   => \$onlycheck,
     'executable=s' => sub {$executable = $_[1]; &_cc2(@_);},
     'LogFile=s'   => sub {$rlogfile = $_[1]; &_cc2(@_);},
     'saveConfig=s' => \$outconf,
     'useConfig=s'  => sub {&load_options($_[1]);},
     'dirChange=s'  => sub {$dirchange = $_[1]; &_cc2(@_);},
     'RunIfTrue=s'  => sub {push @runiftrue, $_[1]; &_cc2(@_);},
    ) or MMisc::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");
  MMisc::ok_quit("\n$usage\n") if ($opt{'help'});
  MMisc::ok_quit("$versionid\n") if ($opt{'version'});
}

#####

sub load_options {
  my ($conf) = @_;

  my $err = MMisc::check_file_r($conf);
  MMisc::error_quit("Problem with \'useConfig\' file ($conf): $err")
    if (! MMisc::is_blank($err));

  my $tmp = undef;
  $tmp = MMisc::load_memory_object($conf);
  MMisc::error_quit("Problem with configuration file data ($conf)")
    if (! defined $tmp);
  push @ARGV, @$tmp;
}

#####

sub set_usage {  
  my $tmp=<<EOF
$versionid

$0 [--help | --version] [--Verbose] [--okquit] [--Onlycheck] [--dirChange dir] --lockdir dir --name text [--checkfile file [--checkfile file [...]]] [--badErase]  [--CreateDir dir [--CreateDir dir [...]]] [--RunIfTrue executable [--RunIfTrue executable]] [--LogFile file] [[--executable file] | [ -- command_line_to_run]] [--saveConfig file | --useConfig file]

Will execute 'executable' or command_line_to_run if it can be run (not already in progress, completed, bad)

Where:
  --help     This help message
  --version  Version information
  --Verbose  Print more verbose status updates
  --Onlycheck  Do the entire check list but before doing the actual run, exit with a return code value of \"$onlycheck_rc\" (reminder: 1 means that there was an issue, 0 means that the program exited succesfuly, ie in this case a previous run completed -- it can still be a bad run, use \'--badErase\' to insure redoing those)
  --dirChange  Before doing anything else, change to the specified directory (ie relative path provided have to be from that directory)
  --okquit   In case the command line to run return a bad status, return the "ok" (exit code 0) status, otherwise return the actual command return code (note that this only applies to the command run, all other issues will return the error exit code)
  --lockdir  base lock directory in which is stored the commandline and logfile
  --name     name (converted adapted) to the base lock directory
  --checkfile  check file when a succesful run is present to decide if a re-run is necessary, comparing date of files to that of logfile
  --badErase   If a bad run is present, erase run and retry
  --CreateDir  Before (and only if) running the command line to run, create the required directory
  --RunIfTrue  Check that given program (no arguments accepted) returns true (0 exit status) to run job, otherwise do not run job (will still be available for later rerun)
  --LogFile   Override the default location of the log file (inside the lock directory)
  --executable  executable file to run
  --saveConfig  Do not run anything, instead save the command line options needed to run that specific JobRunner job into a specified configuration file that can be loaded in another JobRunner call using \'--useConfig\'
  --useConfig   Use one (and only one) JobRunner configuration files generated by \'--saveConfig\'. To run on multiple files, use \'JobRunner_Caller\'.
EOF
;

  return($tmp);
}
