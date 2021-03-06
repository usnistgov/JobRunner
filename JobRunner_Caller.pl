#!/usr/bin/env perl
# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs
#
# $Id$
#
# JobRunner_Caller
#
# Author(s): Martial Michel
#
# This software was developed at the National Institute of Standards and Technology by
# employees and/or contractors of the Federal Government in the course of their official duties.
# Pursuant to Title 17 Section 105 of the United States Code this software is not subject to 
# copyright protection within the United States and is in the public domain.
#
# "JobRunner_Caller" is an experimental system.
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
my $versionid = "JobRunner_Caller $version";

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
use File::Tee qw(tee);
sub __dbg_get_date { return(JRHelper::epoch2str(JRHelper::get_scalar_currenttime()) . ": " . $_[0]); }
{ my $date = JRHelper::epoch2str(JRHelper::get_scalar_currenttime());
  my $_dbg_ofile = $ENV{'HOME'} . "/_____log_____JobRunner_Caller.pl_____".$date.".$$";
  tee STDOUT, { prefix => 'OUT: ', preprocess => \&__dbg_get_date, lock => 1, mode => '>>', open => $_dbg_ofile };
  tee STDERR, { prefix => 'ERR: ', preprocess => \&__dbg_get_date, lock => 1, mode => '>>', open => $_dbg_ofile }; }
## Debug options END



########################################
# Options processing

my $dsleepv = 60;
my @ts_okv = ('atime', 'ctime', 'mtime');
my $ts_okv_txt = join(" ", @ts_okv);

my $usage = &set_usage();
JRHelper::ok_quit("\n$usage\n") if (scalar @ARGV == 0);

# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz  #
# Used:    DE    J L    QRS         cde  h    m o qrst vw     #

my $toolb = "JobRunner";
my $tool = JRHelper::cmd_which($toolb);
$tool = JRHelper::cmd_which(dirname(abs_path($0)) . "/$toolb.pl") if (! defined $tool);
$tool = JRHelper::cmd_which(dirname(abs_path($0)) . "/$toolb") if (! defined $tool);
my @watchdir = ();
my $sleepv = $dsleepv;
my $retryall = 0;
my $verb = 1;
my $random = undef;
my $sibj = 0;
my @dironce = ();
my @dironcebefore = ();
my $passreport = 0;
my $okquit = 0;
my $maxSet = -1;
my $timesort = "";
my $sp_lt = "";
my $sp_ltdir = "";
my $quitfile = JRHelper::get_tmpfilename();
unlink($quitfile);
$quitfile .= ".JobRunner_Caller." . JRHelper::epoch2str(JRHelper::get_scalar_currenttime());

my $csortt = undef;

my %opt = ();
GetOptions
  (
   \%opt,
   'help',
   'version',
   'JobRunner=s' => \$tool,
   'watchdir=s' => \@watchdir,
   'sleep=i'    => \$sleepv,
   'retryall'   => \$retryall,
   'quiet'      => sub {$verb = 0},
   'RandomOrder:-99' => \$random,
   'SleepInBetweenJobs=i' => \$sibj,
   'dironce=s'      => \@dironce,
   'DirOnceBefore=s' => \@dironcebefore,
   'endSetReport=i' => \$passreport,
   'okquit'     => \$okquit,
   'maxSet=i'   => \$maxSet,
   'timeSort=s' => \$timesort,
   'ExtraLockingTool=s' => \$sp_lt,
   'LockingToolLockDir=s' => \$sp_ltdir,
   'QuitFile=s' => \$quitfile,
   'customSortTool=s' => \$csortt,
  ) or JRHelper::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");
JRHelper::ok_quit("\n$usage\n\nAutoDection of \'$toolb\' found: $tool\n") if ($opt{'help'});
JRHelper::ok_quit("$versionid\n") if ($opt{'version'});

