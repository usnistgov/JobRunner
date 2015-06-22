#JobRunner
Version: 1.3.0 (April 4, 2013)


***JobRunner*** is a tool designed to *run* a *job*, ie to execute a command line or script that does not require user interaction, and take care of storing the program's output (standard error and standard out) in an easy to read log file. The tool is able to save *configuration files* (or *job description*) of the job to be run.

**JobRunner_Caller** is a tool designed to *call* JobRunner's *configuration files*, acting as a *queue processor*.

The tools were designed to work using directory lock mechanism instead of relying on a central networked server to dispatch jobs and aggregate log and job status information from networked clients.


INSTALLATION
------------

The tools do not need to be installed as they can be called from anywhere. As long as the files in the archive are together, it will work.

There is no installation mechanism for the tool, as it is a standalone tool and has only one internal dependency to a perl package (`JRHelper.pm`) containing a set of functions used by both tools (its Perl packages dependencies are only some core modules).

If you desire to make them available in your `PATH`, keep the files in location (where both executables and the perl package are located), and make symbolic links to the original perl executables, namely:
- with *uncompress_path* the location of both executables and the perl package
- with *install_path* a location that is part of your `PATH`

<pre>
% cd install_path
% ln -s uncompress_path/JobRunner.pl JobRunner
% ln -s uncompress_path/JobRunner_Caller.pl JobRunner_Caller
</pre>
Just remember not to remove the uncompressed version of the tools.


USAGE
-----

An informative help page can be obtained by executing the command with the option `--help`.

For examples of use, please look at the `JobRunner_Primer.html` file that should have included in this archive.


CONTACT
-------

Please send bug reports to: martial.michel@nist.gov

For the bug report to be useful, please include the command line, files and text output, including the error message in your email.


AUTHOR
------


	Martial Michel <martial.michel@nist.gov>
       

LICENSE 
---------

Full details can be found at: http://nist.gov/data/license.cfm

This software was developed at the National Institute of Standards and Technology by employees and/or contractors of the Federal Government in the course of their official duties.
Pursuant to Title 17 Section 105 of the United States Code this software is not subject to copyright protection within the United States and is in the public domain.

"JobRunner" is an experimental system.
NIST assumes no responsibility whatsoever for its use by any party.

THIS SOFTWARE IS PROVIDED "AS IS."  With regard to this software, NIST MAKES NO EXPRESS OR IMPLIED WARRANTY AS TO ANY MATTER WHATSOEVER, INCLUDING MERCHANTABILITY, OR FITNESS FOR A PARTICULAR PURPOSE.
