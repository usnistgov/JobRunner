#!/usr/bin/env perl
# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs
#
# $Id$
#
# JobRunner
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
my $version = JRHelper::slurp_file(dirname(abs_path($0)) . "/.jobrunner_version");
$version =~ s%^.+\-%%;
my $versionid = "JobRunner $version";

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

## Debug options START
# comment section if not using
# use File::Tee qw(tee);
# sub __dbg_get_date { return(JRHelper::epoch2str(JRHelper::get_scalar_currenttime()) . ": " . $_[0]); }
# { my $date = JRHelper::epoch2str(JRHelper::get_scalar_currenttime());
#   my $_dbg_ofile = $ENV{'HOME'} . "/_____log_____JobRunner.pl_____".$date.".$$";
#   tee STDOUT, { prefix => 'OUT: ', preprocess => \&__dbg_get_date, lock => 1, mode => '>>', open => $_dbg_ofile };
#   tee STDERR, { prefix => 'ERR: ', preprocess => \&__dbg_get_date, lock => 1, mode => '>>', open => $_dbg_ofile }; }
## Debug options END

########################################
# Options processing

my $toprintd = "[JobRunner]";
my $onlycheck_rc = 99;
my $jr_mutext_env = 'JOBRUNNER_MUTEXTOOL';
my $jr_mutexd_env = 'JOBRUNNER_MUTEXLOCKDIR';
my $auto_name = "__auto__";
my $usage = &set_usage();
JRHelper::ok_quit("\n$usage\n") if (scalar @ARGV == 0);

# Default values for variables
# none here

my $blockdir = "";
my @checkfiles = ();
my $name = "";
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
my $successreturn = undef;
my $sp_lt = "";
my $sp_ltdir = "";
my $sp_lf = "";
my $ics = 0;
my @waiton = ();
my $showpid = undef;

my @cc = ();
my %ccx = ();
# Sort the options, so that 'useConfig' is first to load the file before the command line override
my $pwd = JRHelper::get_pwd();
 
@ARGV = &__sort_options();
&process_options();

## Catch some errors before writing config file
JRHelper::error_quit("\'executable\' and command line can not be used at the same time")
  if ((defined $executable) && (scalar @ARGV > 0));

JRHelper::error_quit("\'0\' or \'1\' are invalid \"SuccessReturnCode\" values, as they are reserved for normal operations")
  if ((defined $successreturn) && (($successreturn == 0) || ($successreturn == 1)));

&error_quit("No \'lockdir\' specified, aborting")
  if (JRHelper::is_blank($blockdir));

my $err = JRHelper::check_dir_w($blockdir);
&error_quit("Problem with \'lockdir\' : $err")
  if (! JRHelper::is_blank($err));

JRHelper::error_quit("No \'name\' specified, aborting")
  if (JRHelper::is_blank($name));

$sp_ltdir = $blockdir
  if ((! JRHelper::is_blank($sp_lt)) && (JRHelper::is_blank($sp_ltdir)));

#####
# write configuration file
if (! JRHelper::is_blank($outconf)) {
  if (JRHelper::does_dir_exist($outconf)) {
    $outconf =~ s%\/$%%; # remove trailing /
    $outconf = "$outconf/$name";
  }
  if (scalar @ARGV > 0) {
    push @cc, '--', @ARGV;
  }
  JRHelper::error_quit("Problem writing configuration file ($outconf)")
    if (! JRHelper::dump_memory_object($outconf, "", \@cc,
                                    "# Job Runner Configuration file\n\n",
                                    undef, 0));
  JRHelper::ok_quit("Wrote \'saveConfig\' file ($outconf)");
}

#################### Start processing
my $toprint2 = (JRHelper::is_blank($toprint)) ? "$toprintd $name : " : "$toprint "; 

