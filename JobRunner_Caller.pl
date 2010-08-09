#!/usr/bin/env perl
# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs

# Job Runner Caller
#
# Author(s): Martial Michel
#
# This software was developed at the National Institute of Standards and Technology by
# employees and/or contractors of the Federal Government in the course of their official duties.
# Pursuant to Title 17 Section 105 of the United States Code this software is not subject to 
# copyright protection within the United States and is in the public domain.
#
# "JobRunner Caller" is an experimental system.
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

my $versionid = "JobRunner Caller Version: $version";

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

my $usage = &set_usage();
MMisc::ok_quit("\n$usage\n") if (scalar @ARGV == 0);

# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz  #
# Used:                                  h             v      #

my $toolb = "JobRunner";
my $tool = (exists $ENV{$f4b}) ? MMisc::cmd_which($toolb) : "./$toolb.pl";
my %opt = ();
GetOptions
  (
   \%opt,
   'help',
   'version',
   'JobRunner=s' => \$tool,
  ) or MMisc::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");
MMisc::ok_quit("\n$usage\n") if ($opt{'help'});
MMisc::ok_quit("$versionid\n") if ($opt{'version'});

MMisc::error_quit("Problem with \'$toolb\' tool ($tool): not found")
  if ((! defined $tool) || (! MMisc::does_file_exists($tool)));
my $err = MMisc::check_file_x($tool);
MMisc::error_quit("Problem with \'$toolb\' tool ($tool): $err")
  if (! MMisc::is_blank($err));


my $todo = 0;
my $done = 0;
foreach my $jrc (@ARGV) {
  $todo++;
  print "\n\n[**] Job Runner Config: \'$jrc\'\n";
  my $err = MMisc::check_file_r($jrc);
  if (! MMisc::is_blank($err)) {
    print "  !! Skipping -- Problem with file ($jrc): $err\n";
    next;
  }
  
  $err = &check_header($jrc);
  if (! MMisc::is_blank($err)) {
    print "  -- Skipping -- $err\n";
    next;
  }

  my $jb_cmd = "$tool -u $jrc";

  my $tjb_cmd = "$jb_cmd -O";
  my ($rc, $so, $se) = MMisc::do_system_call($tjb_cmd);
  
  if ($rc == 0) {
    print  "  @@ Can be skipped\n$so\n";
    $done++;
    next;
  }
  
  if ($rc == 1) {
    print "  ?? Possible Problem\n$so\n$se\n";
    $done++;
    next;
  }

  ## To be run ? run it !
  my ($rc, $so, $se) = MMisc::do_system_call($jb_cmd);
  
  if ($rc == 0) {
    print  "  ++ Job completed\n$so\n";
    $done++;
    next;
  }
  
  print "  -- ERROR Run\n$so\n$se\n";
}

MMisc::ok_quit("Done ($done / $todo)\n");

########################################

sub check_header {
  my $jrc = $_[0];
  
  open FILE, "<$jrc"
    or return("Problem opening file ($jrc) : $!");
  
  my $header = <FILE>;
  chomp $header;
  close FILE;
  
  print "[$header]\n";
  return("File header is not the expected text")
    if ($header ne "# Job Runner Configuration file");

  return("");
}



########################################

sub set_usage {  
  my $tmp=<<EOF
$versionid

$0 [--help | --version] [--JobRunner executable] JobRunner_configfile [JobRunner_configfile [...]] 

Will execute JobRunner jobs 

Where:
  --help     This help message
  --version  Version information
  --JobRunner  Location of executable tool (if not in PATH)
EOF
;

  return($tmp);
}
