# copies most rescent files from eplapp for updating to git.
SERVER=eplapp.library.ualberta.ca
USER=sirsi
REMOTE=~/Unicorn/EPLwork/anisbet/OCLC/
LOCAL=~/projects/oclc/
APP=oclc.pl
FTP=ftp.pl

put: test
	scp ${LOCAL}${APP} ${USER}@${SERVER}:${REMOTE}
get:
	scp ${USER}@${SERVER}:${REMOTE}${APP} ${LOCAL}
test:
	perl -c ${APP}
putftp: test_ftp
	scp ${LOCAL}${FTP} ${USER}@${SERVER}:${REMOTE}
test_ftp:
	perl -c ${FTP}
