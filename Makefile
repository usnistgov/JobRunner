# $Id:$

SHELL=/bin/bash

##########

JOBRUNNER_VERSION=.jobrunner_version

all:
	@echo "NOTE: Make sure to run this Makefile from the source directory"
	@echo ""
	@make from_installdir
	@make dist_head
	@echo "Version Information : " `cat ${JOBRUNNER_VERSION}`
	@echo ""
	@echo "Possible options are:"
	@echo "  gitdist   Make the tar.bz2 distribution file"
	@echo ""
	@echo ""

from_installdir:
	@echo "** Checking that \"make\" is called from the source directory"
	@test -f ${JOBRUNNER_VERSION}


# 'gitdist' can only be run by developpers
gitdist:
	@make from_installdir
	@make dist_head
	@echo ""
	@echo ""
	@echo "Building a GIT release:" `cat ${JOBRUNNER_VERSION}`
	@rm -rf /tmp/`cat ${JOBRUNNER_VERSION}`
	@echo "GIT checkout in: /tmp/"`cat ${JOBRUNNER_VERSION}`
	@cp ${JOBRUNNER_VERSION} /tmp
	@(cd /tmp; mkdir `cat ${JOBRUNNER_VERSION}`; cd `cat ${JOBRUNNER_VERSION}`; git clone git@github.com:usnistgov/JobRunner.git .)
	@make dist_usage
	@make dist_common
	@echo ""
	@echo ""
	@echo "***** Did you REMEMBER to update the version number and date in the README.md and .jobrunner_version files ? *****"
	@echo "   do a 'make git-tag-current-distribution' here "

make_html_usage:
	@echo "<html><head><title>JobRunner Usage</title><style type=\"text/css\">pre { border-style: solid; border-width: 1px; margin-left: 5px; padding: 2px 2px 2px 2px; background-color: #DDDDDD; white-space: -moz-pre-wrap; white-space: -pre-wrap; white-space: -o-pre-wrap; white-space: pre-wrap; word-wrap: break-word; }</style></head><body><pre>" > JobRunner-usage.html
	@./JobRunner.pl --help >> JobRunner-usage.html
	@echo "</pre></body></html>" >> JobRunner-usage.html
	@echo "<html><head><title>JobRunner_Caller Usage</title><style type=\"text/css\">pre { border-style: solid; border-width: 1px; margin-left: 5px; padding: 2px 2px 2px 2px; background-color: #DDDDDD; white-space: -moz-pre-wrap; white-space: -pre-wrap; white-space: -o-pre-wrap; white-space: pre-wrap; word-wrap: break-word; }</style></head><body><pre>" > JobRunner_Caller-usage.html
	@./JobRunner_Caller.pl --help >> JobRunner_Caller-usage.html
	@echo "</pre></body></html>" >> JobRunner_Caller-usage.html


dist_usage:
	@(cd /tmp/`cat ${JOBRUNNER_VERSION}`; make make_html_usage)

dist_head:
	@echo "***** Checking ${JOBRUNNER_VERSION}"
	@test -f ${JOBRUNNER_VERSION}
	@fgrep JobRunner ${JOBRUNNER_VERSION} > /dev/null

dist_archive_pre_remove:
	@rm -rf /tmp/`cat ${JOBRUNNER_VERSION}`/.git*
	@rm -f /tmp/`cat ${JOBRUNNER_VERSION}`/Makefile

dist_common:
	@cp ${JOBRUNNER_VERSION} /tmp
	@make dist_archive_pre_remove
	@echo ""
	@echo "Building the tar.bz2 file"
	@echo `cat ${JOBRUNNER_VERSION}`"-"`date -u +%Y%m%d-%H%M`"Z.tar.bz2" > /tmp/.JOBRUNNER_distname
	@echo `pwd` > /tmp/.JOBRUNNER_pwd
	@(cd /tmp; tar cfj `cat /tmp/.JOBRUNNER_pwd`/`cat /tmp/.JOBRUNNER_distname` --exclude .DS_Store --exclude "*~" `cat ${JOBRUNNER_VERSION}`)
	@md5 `cat /tmp/.JOBRUNNER_distname` > `cat /tmp/.JOBRUNNER_distname`.md5	
	@echo ""
	@echo ""
	@echo "** Release ready:" `cat /tmp/.JOBRUNNER_distname`
#	@make dist_clean

dist_clean:
	@rm -rf /tmp/`cat ${JOBRUNNER_VERSION}`
	@rm -f /tmp/.JOBRUNNER_{distname,version,pwd}

##########

git-tag-current-distribution:
	@make from_installdir
	@make dist_head
	@echo "Tagging the current GIT for distribution as '"`sed 's/\./dot/g' ${JOBRUNNER_VERSION}`"'"
	@(echo -n "Starting actual tag in "; for i in 10 9 8 7 6 5 4 3 2 1 0; do echo -n "$$i "; sleep 1; done; echo " -- Tagging")
	@git tag -a -m `sed 's/\./dot/g' ${JOBRUNNER_VERSION}` `sed 's/\./dot/g' ${JOBRUNNER_VERSION}`
