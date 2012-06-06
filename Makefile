# copies most rescent files from eplapp for updating to git.
SERVER=eplapp.library.ualberta.ca
USER=sirsi
REMOTE=~/Unicorn/EPLwork/anisbet/
LOCAL=~/projects/oclc/

put:
	scp ${LOCAL}oclc.pl ${USER}@${SERVER}:${REMOTE}
get:
	scp ${USER}@${SERVER}:${REMOTE}oclc.pl ${LOCAL}
test:
	perl -c oclc.pl
