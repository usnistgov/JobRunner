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

my $sd = "";
BEGIN {
  use Cwd 'abs_path';
  use File::Basename 'dirname';
  $sd = dirname(abs_path($0));
}
use lib ($sd);

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

sub eo2pe {
  my $oe = join(" ", @_);
  return( ($oe !~ m%^Can\'t\s+locate%) ? "\n----- Original Error:\n $oe\n-----" : "");
}

## Then try to load everything
my $have_everything = 1;
my $partofthistool = "It should have been part of this tools' files. ";
my $warn_msg = "";
sub _warn_add { $warn_msg .= "[Warning] " . join(" ", @_) ."\n"; }

# Part of this tool
foreach my $pn ("JRHelper") {
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

my $toprintd = "[JobRunner]";
my $onlycheck_rc = 99;
my $usage = &set_usage();
JRHelper::ok_quit("\n$usage\n") if (scalar @ARGV == 0);

# Default values for variables
# none here

my $blockdir = "";
my @checkfiles = ();
my $tname = "";
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
my @predir = ();
my $postrun_Done = "";
my $postrun_Error = "";
my $postrun_cd = "";
my $gril = 0;
my $grid = "";
my $toprint = "";

my @cc = ();
&process_options();

if (! JRHelper::is_blank($outconf)) {
  if (scalar @ARGV > 0) {
    push @cc, '--', @ARGV;
  }
  JRHelper::error_quit("Problem writing configuration file ($outconf)")
    if (! JRHelper::dump_memory_object($outconf, "", \@cc,
                                    "# Job Runner Configuration file\n\n",
                                    undef, 0));
  JRHelper::ok_quit("Wrote \'saveConfig\' file ($outconf)");
}

my $name = &adapt_name($tname);
JRHelper::error_quit("No \'name\' specified, aborting")
  if (JRHelper::is_blank($name));

my $toprint2 = (JRHelper::is_blank($toprint)) ? "$toprintd $name : " : "$toprint "; 
## From here we ought to use the local error_quit

foreach my $ddir (@predir) {
  JRHelper::error_quit("${toprint2}Could not create requested \'preCreateDir\' dir ($ddir)")
    if (! JRHelper::make_wdir($ddir));
}

my $pwd = JRHelper::get_pwd();
if (! JRHelper::is_blank($dirchange)) {
  my $err = JRHelper::check_dir_r($dirchange);
  JRHelper::error_quit("${toprint2}Problem with \'dirChange\' directory ($dirchange): $err")
    if (! JRHelper::is_blank($err));
  JRHelper::error_quit("${toprint2}Could not change to requested \'dirChange\' directory ($dirchange)")
    if (! chdir($dirchange));
  JRHelper::warn_print("${toprint2}dirChange -- Current directory changed to \'$dirchange\'");
}

# Remaining of command line is the command to start
JRHelper::error_quit("${toprint2}\'executable\' and command line can not be used at the same time")
  if ((defined $executable) && (scalar @ARGV > 0));
JRHelper::error_quit("${toprint2}Neither \'executable\', nor command line are specified, and we are not in \'OnlyCheck\' mode")
  if ((! defined $executable) && (scalar @ARGV == 0) && (! $onlycheck));

if (defined $executable) {
  my $err = JRHelper::check_file_x($executable);
  JRHelper::error_quit("${toprint2}Problem with \'executable\' ($executable): $err")
    if (! JRHelper::is_blank($err));
}

foreach my $rit (@runiftrue) {
  my $err = JRHelper::check_file_x($rit);
  JRHelper::error_quit("${toprint2}Problem with \'RunIfTrue\' executable ($rit): $err")
    if (! JRHelper::is_blank($err));
}

$blockdir =~ s%\/$%%; # remove trailing /
$blockdir = JRHelper::get_file_full_path($blockdir, $pwd);
JRHelper::error_quit("${toprint2}No \'lockdir\' specified, aborting")
  if (JRHelper::is_blank($blockdir));

my $err = JRHelper::check_dir_w($blockdir);
JRHelper::error_quit("${toprint2}Problem with \'lockdir\' : $err")
  if (! JRHelper::is_blank($err));

my $lockdir = "$blockdir/$name";
JRHelper::error_quit("${toprint2}The lockdir directory ($lockdir) must not exist to use this tool")
  if (JRHelper::does_dir_exists($lockdir));

my @dir_end = ("done", "skip", "bad", "inprogress");
my $ds_sep  = "_____";
my @all = ();
foreach my $end (@dir_end) {
  my $tmp = "${ds_sep}$end";
  JRHelper::error_quit("${toprint2}Requested lockdir can not end in \'$tmp\' ($lockdir)")
      if ($lockdir =~ m%$tmp$%i);
  push @all, "$lockdir$tmp";
}
my ($dsDone, $dsSkip, $dsBad, $dsRun) = @all;

my $blogfile = "logfile";

foreach my $file (@checkfiles) {
  my $err = JRHelper::check_file_r($file);
  JRHelper::error_quit("${toprint2}Problem with \'checkfile\' [$file] : $err")
      if (! JRHelper::is_blank($err));
}

my @mulcheck = ();
foreach my $tmpld (@all) {
  push(@mulcheck, $tmpld)
    if (JRHelper::does_dir_exists($tmpld));
}
JRHelper::error_quit("${toprint2}Can not run program, lockdir already exists in multiple states:\n - " . join("\n - ", @mulcheck))
  if (scalar @mulcheck > 1);
#print "[*] ", join("\n[*] ", @mulcheck), "\n";


##########
## Skip ?
JRHelper::ok_quit("${toprint2}Skip requested")
  if (JRHelper::does_dir_exists($dsSkip));


##########
## Previously bad ?
if (JRHelper::does_dir_exists($dsBad)) {
  JRHelper::ok_quit("${toprint2}Previous bad run present, skipping")
      if (! $redobad);

  &vprint("${toprint2}!! Deleting previous run lockdir [$dsBad]");
  
  `rm -rf $dsBad`;
  JRHelper::error_quit("${toprint2}Problem deleting \'bad\' lockdir [$dsBad], still present ?")
      if (JRHelper::does_dir_exists($dsBad));
}


##########
## Previously done ?
if (JRHelper::does_dir_exists($dsDone)) {
  JRHelper::ok_quit("${toprint2}Previously succesfully completed")
    if (scalar @checkfiles == 0);
  
  my $flf = (JRHelper::is_blank($rlogfile)) ? "$dsDone/$blogfile" : $rlogfile;
  
  if (JRHelper::does_file_exists($flf)) {
    JRHelper::ok_quit("${toprint2}Previously succesfully completed, and no files listed in \'checkfile\' is newer than the logfile, not re-runing")
      if (JRHelper::newest($flf, @checkfiles) eq $flf);
    &vprint("!! ${toprint2}Previously succesfully completed, but at least one file listed in \'checkfile\' is newer than the logfile => re-runing");
  } else {
    &vprint("!! ${toprint2}Previously succesfully completed, but logfile absent => considering as new run");
  }
  
  &vprint("${toprint2}!! Deleting previous run lockdir [$dsDone]");
  `rm -rf $dsDone`;
  JRHelper::error_quit("${toprint2}Problem deleting lockdir [$dsDone], still present ?")
    if (JRHelper::does_dir_exists($dsDone));
}


##########
## Already in progress ?
JRHelper::ok_quit("${toprint2}Job already in progress, Skipping")
  if (JRHelper::does_dir_exists($dsRun));

##########
# Actual run
&check_RunIfTrue();

if ($onlycheck) {
  &vprint("${toprint2}Would actually have to run tool, exiting with expected return code ($onlycheck_rc)\n");
  exit($onlycheck_rc);
}

&vprint("${toprint2}%% In progress: $toprint\n");

# In case the user use Ctrl+C do not return "ok"
sub SIGINTh { JRHelper::error_quit("${toprint2}\'Ctrl+C\'-ed, exiting with error status"); }
$SIG{'INT'} = 'SIGINTh';

&vprint("${toprint2}++ Creating \"In Progress\" lock dir");
JRHelper::error_quit("${toprint2}Could not create writable dir ($dsRun)")
  if (! JRHelper::make_wdir($dsRun));
my $flf = (JRHelper::is_blank($rlogfile)) ? "$dsRun/$blogfile" : $rlogfile;

## From here any "error_quit" has to rename $dsRun to $dsBad

# goRunInLock
if ($gril) {
  if (! chdir($dsRun)) {
    &rod($dsRun, $dsBad); # Move to "bad" status
    JRHelper::error_quit("${toprint2}Could not change to requested \'goRunInLock\' directory ($dsRun)");
  }
  JRHelper::warn_print("${toprint2}goRunInLock -- Current directory changed to \'$dsRun\'");
}

# CreateDir
foreach my $ddir (@destdir) {
  if (! JRHelper::make_wdir($ddir)) {
    &rod($dsRun, $dsBad); # Move to "bad" status
    JRHelper::error_quit("${toprint2}Could not create requested \'CreateDir\' dir ($ddir)");
  }
}

# GoRunInDir
if (! MMisc::is_blank($grid)) {
  if (! chdir($grid)) {
    &rod($dsRun, $dsBad); # Move to "bad" status
    JRHelper::error_quit("${toprint2}Could not change to requested \'GoRunInDir\' directory ($grid)");
  }
  JRHelper::warn_print("${toprint2}GoRunInDir -- Current directory changed to \'$grid\'");
}

my ($rv, $tx, $so, $se, $retcode, $flogfile)
  = JRHelper::write_syscall_logfile
  ($flf, (defined $executable) ? $executable : @ARGV);
&vprint("${toprint2}-- Final Logfile different from expected one: $flogfile")
  if ($flogfile ne $flf);

if (! JRHelper::is_blank($postrun_cd)) {
  if (! chdir($postrun_cd)) {
    &rod($dsRun, $dsBad); # Move to "bad" status
    JRHelper::error_quit("${toprint2}Could not change to requested \'PostRunChangeDir\' directory ($postrun_cd)");
  }
  JRHelper::warn_print("${toprint2}PostRunChangeDir -- Current directory changed to \'$postrun_cd\'");
}

if ($retcode == 0) {
  &rod($dsRun, $dsDone); # Move to "ok" status
  if (! JRHelper::is_blank($postrun_Done)) {
    &vprint("${toprint2}%% OK Post Running: \'$postrun_Done\'\n");
    my ($rc, $so, $se) = JRHelper::do_system_call($postrun_Done);
    &_postrunning_status("\'OK Post Running\'", $rc, $so, $se);
  }
  JRHelper::ok_quit("${toprint2}Job succesfully completed");
}

## If we are here, it means it was a BAD run
&rod($dsRun, $dsBad); # Move to "bad" status
if (! JRHelper::is_blank($postrun_Error)) {
  &vprint("${toprint2}%% ERROR Post Running: \'$postrun_Error\'\n");
  my ($rc, $so, $se) = JRHelper::do_system_call($postrun_Error);
  &_postrunning_status("\'ERROR Post Running\'", $rc, $so, $se);
}
$flogfile =~ s%$dsRun%$dsBad%;
&ec_error_quit($retcode, "${toprint2}Error during run, see logfile ($flogfile)");

########################################

sub _postrunning_status {
  my ($mode, $rc, $so, $se) = @_;
  JRHelper::warn_print("${toprint2}Unsuccesfull return code for $mode\n")
    if ($rc != 0);
  &vprint("${toprint2}$mode -- stdout: $so\n") if (! JRHelper::is_blank($so));
  &vprint("${toprint2}$mode -- stderr: $se\n") if (! JRHelper::is_blank($se));
}

#####

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

  JRHelper::error_quit("${toprint2}Could not rename [$e1] to [$e2] : $!")
    if (! rename($e1, $e2));
}

##########

sub vprint {
  return if (! $verb);
  print join("", @_), "\n";
}

#####

sub ec_error_quit {
  my $ec = shift @_;
  print('[ERROR] ', join(' ', @_), "\n");
  exit(0) if ($okquit);
  exit($ec);
}

####################

sub check_RunIfTrue {
  return() if (scalar @runiftrue == 0);

  foreach my $rit (@runiftrue) {
    my ($rc, $so, $se) = JRHelper::do_system_call($rit);
    if ($rc == 0) {
      &vprint("${toprint2}== \'RunIfTrue\' check OK ($rit)");
    } else {
      &vprint("${toprint2}== \'RunIfTrue\' check FAILED ($rit)\n stdout:$so\n stderr:$se");
      JRHelper::ok_quit("${toprint2}\'RunIfTrue\' check did not succeed ($rit), will not run job, but exiting with success return code");
    }
  }
}

########################################

sub _cc1 { push @cc, "--" . $_[0]; }
sub _cc2 { push @cc, "--" . $_[0]; push @cc, $_[1]; } 

#####

sub process_options {
# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz  #
# Used:   CDE G    L  OP R   V     bcde gh   l nop rstuv      #

  my %opt = ();

  GetOptions
    (
     \%opt,
     'help',
     'version',
     'lockdir=s'   => sub {$blockdir = $_[1]; &_cc2(@_);},
     'checkfile=s' => sub {push @checkfiles, $_[1]; &_cc2(@_);},
     'name=s'      => sub {$tname = $_[1]; &_cc2(@_)},
     'Verbose'     => sub {$verb++; &_cc1(@_);},
     'badErase'    => sub {$redobad++; &_cc1(@_);},
     'okquit'      => sub {$okquit++; &_cc1(@_);},
     'CreateDir=s' => sub {push @destdir, $_[1]; &_cc2(@_);},
     'preCreateDir=s' => sub {push @predir, $_[1]; &_cc2(@_);},
     'OnlyCheck'   => \$onlycheck,
     'executable=s' => sub {$executable = $_[1]; &_cc2(@_);},
     'LogFile=s'   => sub {$rlogfile = $_[1]; &_cc2(@_);},
     'saveConfig=s' => \$outconf,
     'useConfig=s'  => sub {&load_options($_[1]);},
     'dirChange=s'  => sub {$dirchange = $_[1]; &_cc2(@_);},
     'RunIfTrue=s'  => sub {push @runiftrue, $_[1]; &_cc2(@_);},
     'DonePostRun=s'  => sub {$postrun_Done  = $_[1]; &_cc2(@_);},
     'ErrorPostRun=s' => sub {$postrun_Error = $_[1]; &_cc2(@_);},
     'PostRunChangeDir=s' => sub {$postrun_cd = $_[1]; &_cc2(@_);},
     'goRunInLock'    => sub {$gril = 1; &_cc1(@_);},
     'GoRunInDir=s'   => sub {$grid = $_[1]; &_cc2(@_);},
     'toPrint=s'      => sub {$toprint = $_[1]; &_cc2(@_);},
    ) or JRHelper::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");
  JRHelper::ok_quit("\n$usage\n") if ($opt{'help'});
  JRHelper::ok_quit("$versionid\n") if ($opt{'version'});
}

#####

sub load_options {
  my ($conf) = @_;

  my $err = JRHelper::check_file_r($conf);
  JRHelper::error_quit("Problem with \'useConfig\' file ($conf): $err")
    if (! JRHelper::is_blank($err));

  my $tmp = undef;
  $tmp = JRHelper::load_memory_object($conf);
  JRHelper::error_quit("Problem with configuration file data ($conf)")
    if (! defined $tmp);
  push @ARGV, @$tmp;
}

#####

sub set_usage {  
  my $tmp=<<EOF
$versionid

$0 [options] --lockdir ldir --name jobid --executable script
  or
$0 [options] --lockdir ldir --name jobid -- command_line_to_run

if it can be run, will either run the executable script or the command_line_to_run 



Where [options] are split in:
  required_options [common_options] [step1_options] [step2_options] [step3_options]


required_options are:
  --lockdir ldir
      base lock directory, used to create the actual lock directory (default location of the logfile)
  --name jobid
      the unique ID (text value) representing one\'s job (fixed so that it remove any leading and trailing space, and transforming any characters not a-z, 0-9 or - to _)
  --executable script
      executable file to run (only required in non \'command_line_to_run\' mode)


[common_options] apply to any step, and are:
  --help
      This help message. For more help and examples, please look at the Primer that should have been included in the source archive of the tool
  --version
      Version information
  --Verbose
      Print more verbose status updates
  --okquit
      In case the command line to run return a bad status, return the "ok" (exit code 0) status, otherwise return the actual command return code (note that this only applies to the command run, all other issues will return the error exit code)
  --saveConfig file
      Do not run anything, instead save the command line options needed to run that specific JobRunner job into a specified configuration file that can be loaded in another JobRunner call using \'--useConfig\'
  --useConfig file
      Use one (and only one) JobRunner configuration files generated by \'--saveConfig\'. To run on multiple files, use \'JobRunner_Caller\'.
  --toPrint text
    Change the default output header for JobRunner from: $toprint followed by jobid to user given entry

[step1_options] are any options that take effect before the lock is made, and are (in order of use):
  --preCreateDir dir [--preCreateDir dir [...]] 
      Create the specified writable directory if it does not exist. Note that this is done before any checks and as such should be used with caution.
  --dirChange dir
      Go to the specified directory
  --LogFile file
      Override the default location of the log file (inside the run lock directory). Use this option with caution since it will influence the behavior of \'checkfile\'
  --checkfile file [--checkfile file [...]]
      check that the required file is present before accepting to run this job. When a succesful run is present, check if the file date is newer than the succesful run\'s logfile to decide if a re-run is necessary.
  --RunIfTrue executable [--RunIfTrue executable [...]]
      Check that given program (no arguments accepted) returns true (0 exit status) to run job, otherwise do not run job (will still be available for later rerun)
  --badErase
      If a bad run is present, erase it run lock directory so it can be retried
  --Onlycheck
      Do the entire check list but before doing the actual run, exit with a return code value of \"$onlycheck_rc\" (reminder: 1 means that there was an issue, 0 means that the program exited succesfuly, ie in this case a previous run completed, which can still be a bad run)


[step2_options] are any options that take effect after the lock is made but before the job is run, and are (in order of use):
  --goRunInLock
      Run in the lock directory
  --CreateDir dir [--CreateDir dir [...]]
      Create the specified writable directory if it does not exist.
  --GoRunInDir
      Run in the specified directory


[step3_options] are any options that take effect after the job is run (in order of use):
  --PostRunChangeDir dir
      Change directory to dir
  --DonePostRun script
      If the executable or run command exited succesfully, run specified script
  --ErrorPostRun script
      If the executable or run command did not exit succesfully, run specified script


EOF
;

  return($tmp);
}
