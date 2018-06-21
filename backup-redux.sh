#!/bin/sh

### functions

function validate_directory_path() {
	dir_path="$1"
	[ -d ${dir_path} ]
}

function abort_with_reason() {
	reason="$1"
	if [[ -z ${reason} ]]
	then
		reason="an unspecified error occurred"
	fi

	code="$2"
	if [[ -z ${code} ]]
	then
		code=255
	fi

	echo "* ERROR: ${reason}"
	exit ${code}
}

function ts() {
	date +"%F %H:%M:%S.%N"
}

function echo_run() {
	command="${1}"
	echo "[$(ts)] ${command}"
	${command} 2>&1
	result=$?
	echo "Done; code: ${result}"
	if [[ ${result} -gt 0 && ${GLOBAL_EXIT_CODE} -eq 0 ]]
	then
		GLOBAL_EXIT_CODE=${result}
	fi
	return ${result}
}

function copy_path_remote() {
	source=${1}
	target=${2}

	# apply -r (recursive) which works both on folders and files
	echo_run "scp -r -i ${IDENTITY_FILE} ${source} ${target}"
}

function test_remote_path() {
	remote_path=${1}
	token_file="token_file"
	# test that remote target is valid by copying an empty file
	touch ${token_file}
	copy_path_remote ${token_file} ${remote_path}/${token_file}
	result=$?
	rm ${token_file}

	return ${result}
}

### program

while [[ $# -gt 0 ]]
do
arg="$1"

case $arg in
	-s|--staging-dir)
		BACKUP_STAGING_DIR="$2"
		shift
		shift
		;;
	-l|--local-repo)
		BACKUP_LOCAL_REPOSITORY="$2"
		shift
		shift
		;;
	-r|--remote-repo)
		BACKUP_REMOTE_REPOSITORY="$2"
		shift
		shift
		;;
	-d|--data-dir)
		BACKUP_SERVER_DATA_DIR="$2"
		shift
		shift
		;;
	-b|--db-dir)
		BACKUP_SERVER_DB_DIR="$2"
		shift
		shift
		;;
	-o|--owner)
		BACKUP_FILE_OWNER="$2"
		shift
		shift
		;;
	*)
		echo "Unknown argument: $1"
		exit 255
		;;
esac
done

# echo back the selected values
echo "### Arguments and their values:"
echo
echo "BACKUP_STAGING_DIR = ${BACKUP_STAGING_DIR}"
echo "BACKUP_LOCAL_REPOSITORY = ${BACKUP_LOCAL_REPOSITORY}"
echo "BACKUP_REMOTE_REPOSITORY = ${BACKUP_REMOTE_REPOSITORY}"
echo "BACKUP_SERVER_DATA_DIR = ${BACKUP_SERVER_DATA_DIR}"
echo "BACKUP_SERVER_DB_DIR = ${BACKUP_SERVER_DB_DIR}"
echo "BACKUP_FILE_OWNER = ${BACKUP_FILE_OWNER}"
echo


# stop right away if a single arg is missing

if [[ -z ${BACKUP_STAGING_DIR} \
	|| -z ${BACKUP_LOCAL_REPOSITORY} \
	|| -z ${BACKUP_REMOTE_REPOSITORY} \
	|| -z ${BACKUP_SERVER_DATA_DIR} \
	|| -z ${BACKUP_SERVER_DB_DIR} \
	|| -z ${BACKUP_FILE_OWNER} ]]
then
	abort_with_reason "You should provide all arguments."
fi


# here are a few magic variables

BACKUP_TAG="matrix-backup_`date +"%F_%H-%M-%S.%N"`"
BACKUP_DIR=${BACKUP_TAG}
IDENTITY_FILE="/home/${BACKUP_FILE_OWNER}/.ssh/id_rsa"
GLOBAL_EXIT_CODE=0 # hope for the best!

# sanity check -- the BACKUP_FILE_OWNER should exist
if ! id ${BACKUP_FILE_OWNER} &> /dev/null
then
	abort_with_reason "the user '${BACKUP_FILE_OWNER}' does not exist." 1
fi

# sanity check -- create and chown these if not existing
# don't modify if already existing

if ! validate_directory_path ${BACKUP_STAGING_DIR}
then
	echo_run "mkdir ${BACKUP_STAGING_DIR}"
	echo_run "chown ${BACKUP_FILE_OWNER}:${BACKUP_FILE_OWNER} ${BACKUP_STAGING_DIR}"
fi

if ! validate_directory_path ${BACKUP_LOCAL_REPOSITORY}
then
	echo_run "mkdir ${BACKUP_LOCAL_REPOSITORY}"
	echo_run "chown ${BACKUP_FILE_OWNER}:${BACKUP_FILE_OWNER} ${BACKUP_LOCAL_REPOSITORY}"
fi

# sanity check -- the remote repository must be writable
if ! test_remote_path ${BACKUP_REMOTE_REPOSITORY}
then
	abort_with_reason "the remote repository at '${BACKUP_REMOTE_REPOSITORY}' was not found or is not writable." 1
fi

# sanity check -- the data and db directories must exist
if ! validate_directory_path ${BACKUP_SERVER_DATA_DIR}
then
	abort_with_reason "the data directory '${BACKUP_SERVER_DATA_DIR}' 
	was not found."
fi

if ! validate_directory_path ${BACKUP_SERVER_DB_DIR}
then
	abort_with_reason "the database directory '${BACKUP_SERVER_DB_DIR}' was not found."
fi

# create the backup directory in the staging directory
echo_run "mkdir ${BACKUP_STAGING_DIR}/${BACKUP_DIR}"

# stop the matrix service temporarily
if echo_run "systemctl stop docker-compose-matrix"
then
	# create the backup archives
	echo_run "tar -zcf ${BACKUP_STAGING_DIR}/${BACKUP_DIR}/${BACKUP_TAG}_data.tar.gz ${BACKUP_SERVER_DATA_DIR}"
	echo_run "tar -zcf ${BACKUP_STAGING_DIR}/${BACKUP_DIR}/${BACKUP_TAG}_db.tar.gz ${BACKUP_SERVER_DB_DIR}"

	# restart the matrix service again
	echo_run "systemctl start docker-compose-matrix"

	copy_path_remote ${BACKUP_STAGING_DIR}/${BACKUP_DIR} ${BACKUP_REMOTE_REPOSITORY}
	echo_run "mv ${BACKUP_STAGING_DIR}/${BACKUP_DIR} ${BACKUP_LOCAL_REPOSITORY}"
	echo_run "chown -R ${BACKUP_FILE_OWNER}:${BACKUP_FILE_OWNER} ${BACKUP_LOCAL_REPOSITORY}/${BACKUP_DIR}"

	echo

	# display the docker processes
	echo_run "docker ps -a"
fi

echo "Exiting with code ${GLOBAL_EXIT_CODE}"
exit ${GLOBAL_EXIT_CODE}