#### Mutex pre-checks
# load them from environment variables (if possible) and not set on the command line
$sp_lt = ((JRHelper::is_blank($sp_lt)) && (exists $ENV{$jr_mutext_env})) ? $ENV{$jr_mutext_env} : "";
$sp_ltdir = ((JRHelper::is_blank($sp_ltdir)) && (exists $ENV{$jr_mutexd_env})) ? $ENV{$jr_mutexd_env} : "";
# then do some checks
if (! JRHelper::is_blank($sp_lt)) {
  # redo those checks in case the environment variables were used
  JRHelper::error_quit("When using \'mutexTool\', a \'MutexLockDir\' must be specified")
    if (JRHelper::is_blank($sp_ltdir));
  JRHelper::error_quit("\'MutexLockDir\' can not be the same as \'lockdir\'")
    if ($sp_ltdir eq $blockdir);
  # now some new checks
  my $err = JRHelper::check_file_x($sp_lt);
  JRHelper::error_quit("${toprint2}Problem with \'mutexTool\' ($sp_lt): $err")
    if (! JRHelper::is_blank($sp_lt));
  $err = JRHelper::check_dir_w($sp_ltdir);
  JRHelper::error_quit("${toprint2}Problem with \'MutexLockDir\' ($sp_ltdir): $err")
    if (! JRHelper::is_blank($err));
}

## From here we ought to use the local quit functions:
# ec_error_quit, ec_ok_quit, error_quit, ok_quit

## Obtain the mutex
if (! JRHelper::is_blank($sp_lt)) {
  $sp_lf = "$sp_ltdir/$name";
  my @cmd = ($sp_lt, $sp_lf);
  my ($rc, $so, $se) = JRHelper::do_system_call(@cmd);

  # we were not able to get the lock/mutex ... somebody else is doing this job, force a skip
  if ($rc != 0) {
    $sp_lf = "";
    &error_quit("${toprint2}Can not obtain \'mutex\', exiting tool");
  }
  
  # we have the insured mutex, continue
}


foreach my $ddir (@predir) {
  &error_quit("${toprint2}Could not create requested \'preCreateDir\' dir ($ddir)")
    if (! JRHelper::make_wdir($ddir));
}

if (! JRHelper::is_blank($dirchange)) {
  my $err = JRHelper::check_dir_r($dirchange);
  &error_quit("${toprint2}Problem with \'dirChange\' directory ($dirchange): $err")
    if (! JRHelper::is_blank($err));
  &error_quit("${toprint2}Could not change to requested \'dirChange\' directory ($dirchange)")
    if (! chdir($dirchange));
  JRHelper::warn_print("${toprint2}dirChange -- Current directory changed to \'$dirchange\'");
}

# Remaining of command line is the command to start
&error_quit("${toprint2}Neither \'executable\', nor command line are specified, and we are not in \'OnlyCheck\' mode")
  if ((! defined $executable) && (scalar @ARGV == 0) && (! $onlycheck));

if (defined $executable) {
  my $err = JRHelper::check_file_x($executable);
  &error_quit("${toprint2}Problem with \'executable\' ($executable): $err")
    if (! JRHelper::is_blank($err));
}

foreach my $rit (@runiftrue) {
  my $err = JRHelper::check_file_x($rit);
  &error_quit("${toprint2}Problem with \'RunIfTrue\' executable ($rit): $err")
    if (! JRHelper::is_blank($err));
}

my $lockdir = "$blockdir/$name";
&error_quit("${toprint2}The lockdir directory ($lockdir) must not exist to use this tool")
  if (JRHelper::does_dir_exist($lockdir));

my @dir_end = ("done", "skip", "bad", "inprogress");
my $ds_sep  = "_____";
my @all = ();
foreach my $end (@dir_end) {
  my $tmp = "${ds_sep}$end";
  &error_quit("${toprint2}Requested lockdir can not end in \'$tmp\' ($lockdir)")
    if ($lockdir =~ m%$tmp$%i);
  push @all, "$lockdir$tmp";
}
my ($dsDone, $dsSkip, $dsBad, $dsRun) = @all;

foreach my $wname (@waiton) {
  $wname = &adapt_name($wname);
  &error_quit("\'WaitForJobName\' jobid is the same as the main jobid [$wname], aborting")
    if ($wname eq $name);
  my $tmp = "$blockdir/$wname${ds_sep}" . $dir_end[0];
  &error_quit("${toprint2}\'WaitForJobName\' [$wname] not done, exiting")
    if (! JRHelper::does_dir_exist($tmp));
}

foreach my $file (@checkfiles) {
  my $err = JRHelper::check_file_r($file);
  &error_quit("${toprint2}Problem with \'checkfile\' [$file] : $err")
    if (! JRHelper::is_blank($err));
}

