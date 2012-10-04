# copies most rescent files from eplapp for updating to git.
SERVER=eplapp.library.ualberta.ca
USER=sirsi
# this is the test directory. Production is in cronjobscripts.
# this allows us to move test scripts to the server without
# affecting the existing production code.
REMOTE=~/Unicorn/EPLwork/anisbet/OCLC/
LOCAL=~/projects/oclc/
APP=oclc.pl
FTP=ftp.pl
WRAPPER_CANCELS=oclc_cancels.sh
WRAPPER_MIXED=oclc_mixed.sh

put: test
	scp ${LOCAL}${APP} ${USER}@${SERVER}:${REMOTE}
	scp ${LOCAL}${WRAPPER_CANCELS} ${USER}@${SERVER}:${REMOTE}
	scp ${LOCAL}${WRAPPER_MIXED} ${USER}@${SERVER}:${REMOTE}
get:
	scp ${USER}@${SERVER}:${REMOTE}${APP} ${LOCAL}
test:
	perl -c ${APP}
# these rules are for the FTP test script only.
putftp: test_ftp
	scp ${LOCAL}${FTP} ${USER}@${SERVER}:${REMOTE}
test_ftp:
	perl -c ${FTP}
