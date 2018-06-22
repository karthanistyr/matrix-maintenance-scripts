#!/bin/sh

while [[ $# -gt 0 ]]
do
arg="$1"

case $arg in
	-d|--directory)
		BACKUP_DIRECTORY=${2}
		shift
		shift
		;;
	-w|--weekly-dir)
		BACKUP_WEEKLY_DIR=${2}
		shift
		shift
		;;
	*)
		echo "Unknown argument: ${arg}"
		exit 255
		;;
esac
done

# echo back the selected values
echo "### Arguments and their values:"
echo
echo "BACKUP_DIRECTORY = ${BACKUP_DIRECTORY}"
echo "BACKUP_WEEKLY_DIR = ${BACKUP_WEEKLY_DIR}"
echo

# stop right away if a single arg is missing
if [[ -z ${BACKUP_DIRECTORY} \
	|| -z ${BACKUP_WEEKLY_DIR} ]]
then
	echo "Not all arguments were provided."
	exit 1
fi

#magic vars
BACKUP_NAME_PATTERN="matrix-backup"


# sanity check -- the backup directory must exist
if [[ ! -d "${BACKUP_DIRECTORY}" ]]
then
	echo "Could not find directory '${BACKUP_DIRECTORY}'"
	exit 1
fi

# sanity check -- the weekly directory should exist
if [[ ! -d "${BACKUP_WEEKLY_DIR}" ]]
then
	mkdir -p "${BACKUP_WEEKLY_DIR}"
fi

for save_folder in $(find ${BACKUP_DIRECTORY}/* -maxdepth 0 -type d -name "${BACKUP_NAME_PATTERN}*" | sort -d | tail --lines=1)
do
	cp -r "${save_folder}" "${BACKUP_WEEKLY_DIR}"
done