my @mulcheck = ();
foreach my $tmpld (@all) {
  push(@mulcheck, $tmpld)
    if (JRHelper::does_dir_exist($tmpld));
}
&error_quit("${toprint2}Can not run program, lockdir already exists in multiple states:\n - " . join("\n - ", @mulcheck))
  if (scalar @mulcheck > 1);
#print "[*] ", join("\n[*] ", @mulcheck), "\n";


##########
## Skip ?
&ok_quit("${toprint2}Skip requested")
  if (JRHelper::does_dir_exist($dsSkip));

my $blogfile = "logfile";
##########
## Previously bad ?
if (JRHelper::does_dir_exist($dsBad)) {
  &ok_quit("${toprint2}Previous bad run present, skipping")
    if (! $redobad);

  &vprint("${toprint2}!! Deleting previous run lockdir [$dsBad]");
  
  `rm -rf $dsBad`;
  &error_quit("${toprint2}Problem deleting \'bad\' lockdir [$dsBad], still present ?")
    if (JRHelper::does_dir_exist($dsBad));
}


##########
## Previously done ?
if (JRHelper::does_dir_exist($dsDone)) {
  my $flf = (JRHelper::is_blank($rlogfile)) ? "$dsDone/$blogfile" : $rlogfile;
  
  if (JRHelper::does_file_exist($flf)) {
    if (JRHelper::newest($flf, @checkfiles) eq $flf) { 
      my $msg = "${toprint2}Previously successfully completed";
      &ec_ok_quit($successreturn, $msg) if (defined $successreturn);
      &ok_quit("$msg" . ((scalar @checkfiles > 0) ? ", and no file listed in \'checkfile\' is newer than the logfile, not re-runing" : ""));
    }
    &vprint("!! ${toprint2}Previously successfully completed, but at least one file listed in \'checkfile\' is newer than the logfile => re-runing");
  } else {
    &vprint("!! ${toprint2}Previously successfully completed, but logfile absent => considering as new run");
  }
  
  &vprint("${toprint2}!! Deleting previous run lockdir [$dsDone]");
  `rm -rf $dsDone`;
  &error_quit("${toprint2}Problem deleting lockdir [$dsDone], still present ?")
    if (JRHelper::does_dir_exist($dsDone));
}


##########
## Already in progress ?
&ok_quit("${toprint2}Job already in progress, Skipping")
  if (JRHelper::does_dir_exist($dsRun));

##########
# Actual run
&check_RunIfTrue();

if ($onlycheck) {
  &vprint("${toprint2}Would actually had run tool, exiting with \'OnlyCheck\' expected return code ($onlycheck_rc)\n");
  &ec_ok_quit($onlycheck_rc);
}

&vprint("${toprint2}%% In progress: $toprint\n");

# In case the user use Ctrl+C do not return "ok"
sub SIGINTh { &error_quit("${toprint2}\'Ctrl+C\'-ed, exiting with error status"); }
$SIG{'INT'} = \&SIGINTh;

&vprint("${toprint2}++ Creating \"In Progress\" lock dir");
&error_quit("${toprint2}Could not create writable dir ($dsRun)")
  if (! JRHelper::make_wdir($dsRun));
my $flf = (JRHelper::is_blank($rlogfile)) ? "$dsRun/$blogfile" : $rlogfile;

## From here any "error_quit" has to rename $dsRun to $dsBad

# goRunInLock
if ($gril) {
  if (! chdir($dsRun)) {
    &rod($dsRun, $dsBad); # Move to "bad" status
    &error_quit("${toprint2}Could not change to requested \'goRunInLock\' directory ($dsRun)");
  }
  JRHelper::warn_print("${toprint2}goRunInLock -- Current directory changed to \'$dsRun\'");
}

# CreateDir
foreach my $ddir (@destdir) {
  if (! JRHelper::make_wdir($ddir)) {
    &rod($dsRun, $dsBad); # Move to "bad" status
    &error_quit("${toprint2}Could not create requested \'CreateDir\' dir ($ddir)");
  }
}

# GoRunInDir
if (! JRHelper::is_blank($grid)) {
  if (! chdir($grid)) {
    &rod($dsRun, $dsBad); # Move to "bad" status
    &error_quit("${toprint2}Could not change to requested \'GoRunInDir\' directory ($grid)");
  }
  JRHelper::warn_print("${toprint2}GoRunInDir -- Current directory changed to \'$grid\'");
}