JRHelper::error_quit("Problem with \'$toolb\' tool ($tool): not found")
  if ((! defined $tool) || (! JRHelper::does_file_exist($tool)));
my $err = JRHelper::check_file_x($tool);
JRHelper::error_quit("Problem with \'$toolb\' tool ($tool): $err")
  if (! JRHelper::is_blank($err));

JRHelper::error_quit("\SleepInBetweenJobs\' values must be positive ($sibj)")
  if ($sibj < 0);

my $tmpv = (defined $random) ? 1 : 0;
$tmpv += (! JRHelper::is_blank($timesort)) ? 1 : 0;
$tmpv += (defined $csortt) ? 1 : 0;
JRHelper::error_quit("Only one of \'Random\', \'timeSort\' and \'customSortTool\' can not be used at a time")
  if ($tmpv > 1);
      
JRHelper::error_quit("Unknow \'timeSort\' value ($timesort), valid options are: $ts_okv_txt")
  if ((! JRHelper::is_blank($timesort)) && (! grep(m%^$timesort$%, @ts_okv)));

my $csortt_if = "";
my $csortt_of = "";
if (defined $csortt) {
  my $err = JRHelper::check_file_x($csortt);
  JRHelper::error_quit("Problem with \'customSortTool\' tool ($csortt): $err")
    if (! JRHelper::is_blank($err));
  $csortt_if = JRHelper::get_tmpfilename();
  $csortt_of = JRHelper::get_tmpfilename();
}

if (! JRHelper::is_blank($sp_lt)) {
  my $err = JRHelper::check_file_x($sp_lt);
  JRHelper::error_quit("Problem with \'ExtraLockingTool\' ($sp_lt): $err")
    if (! JRHelper::is_blank($err));
  JRHelper::error_quit("When using \'ExtraLockingTool\', a \'LockingToolLockDir\' must be specified")
    if (JRHelper::is_blank($sp_ltdir));
  $err = JRHelper::check_dir_w($sp_ltdir);
  JRHelper::error_quit("Problem with \'LockingToolLockDir\' ($sp_ltdir): $err")
    if (! JRHelper::is_blank($err));
}

my $randi = 0;
my $rands = 0;
my @randa = ();
if (defined $random) {
  $random = time() if ($random == -99);
  srand($random);
  # just to be safe (if anything were to use "rand()" it would change the order)
  # -> get 10K entries in advance
  set_randa(10000);
}

my $kdi = 1; # keep doing it

my %alldone = ();
my %todo = ();
my %done = ();
my $todoc = 0;
my $donec = 0;
my %notdone = ();

my %allsetsdone = ();
my $set = 1;

# Infinite run unless not in watchdir mode (and no maxSet requested)
$maxSet = 1 if (($maxSet == -1) && (scalar @watchdir == 0));
# create the quitfile
JRHelper::error_quit("Problem writing to \'QuitFile\' ($quitfile)")
  if (! JRHelper::writeTo($quitfile, "", 0, 0, JRHelper::get_scalar_currenttime()));

sub __add2tobedone {
  my ($dir, $rtobedone, $ralldone) = @_;

  my $err = JRHelper::check_dir_r($dir);
  JRHelper::error_quit("Problem with directory ($dir): $err")
    if (! JRHelper::is_blank($err));
  my @in = JRHelper::get_files_list($dir);
  foreach my $file (@in) {
    my $ff = "$dir/$file";
    next if (exists $$ralldone{$ff});
    push @$rtobedone, $ff;
  }
}

