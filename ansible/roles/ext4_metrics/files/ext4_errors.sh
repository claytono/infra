#!/bin/sh
# Prints the error count ext4 keeps for each mounted filesystem, in the
# node_exporter textfile format. ext4 stores the count in the superblock
# and only e2fsck clears it, so a non-zero value means the filesystem
# has had an error since it was last checked. A filesystem whose
# journal has aborted keeps showing as mounted read-write while every
# read and write fails, and this count is the only metric that shows it.
set -eu

echo '# HELP node_ext4_errors Errors ext4 has recorded since the filesystem was last checked.'
echo '# TYPE node_ext4_errors gauge'
for dir in /sys/fs/ext4/*/; do
	# set -e does not see a failed command substitution inside printf's
	# arguments, so read the count first and skip a filesystem that was
	# unmounted after the glob ran.
	count=$(cat "${dir}errors_count" 2>/dev/null) || continue
	dev=${dir%/}
	dev=${dev##*/}
	# Kubernetes mounts a volume under .../kubernetes.io~csi/<pv>/mount;
	# name the PV so the alert says which volume failed.
	pv=$(awk -v d="/dev/$dev" '$1 == d && $2 ~ /kubernetes\.io~csi\/[^/]+\/mount$/ { n = split($2, p, "/"); print p[n - 1]; exit }' /proc/mounts)
	printf 'node_ext4_errors{device="%s",pv="%s"} %s\n' "$dev" "$pv" "$count"
done