if (! defined $showpid) {
  JRHelper::set_showpid("");
  JRHelper::set_showpid_pre_text($toprint2);
} else {
  JRHelper::set_showpid($showpid);
}
my ($rv, $tx, $so, $se, $retcode, $flogfile, $signal)
  = JRHelper::write_syscall_logfile
  ($flf, (defined $executable) ? $executable : @ARGV);
JRHelper::set_showpid(undef);
&vprint("${toprint2}-- Final Logfile different from expected one: $flogfile")
  if ($flogfile ne $flf);

$signal = ($ics == 1) ? 0 : $signal;

if (! JRHelper::is_blank($postrun_cd)) {
  if (! chdir($postrun_cd)) {
    &rod($dsRun, $dsBad); # Move to "bad" status
    &error_quit("${toprint2}Could not change to requested \'PostRunChangeDir\' directory ($postrun_cd)");
  }
  JRHelper::warn_print("${toprint2}PostRunChangeDir -- Current directory changed to \'$postrun_cd\'");
}

if (($retcode == 0) && ($signal == 0)) {
  &rod($dsRun, $dsDone); # Move to "ok" status
  if (! JRHelper::is_blank($postrun_Done)) {
    &vprint("${toprint2}%% OK Post Running: \'$postrun_Done\'\n");
    my ($rc, $so, $se) = JRHelper::do_system_call($postrun_Done);
    &_postrunning_status("\'OK Post Running\'", $rc, $so, $se);
  }
  print("${toprint2}Job successfully completed\n");
  &ec_ok_quit($successreturn) if (defined $successreturn);
  &ec_ok_quit();
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
  JRHelper::warn_print("${toprint2}Unsuccessfull return code for $mode\n")
    if ($rc != 0);
  &vprint("${toprint2}$mode -- stdout: $so\n") if (! JRHelper::is_blank($so));
  &vprint("${toprint2}$mode -- stderr: $se\n") if (! JRHelper::is_blank($se));
}

#####

sub get_full_path {
  my $tmp = $_[0];
  $tmp =~ s%\/$%%; # remove trailing /
  $tmp = JRHelper::get_file_full_path($tmp, $pwd);
  return($tmp);
}

#####

sub adapt_name {
  my $tmp = $_[0];
  if ($tmp eq $auto_name) { 
    $tmp = join("___", JRHelper::epoch2str(JRHelper::get_scalar_currenttime()), $$, int(rand(1000000))); 
  }
  $tmp =~ s%^\s+%%;
  $tmp =~ s%\s+$%%;
  $tmp =~ s%[^a-z0-9-_]%_%ig;
  return($tmp);
}

#####

sub rod { # rename or die
  my ($e1, $e2) = @_;

  &error_quit("${toprint2}Could not rename [$e1] to [$e2] : $!")
    if (! rename($e1, $e2));
}

##########

sub vprint {
  return if (! $verb);
  print join("", @_), "\n";
}

#####

sub __common_quit {
  print $_[0] if (! JRHelper::is_blank($_[0]));
  unlink($sp_lf) if (! JRHelper::is_blank($sp_lf)); # release the "mutex"
}

##

sub error_quit {
  &__common_quit((scalar @_ > 0) ? '[ERROR] ' . join(' ', @_) . "\n" : "");
  JRHelper::error_quit();
}

##

sub ec_error_quit {
  my $ec = shift @_;
  &__common_quit((scalar @_ > 0) ? '[ERROR] ' . join(' ', @_) . "\n" : "");
  JRHelper::ok_exit() if ($okquit);
  exit($ec);
}

##

sub ok_quit {
  &__common_quit((scalar @_ > 0) ? join(' ', @_) . "\n" : "");
  JRHelper::ok_exit();
}

##

sub ec_ok_quit {
  my $ec = shift @_;
  &__common_quit((scalar @_ > 0) ? join(' ', @_) . "\n" : "");
  exit($ec) if ((defined $ec) && ($ec != 0));
  JRHelper::ok_exit();
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
      &ok_quit("${toprint2}\'RunIfTrue\' check did not succeed ($rit), will not run job, but exiting with success return code");
    }
  }
}