do {{ # transform 'do' in a valid loop, see: http://perldoc.perl.org/perlsyn.html#Loop-Control
  if (! JRHelper::does_file_exist($quitfile)) {
      print " !! \'QuitFile\' disappeared, will exit after this loop iteration\n";
    $kdi = 0;
    next;
  } else { # Re-inforce date on the quit file (if the file exists to avoid deletion from inactivity in temp location)
      JRHelper::error_quit("Problem writing to \'QuitFile\' ($quitfile)")
          if (! JRHelper::writeTo($quitfile, "", 0, 0, JRHelper::get_scalar_currenttime()));
  }

  my $qtxt = "\% Reminder: to quit properly after a Job/during a Set, delete the \'QuitFile\': $quitfile";
  print "$qtxt\n";

  my @tobedone = ();
  %alldone = () if ($retryall);

  while (my $dir = shift @dironcebefore) { &__add2tobedone($dir, \@tobedone, \%alldone); }

  foreach my $dir (@watchdir) { &__add2tobedone($dir, \@tobedone, \%alldone); }

  while (my $dir = shift @dironce) { &__add2tobedone($dir, \@tobedone, \%alldone); }

  foreach my $file (@ARGV) {
    next if (exists $alldone{$file});
    push @tobedone, $file;
  }

  # Order @tobedone
  if (defined $random) { # Random
    @tobedone = sort _rand @tobedone;
  }
  if (! JRHelper::is_blank($timesort)) { # timeSort
    ($err, @tobedone) = JRHelper::sort_files($timesort, @tobedone);
    # we choose to not quit on error messages here, but at least let the user know
    JRHelper::warn_print("While sorting using JobID file's \'$timesort\': $err")
      if (! JRHelper::is_blank($err));
  }
  if (defined $csortt) { # customSortTool
    open CSORTT, ">$csortt_if"
      or JRHelper::error_quit("Problem creating \'customSortTool\' input file ($csortt_if): $!");
    print CSORTT  join("\n", @tobedone) . "\n";
    close CSORTT;
    my $csortt_cmd = "$csortt $csortt_if $csortt_of";
    my ($rc, $so, $se, $sig) = JRHelper::do_system_call($csortt_cmd);
    JRHelper::error_quit("Problem running \'customSortTool\': \n(stdout)$so\n(stderr)$se")
      if ($rc + $sig != 0);
    open CSORTT, "<$csortt_of"
      or JRHelper::error_quit("Problem opening \'customSortTool\' output file ($csortt_of): $!");
    @tobedone = <CSORTT>;
    close CSORTT;
    chomp @tobedone;
  }

  # Process @tobedone
  my $jrc_max = scalar @tobedone;
  for (my $jrc_i = 0; $jrc_i < $jrc_max && $kdi == 1; $jrc_i++) {
    my $jrc = $tobedone[$jrc_i];

    # Check+recreate(touch) QuitFile
    if (! JRHelper::does_file_exist($quitfile)) {
      $kdi = 0;
      next;
    }
    JRHelper::error_quit("Problem writing to \'QuitFile\' ($quitfile)")
      if (! JRHelper::writeTo($quitfile, "", 0, 0, JRHelper::get_scalar_currenttime()));

    next if (exists $alldone{$jrc});

    $todo{$jrc}++;

    my ($ok, $txt, $ds, $msg, $sp_lf) = &doit($jrc, $jrc_i, $jrc_max);
    if (! JRHelper::is_blank($txt)) {
      print "$txt\n";
      print "$qtxt\n" if (! JRHelper::is_blank($qtxt));
    }

    if ((! JRHelper::is_blank($sp_lf)) && ($ok == -99)) {
      # not able to mutex this jobid, try later
      print "  !! Skipping job for now: Unable to obtain ExtraLock ($sp_lf)\n";
      $sp_lf = ""; # safeguard
      next;
    }
      
    # release the "mutex"
    unlink($sp_lf) if (! JRHelper::is_blank($sp_lf));

    if ($ok) {
      $done{$jrc}++;
      delete $notdone{$jrc};
    }

    $notdone{$jrc} = $msg if (! JRHelper::is_blank($msg));

    if (($ds) && ($sibj)) {
#      print "$qtxt\n" if (! JRHelper::is_blank($qtxt));
      print " (waiting $sibj seconds)\n";
      sleep($sibj);
    }

  }
  
  $todoc = scalar(keys %todo);
  $donec = scalar(keys %done);
  print "\n\n%%%%%%%%%% Set " . $set++ . " run results: $donec / $todoc %%%%%%%%%%\n";
  if ($passreport) {
    print "%%% Configurations files -- Set Report:\n";
    my %tmpr = ();
    foreach my $v (sort keys %notdone) { push @{$tmpr{$notdone{$v}}}, $v; }
    foreach my $v (sort keys %tmpr) {
      print " ** \"$v\" found in:\n     - " . join("\n     - ", @{$tmpr{$v}}) . "\n";
    }
  }
  
  $maxSet--;
  $kdi = 0 if ($maxSet == 0);

  if ($kdi) {
    print "$qtxt\n" if (! JRHelper::is_blank($qtxt));
    print " (waiting $sleepv seconds)\n";
    sleep($sleepv);
  }

}} while ($kdi);

