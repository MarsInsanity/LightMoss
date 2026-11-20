#!/bin/sh
# check-fragment.sh FRAGMENT CONFIG
#
# Fails when a line of the kernel config fragment did not make it into the
# final .config: "CONFIG_X=value" must be there exactly; "# CONFIG_X is not
# set" must not be set (a symbol whose dependencies are off is not written
# to .config at all, which is just as off).
set -u
fragment=$1 config=$2
status=0
while read -r line; do
	case "$line" in
	"# CONFIG_"*" is not set")
		sym=${line#"# "}
		sym=${sym%% *}
		if grep -q "^$sym=" "$config"; then
			echo "lightmoss-linux510: '$line' did not survive olddefconfig" >&2
			status=1
		fi
		;;
	CONFIG_*=*)
		if ! grep -qxF -- "$line" "$config"; then
			echo "lightmoss-linux510: '$line' did not survive olddefconfig" >&2
			status=1
		fi
		;;
	esac
done < "$fragment"
exit $status
