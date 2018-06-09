#!/bin/sh

BACKUP_TAG="matrix-backup_`date +"%F_%H-%M-%S.%N"`"

BACKUP_STAGING_DIR=${1}
BACKUP_LOCAL_REPOSITORY=${2}
BACKUP_REMOTE_REPOSITORY=${3}

SYNAPSE_DATA_DIR=${4}
SYNAPSE_DB_DIR=${5}

BACKUP_DIR=${BACKUP_TAG}
BACKUP_LOG_FILENAME="${BACKUP_TAG}.log"

function abort() {
	message=${1}
	code=${2}

	if [ -z "${message}" ]; then
		message="just aborting"
	fi
	if [ -z "${code}" ]; then
		code=1
	fi

	echo "###  Aborting for a reason: ${message} (code: ${code})" >> ${BACKUP_LOG_FILENAME}
	exit ${code}
}

function log() {
	logline=${1}
	echo "${logline}" >> ${BACKUP_LOG_FILENAME}
}

function run_and_log() {
	command=${1}
	log "Executing '${command}'..."
	sh -c "${command}" &>> ${BACKUP_LOG_FILENAME}
}

function run_critical() {
	command=${1}
	run_and_log "${command}"

	RET_CODE=$?
	if [ ${RET_CODE} -gt 0 ]; then
		abort "critical command encountered an error." ${RET_CODE}
	fi
}

function copy_path_remote() {
	source=${1}
	target=${2}

	# apply -r (recursive) which works both on folders and files
	run_critical "scp -r ${source} ${target}" 
}

function test_remote_path() {
	remote_path=${1}
	token_file="token_file"
	
	# test that remote target is valid by copying an empty file
	touch ${token_file}
	copy_path_remote ${token_file} ${remote_path}/${token_file}
}

### sanity check

if [ -d ${BACKUP_STAGING_DIR} ]; then
	cd ${BACKUP_STAGING_DIR}
else
	echo "Directory '${BACKUP_STAGING_DIR}' doesn't exist."
	exit 255
fi

### more sanity check

log "Checking that BACKUP_LOCAL_REPOSITORY '${BACKUP_LOCAL_REPOSITORY}' exists..."
if [ ! -d ${BACKUP_LOCAL_REPOSITORY} ]; then
	abort "Directory '${BACKUP_LOCAL_REPOSITORY}' doesn't exist." 1
fi

log "Checking that BACKUP_REMOTE_REPOSITORY '${BACKUP_REMOTE_REPOSITORY}' exists..."
test_remote_path ${BACKUP_REMOTE_REPOSITORY}
REMOTE_EXISTS=$?
if [ ${REMOTE_EXISTS} -gt 0 ]; then
        abort "Directory '${BACKUP_REMOTE_REPOSITORY}' doesn't exist." ${REMOTE_EXISTS}
fi

log "Checking that SYNAPSE_DATA_DIR '${SYNAPSE_DATA_DIR}' exists..."
if [ ! -d ${SYNAPSE_DATA_DIR} ]; then
        abort "Directory '${SYNAPSE_DATA_DIR}' doesn't exist." 1
fi
log "Checking that SYNAPSE_DB_DIR '${SYNAPSE_DB_DIR}' exists..."
if [ ! -d ${SYNAPSE_DB_DIR} ]; then
        abort "Directory '${SYNAPSE_DB_DIR}' doesn't exist." 1
fi


# create backup location
run_and_log "mkdir ${BACKUP_DIR}"

# stop the service
run_critical "systemctl stop docker-compose-matrix"

# tar.gz the matrix data folder
run_critical "tar -zcvf ${BACKUP_DIR}/${BACKUP_TAG}_data.tar.gz ${SYNAPSE_DATA_DIR}"
# tar.gz the database filesystem
run_critical "tar -zcvf ${BACKUP_DIR}/${BACKUP_TAG}_db.tar.gz ${SYNAPSE_DB_DIR}"

# restart the service
run_critical "systemctl start docker-compose-matrix"

# copy remote
copy_path_remote ${BACKUP_DIR} ${BACKUP_REMOTE_REPOSITORY}

#move backup to local repository
run_critical "mv ${BACKUP_DIR} ${BACKUP_LOCAL_REPOSITORY}"

# end - copy log files; this is not logged :)
cp ${BACKUP_LOG_FILENAME} ${BACKUP_LOCAL_REPOSITORY}/${BACKUP_DIR}
copy_path_remote ${BACKUP_LOG_FILENAME} ${BACKUP_REMOTE_REPOSITORY}/${BACKUP_DIR}
