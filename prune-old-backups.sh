#!/bin/sh -x

while [[ $# -gt 0 ]]
do
arg="$1"

case $arg in
	-d|--directory)
		BACKUP_DIRECTORY=${2}
		shift
		shift
		;;
	-n|--number)
		BACKUP_RETAIN_NUMBER=${2}
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
echo "BACKUP_RETAIN_NUMBER = ${BACKUP_RETAIN_NUMBER}"
echo

# stop right away if a single arg is missing

if [[ -z ${BACKUP_DIRECTORY} \
	|| -z ${BACKUP_RETAIN_NUMBER} ]]
then
	echo "Not all arguments were provided."
	exit 1
fi

# magic vars
BACKUP_NAME_PATTERN="matrix-backup"

if [[ ! -d ${BACKUP_DIRECTORY} ]]
then
	echo "Could not find directory '${BACKUP_DIRECTORY}'"
	exit 1
fi

cd "${BACKUP_DIRECTORY}"

for save_folder in $(find * -maxdepth 0 -type d -name "${BACKUP_NAME_PATTERN}*" | sort -d | head --lines=-${BACKUP_RETAIN_NUMBER})
do
	# I do not trust myself for running rm -rf without this check
	if echo ${save_folder} | grep ${BACKUP_NAME_PATTERN} > /dev/null
	then
		rm -rf ${save_folder}
	fi
done
