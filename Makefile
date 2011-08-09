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
	@echo "  cvsdist   Make the tar.bz2 distribution file"
	@echo ""
	@echo ""

from_installdir:
	@echo "** Checking that \"make\" is called from the source directory"
	@test -f ${JOBRUNNER_VERSION}


# 'cvsdist' can only be run by developpers
cvsdist:
	@make from_installdir
	@make dist_head
	@echo ""
	@echo ""
	@echo "Building a CVS release:" `cat ${JOBRUNNER_VERSION}`
	@rm -rf /tmp/`cat ${JOBRUNNER_VERSION}`
	@echo "CVS checkout in: /tmp/"`cat ${JOBRUNNER_VERSION}`
	@cp ${JOBRUNNER_VERSION} /tmp
	@(cd /tmp; cvs -z3 -q -d gaston:/home/sware/cvs checkout -d `cat ${JOBRUNNER_VERSION}` JOBRUNNER)
	@make dist_common
	@echo ""
	@echo ""
	@echo "***** Did you REMEMBER to update the version number and date in the README file ? *****"
	@echo "   do a 'make cvs-tag-current-distribution' here "


dist_head:
	@echo "***** Checking ${JOBRUNNER_VERSION}"
	@test -f ${JOBRUNNER_VERSION}
	@fgrep JobRunner ${JOBRUNNER_VERSION} > /dev/null

dist_archive_pre_remove:
	@rm -rf /tmp/`cat ${JOBRUNNER_VERSION}`/${JOBRUNNER_VERSION}
	@rm -rf /tmp/`cat ${JOBRUNNER_VERSION}`/Makefile

dist_common:
	@cp ${JOBRUNNER_VERSION} /tmp
	@make dist_archive_pre_remove
	@echo ""
	@echo "Building the tar.bz2 file"
	@echo `cat ${JOBRUNNER_VERSION}`"-"`date +%Y%m%d-%H%M`.tar.bz2 > /tmp/.JOBRUNNER_distname
	@echo `pwd` > /tmp/.JOBRUNNER_pwd
	@(cd /tmp; tar cfj `cat /tmp/.JOBRUNNER_pwd`/`cat /tmp/.JOBRUNNER_distname` --exclude CVS --exclude .DS_Store --exclude "*~" `cat ${JOBRUNNER_VERSION}`)
	@echo ""
	@echo ""
	@echo "** Release ready:" `cat /tmp/.JOBRUNNER_distname`
#	@make dist_clean

dist_clean:
	@rm -rf /tmp/`cat ${JOBRUNNER_VERSION}`
	@rm -f /tmp/.JOBRUNNER_{distname,version,pwd}

##########

cvs-tag-current-distribution:
	@make from_installdir
	@make dist_head
	@echo "Tagging the current CVS for distribution as '"`sed 's/\./dot/g' ${JOBRUNNER_VERSION}`"'"
	@(echo -n "Starting actual tag in "; for i in 10 9 8 7 6 5 4 3 2 1 0; do echo -n "$$i "; sleep 1; done; echo " -- Tagging")
	@cvs tag `sed 's/\./dot/g' ${JOBRUNNER_VERSION}`