print "Done ($donec / $todoc)\n";

JRHelper::ok_exit() if (($okquit) || ($donec == $todoc));
JRHelper::error_exit();

########################################

sub __cleanmsg {
  return("") if ($passreport == 0);

  # check every JobRunner's 'ok_quit' for string and adapt message

  # level > 2
  return(($passreport > 2) ? "Job successfully completed" : "") if ($_[0] =~ m%Previously\ssuccessfully\scompleted$%);
  return(($passreport > 2) ? "Job successfully completed" : "") if ($_[0] =~ m%Previously\ssuccessfully\scompleted\,\sand.+$%);
  return(($passreport > 2) ? "Job successfully completed" : "") if ($_[0] =~ m%Job\ssuccessfully\scompleted$%);

  # level > 1
  return(($passreport > 1) ? $1 : "") if ($_[0] =~ m%(Job\salready\sin\sprogress\,\sSkipping)$%);

  # just in case user need a status on jobs
  return($1) if ($_[0] =~ m%(Skip\srequested)$%);
  return($1) if ($_[0] =~ m%(Previous\sbad\srun\spresent\,\sskipping)$%);
  return($1) if ($_[0] =~ m%(\\\'RunIfTrue\\\'\scheck\sdid\snot\ssucceed.+)$%);
  
  #
  return("UNKNOWN: " . $_[0]);
}

##

sub doit {
  my ($jrc, $jrc_i, $jrc_max) = @_;

  my $sp_lf = "";
  if (! JRHelper::is_blank($sp_lt)) {
   my $file = $jrc;
   $file =~ s%^.+/%%;
   $sp_lf = "$sp_ltdir/$file";
   my @cmd = ($sp_lt, $sp_lf);
   my ($rc, $so, $se) = JRHelper::do_system_call(@cmd);

   # we were not able to get the lock/mutex ... somebody else is doing this job, skip
   return(-99, "", 0, "", $sp_lf) if ($rc != 0);

   # we have the insured mutex, continue
  }

  # whatever happens after here, we will not redo this entry (at least this set)
  $alldone{$jrc}++;
  $allsetsdone{$jrc}++; # if > 1 it means we have already done it in the past
  # and therefore do not print "skip" info anymore

  my $header = sprintf("\n\n[**] (%s : %d/%d) Job Runner Config: \'%s\'",
                       JRHelper::epoch2str(JRHelper::get_scalar_currenttime()), 
                       1+$jrc_i, $jrc_max, $jrc);

  my $err = JRHelper::check_file_r($jrc);
  return(0,
         (($allsetsdone{$jrc} < 2) 
         ? "$header\n  !! Skipping -- Problem with file ($jrc): $err"
         : ""), 0, "File Issue: $err", $sp_lf) if (! JRHelper::is_blank($err));
  
  $err = &check_header($jrc);
  return(0,
         (($allsetsdone{$jrc} < 2)
         ? "$header\n  -- Skipping -- $err"
         : ""), 0, $err, $sp_lf) if (! JRHelper::is_blank($err));

  my $jb_cmd = "$tool -u $jrc";

  my $tjb_cmd = "$jb_cmd -O";
  my ($rc, $so, $se, $sig) = JRHelper::do_system_call($tjb_cmd);

  return(1,
         ($allsetsdone{$jrc} < 2)
         ? ("$header\n  @@ Can be skipped" . ($verb ? "\n(stdout)$so" : ""))
         : "", 0, &__cleanmsg($so), $sp_lf) if ($rc + $sig == 0);
  
  if ($rc == 1) {
    if (JRHelper::is_blank($se)) { # no warning, check if all "errors" are just "Problem with 'checkfile' [file] : file does not exist"
      my @errs = split(m%\n%, $so);
      my $cfc = 1;
      foreach my $errline (@errs) {
        $errline =~ s%^\[ERROR\]\s*%%;
        next if (JRHelper::is_blank($errline));
        next if ($errline =~ m%Problem with \'checkfile\'%);
        $cfc = 0;
        last;
      }
      return(1, "$header\n  == Awaiting for \'checkfile\'", 0, "Awaiting for \'checkfile\'", $sp_lf) if ($cfc == 1);
    }
    
    return(1, "$header\n  ?? Possible Problem" . 
           ($verb ? "\n(stdout)$so\n(stderr)$se" : ""), 0, "Possible Problem", $sp_lf);
  }

  ## To be run ? run it !
  # and now really print the header
  print "$header\n";

  my $showpid_tf = JRHelper::get_tmpfilename();
  JRHelper::set_showpid_load_file($showpid_tf);
  $jb_cmd .= " --writePID $showpid_tf";
  my ($rc, $so, $se, $sig) = JRHelper::do_system_call($jb_cmd);
  JRHelper::set_showpid_load_file(undef);

  return(1, "  ++ Job completed" . ($verb ? "\n(stdout)$so" : ""), 1, "", $sp_lf)
    if ($rc + $sig == 0);
  
  return(0, "  ** ERROR Run" . ($verb ? "\n(stdout)$so\n(stderr)$se" : ""), 1, "ERROR RUN", $sp_lf);
}

#####

sub check_header {
  my $jrc = $_[0];
  
  open FILE, "<$jrc"
    or return("Problem opening file ($jrc) : $!");
  
  my $header = <FILE>;
  chomp $header;
  close FILE;
  
#  print "[$header]\n";
  return("File header is not the expected text")
    if ($header ne "# Job Runner Configuration file");

  return("");
}

##########

sub set_randa {
  for (my $i = 0; $i < $_[0]; $i++) {
    push @randa, rand();
  }
  $rands = scalar @randa;
}

#####

sub get_rand {
  JRHelper::error_quit("Can not get pre computed rand() value from array (no content)")
    if ($rands == 0);
  my $mul = (defined $_[0]) ? $_[0] : 1;
  my $v = $mul * $randa[$randi];
  $randi++;
  $randi = 0 if ($randi >= $rands);
  return($v);
}

#####

sub _num { $a <=> $b; }

##

sub _rand { &get_rand(100) <=> &get_rand(100); }

########################################

sub set_usage {  
  my $tmp=<<EOF
$versionid

$0 [--help | --version] [--JobRunner executable] [--quiet] [--endSetReport level] [--SleepInBetweenJobs seconds] [--watchdir dir [--watchdir dir [...]] [--maxSet number] [--sleep seconds] [--retryall]] [--DirOnceBefore dir [--DirOnceBefore dir [...]]] [--dironce dir [--dironce dir [...]]] [--timeSort mode | --RandomOrder [seed] | --customSortTool tool] [--okquit] [--ExtraLockingTool tool [--LockingToolLockDir dir]] [--QuitFile location] [JobRunner_configfile [JobRunner_configfile [...]]]

Will execute JobRunner jobs 

Where:
  --help       This help message
  --version    Version information
  --JobRunner  Location of executable tool (if not in PATH, will also look for it tool dir)
  --quiet      Do not print stdout/stderr data from system calls
  --endSetReport  At the end of a set, print a report of job status (bypassing successfully completed jobs) (\'level\' 1 is to not print \'already in progress\' jobs, use a \'level\' of 2 to add those, and level '3' to add successfully completed jobs)
  --SleepInBetweenJobs  Specify the number of seconds to sleep in between two consecutive jobs (example: when a job check the system load before running using JobRunner\'s \'--RunIfTrue\', this allow the load to drop some) (default is not to sleep)
  --watchdir   Directory to look for configuration files [*]
  --maxSet     Specify the maximum number of set to to in \'watchdir\' mode (default is to continue without end)
  --sleep      Specify the sleep time in between sets (default: $dsleepv)
  --retryall   When running a different set, retry all previously completed entries (especially useful when when a JobRunner configuration uses \'--badErase\' or \'--RunIfTrue\')
  --DirOnceBefore    Directory to look for configuration files only once (before \'--watchdir\')
  --dironce    Directory to look for configuration files only once (after \'--watchdir\')
  --timeSort   Run jobs in configuration files\' Access Time, Creation Time, Modification Time order, instead of the order they are provided. Valid values: $ts_okv_txt
  --RandomOrder  Run jobs in random order instead of the order they are provided (can help with multiple lock dir access over NFS if the data is not propagated from server yet) (note: if providing a random seed --which must be over 0-- use different values for multiple JobRunner_Caller, or simply do not provide any and the current \'time\' value will be used)
  --customSortTool   Run the provided \'tool\' with two arguments: 1) a file containing the list of all the Jobs files to be run (full path, one per line) 2) the name of a file expected to contain the sorted list (same entry than in the input file, full path, one entry per line), sorted with the job to be run first at the top of the list, and last at the bottom of the list
  --okquit     The default is to exit with the error status if the \"done\" vs \"todo\" count is not the same, this bypass this behavior and exit with the ok status
  --ExtraLockingTool  Specify the full path location of a special locking tool used to create a mutual exclusion for a JobID execution (**)
  --LockingToolLockDir  Directory in which the ExtraLockingTool lock for JobID will be created
  --QuitFile   Location of a file that will be created by the tool and used to let it know to stop processing if the file has disappeared (default is to use a random file location, that will be displayed at the beginning of each set)


*: in this mode, the program will complete a full run then on the files found in this directory, then sleep \'--sleep\' seconds before re-reading the directory content and see if any new configuration file is present, before running it. The program will never stop, it is left to the user to stop the program.

**: this is extremely important for queues on network shares (such as NFS), specify the tool that is know to create a safe exclusive access lock file on such a network share. The tool (or wrapper script) must: 1) take only one argument, the lock file location. 2) create the lock file but not erase it (this is done by $0 after job completion). 3) return the 0 exit status if the lock was obtained, any other status otherwise.


Job Processing Order: Unless \'--RandomOrder\', \'--timeSort\' or \'--customSortTool\' are used, jobs are processed in the following order: first the \'--DirOnceBefore\' configuration files, then the \'--watchdir\' configuration files, followed by the \'--dironce\' ones, finally the command lines ones. Then, if the tool is in \'--watchdir\' mode, it will do an infinite number of passes on those files (unless \'--maxSet\' runs if used)

WARNING: the tool is designed to pass any 'ctrl+C' keyboard input to the \'JobRunner\' tool. To end a \'JobRunner_Caller\' in \'--watchdir\' mode (before any \'--maxSet\' completion if set) it is recommend to use the \'kill\' or \'killall\' commands, or to \'ctrl+z\' and then \'kill\' the \"suspended\" job (or to kill it during its \"sleep\" times)

EOF
;

  return($tmp);
}