########################################

sub __sort_options {
  my @p = ();
  my @rest = ();
  while (my $v = shift @ARGV) {
    if ($v =~ m%^\-\-?u%) { # useConfig
      push @p, ($v, shift @ARGV);
      next;
    }
    return(@p, @rest, $v, @ARGV)
      if ($v =~ m%^\-\-$%); # -- => stop processing
    push @rest, $v;
  }
  return(@p, @rest);
}

#####

sub _cc1 { $ccx{$_[0]} = scalar @cc; push @cc, "--" . $_[0]; }
sub _ccr1 { # For options for which only one value is authorized, replace previous entry
  if (exists $ccx{$_[0]}) {
    $cc[$ccx{$_[0]}] = "--" . $_[0];
  } else {
    &_cc1(@_);
  }
}
sub _cc2 { $ccx{$_[0]} = scalar @cc; push @cc, "--" . $_[0]; push @cc, $_[1]; } 
sub _ccr2 {
  if (exists $ccx{$_[0]}) {
    $cc[$ccx{$_[0]}] = "--" . $_[0];
    $cc[$ccx{$_[0]} + 1] = $_[1];
  } else {
    &_cc2(@_);
  }
}

#####

sub process_options {
# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz  #
# Used:   CDE G  J LM OP RS  VW    bcde ghi  lmnop  stuvw     #

  my %opt = ();

  GetOptions
    (
     \%opt,
     'help',
     'version',
     'lockdir=s'   => sub {$_[1] = &get_full_path($_[1]); $blockdir = $_[1]; &_ccr2(@_);},
     'checkfile=s' => sub {push @checkfiles, $_[1]; &_cc2(@_);},
     'name=s'      => sub {$_[1] = &adapt_name($_[1]); $name = $_[1]; &_ccr2(@_)},
     'Verbose'     => sub {$verb++; &_cc1(@_);},
     'badErase'    => sub {$redobad++; &_ccr1(@_);},
     'okquit'      => sub {$okquit++; &_ccr1(@_);},
     'CreateDir=s' => sub {push @destdir, $_[1]; &_cc2(@_);},
     'preCreateDir=s' => sub {push @predir, $_[1]; &_cc2(@_);},
     'OnlyCheck'   => \$onlycheck,
     'executable=s' => sub {$executable = $_[1]; &_ccr2(@_);},
     'LogFile=s'   => sub {$rlogfile = $_[1]; &_ccr2(@_);},
     'saveConfig=s' => \$outconf,
     'useConfig=s'  => sub {&load_options($_[1]);},
     'dirChange=s'  => sub {$dirchange = $_[1]; &_ccr2(@_);},
     'RunIfTrue=s'  => sub {push @runiftrue, $_[1]; &_cc2(@_);},
     'DonePostRun=s'  => sub {$postrun_Done  = $_[1]; &_ccr2(@_);},
     'ErrorPostRun=s' => sub {$postrun_Error = $_[1]; &_ccr2(@_);},
     'PostRunChangeDir=s' => sub {$postrun_cd = $_[1]; &_ccr2(@_);},
     'goRunInLock'    => sub {$gril = 1; &_ccr1(@_);},
     'GoRunInDir=s'   => sub {$grid = $_[1]; &_ccr2(@_);},
     'toPrint=s'      => sub {$toprint = $_[1]; &_ccr2(@_);},
     'SuccessReturnCode=i' => sub {$successreturn = $_[1]; &_ccr2(@_);},
     'mutexTool=s' => sub {$sp_lt = $_[1]; &_ccr2(@_);},
     'MutexLockDir=s' => sub {$sp_ltdir = $_[1]; &_ccr2(@_);},
     'ignoreChildSignal' => sub {$ics = 1; &_cc1(@_);},
     'WaitForJobName=s' => sub {push @waiton, $_[1]; &_ccr2(@_);},
     'writePID=s' => \$showpid,
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
  # Find the '--'
  my @pre = ();
  my $doit = 1;
  while ($doit == 1 && scalar @$tmp > 0) {
    if ($$tmp[0] == '--') {
      $doit = 0;
      next;
    }
    push @pre, shift @$tmp;
  }
  

  if (scalar @pre > 0) {
    unshift @ARGV, @pre; # add to beginning of argument processing entries before '--' to allow for command line override
  }

  if (scalar @$tmp > 0) {
    push @ARGV, @$tmp; # add to the end components after '--'
  }
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
      the unique ID (text value) representing one\'s job (fixed so that it remove any leading and trailing space, and transforming any characters not a-z, 0-9 or - to _). Use \"$auto_name\" to have an automatic name generated with: YYYYMMDD-HHMMSS___PID___RANDof1000000
  --executable script
      executable file to run (only required in non \'command_line_to_run\' mode)


[common_options] apply to any step, and are:
  --help
      This help message. For more help and examples, please look at the Primer that should have been included in the source archive of the tool
  --version
      Version information
  --Verbose
      Print more verbose status updates
  --mutexTool tool
      Specify the full path location of a special locking tool used to create a mutual exclusion to insure JobID exclusive execution (**). Can be specified globaly using the \'$jr_mutext_env\' environment variable (command line takes precedence)
  --MutexLockDir dir
      Directory in which the \'mutexTool\' lock for JobID will be created. Can be specified globaly using the \'$jr_mutexd_env\' environment variable (command line takes precedence). If none is specified, the main \'lockdir\' will be used.
  --okquit
      In case the command line to run return a bad status, return the "ok" (exit code 0) status, otherwise return the actual command return code (note that this only applies to the command run, all other issues will return the error exit code)
  --SuccessReturnCode
      If the command line to run was run successfully (or previously run successfully with no need to be rerun), return the user provided error code, any other return code indicates a non successful completion (including skipping job)
  --ignoreChildSignal
      Do not exit with error if the job exited on a SIGNAL. The default is to consider any signal an error condition (ex: SIGINT) 
  --saveConfig file|dir
      Do not run anything, instead save the command line options needed to run that specific JobRunner job into a specified configuration file that can be loaded in another JobRunner call using \'--useConfig\'. If a directory is provided, the \'jobid\' will be used as the file name within that directory.
  --useConfig file
      Use one (and only one) JobRunner configuration files generated by \'--saveConfig\'. To run on multiple files, use \'JobRunner_Caller\'.
  --toPrint text
    Change the default output header for JobRunner from: $toprint followed by jobid to user given entry
  --writePID
  Specify the file into which to write the PID of the job started (for easy kill). The default is to print a note to stdout. (Note: this option is not saved in the configuration file).

[step1_options] are any options that take effect before the lock is made, and are (in order of use):
  --preCreateDir dir [--preCreateDir dir [...]] 
      Create the specified writable directory if it does not exist. Note that this is done before any checks and as such should be used with caution.
  --dirChange dir
      Go to the specified directory
  --LogFile file
      Override the default location of the log file (inside the run lock directory). Use this option with caution since it will influence the behavior of \'checkfile\'
  --WaitForJobName jobid [--WaitForJobName jobid [...]]
      Check that the specified \'jobid\' name is completed before accepting to run this job. Will check in the same \'lockdir\' as the main \'jobid\'.
  --checkfile file [--checkfile file [...]]
      Check that the required file is present before accepting to run this job. When a successful run is present, check if the file date is newer than the successful run\'s logfile to decide if a re-run is necessary.
  --RunIfTrue executable [--RunIfTrue executable [...]]
      Check that given program (no arguments accepted) returns the ok exit status (0) to run job, otherwise do not run job (will still be available for later rerun)
  --badErase
      If a bad run is present, erase its run lock directory so it can be retried
  --Onlycheck
      Do the entire check list but before doing the actual run, exit with a return code value of \"$onlycheck_rc\" (reminder: 1 means that there was an issue, 0 means that the program exited successfully, ie in this case a previous run completed, which can still be a bad run). (Note: this option is not saved in the configuration file).


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
      If the executable or run command exited successfully, run specified script
  --ErrorPostRun script
      If the executable or run command did not exit successfully, run specified script


**: this is extremely important for queues on network shares (such as NFS), specify the tool that is known to create a safe exclusive access lock file on such a network share. The tool (or wrapper script) must: 1) take only one argument, the lock file location. 2) create the lock file but not erase it (this is done by $0 after job completion). 3) return the 0 exit status if the lock was obtained, any other status otherwise.


EOF
;

  return($tmp);
}
