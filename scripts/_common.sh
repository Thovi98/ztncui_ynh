#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

nodejs_version=12

# dependencies used by the app
pkg_dependencies="g++"

#=================================================
# PERSONAL HELPERS
#=================================================

#=================================================
# EXPERIMENTAL HELPERS
#=================================================

#!/bin/bash

# Execute a command as another user
# usage: exec_as USER COMMAND [ARG ...]
ynh_exec_as() {
  local USER=$1
  shift 1

  if [[ $USER = $(whoami) ]]; then
    eval "$@"
  else
    sudo -u "$USER" "$@"
  fi
}

# Create a dedicated systemd config
#
# usage: ynh_add_systemd_config [--service=service] [--template=template]  [--others_var="list of others variables to replace"]
# | arg: -s, --service - Service name (optional, $app by default)
# | arg: -t, --template - Name of template file (optional, this is 'systemd' by default, meaning ./conf/systemd.service will be used as template)
# | arg: -v, --others_var - List of others variables to replace separated by a space. For example: 'var_1 var_2 ...'
#
# This will use the template ../conf/<templatename>.service
# to generate a systemd config, by replacing the following keywords
# with global variables that should be defined before calling
# this helper :
#
#   __APP__       by  $app
#   __FINALPATH__ by  $final_path
#
# And dynamic variables (from the last example) :
#   __VAR_1__    by $var_1
#   __VAR_2__    by $var_2
#
# Requires YunoHost version 2.7.2 or higher.
ynh_add_systemd_config_vars () {
	# Declare an array to define the options of this helper.
	local legacy_args=stv
	declare -Ar args_array=( [s]=service= [t]=template= [v]=others_var= )
	local service
	local template
	local others_var
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	service="${service:-$app}"
	template="${template:-systemd.service}"
	others_var="${others_var:-}"

	finalsystemdconf="/etc/systemd/system/$service.service"
	ynh_backup_if_checksum_is_different --file="$finalsystemdconf"
	cp ../conf/$template "$finalsystemdconf"

	# To avoid a break by set -u, use a void substitution ${var:-}. If the variable is not set, it's simply set with an empty variable.
	# Substitute in a nginx config file only if the variable is not empty
	if test -n "${final_path:-}"; then
		ynh_replace_string --match_string="__FINALPATH__" --replace_string="$final_path" --target_file="$finalsystemdconf"
	fi
	if test -n "${app:-}"; then
		ynh_replace_string --match_string="__APP__" --replace_string="$app" --target_file="$finalsystemdconf"
	fi

	# Replace all other variables given as arguments
	for var_to_replace in $others_var
	do
		# ${var_to_replace^^} make the content of the variable on upper-cases
		# ${!var_to_replace} get the content of the variable named $var_to_replace
		ynh_replace_string --match_string="__${var_to_replace^^}__" --replace_string="${!var_to_replace}" --target_file="$finalsystemdconf"
	done

	ynh_store_file_checksum --file="$finalsystemdconf"

	chown root: "$finalsystemdconf"
	systemctl enable $service
	systemctl daemon-reload
}

#=================================================
# FUTURE OFFICIAL HELPERS
#=================================================

n_install_dir="/opt/node_n"
node_version_path="$n_install_dir/n/versions/node"
# N_PREFIX is the directory of n, it needs to be loaded as a environment variable.
export N_PREFIX="$n_install_dir"

# Install Node version management
#
# [internal]
#
# usage: ynh_install_n
#
# Requires YunoHost version 2.7.12 or higher.
EXPERIMENTAL_ynh_install_n () {
	ynh_print_info --message="Installation of N - Node.js version management"
	# Build an app.src for n
	mkdir -p "../conf"
	echo "SOURCE_URL=https://github.com/tj/n/archive/v4.1.0.tar.gz
SOURCE_SUM=3983fa3f00d4bf85ba8e21f1a590f6e28938093abe0bb950aeea52b1717471fc" > "../conf/n.src"
	# Download and extract n
	ynh_setup_source --dest_dir="$n_install_dir/git" --source_id=n
	# Install n
	(cd "$n_install_dir/git"
	PREFIX=$N_PREFIX make install 2>&1)
}

# Load the version of node for an app, and set variables.
#
# ynh_use_nodejs has to be used in any app scripts before using node for the first time.
# This helper will provide alias and variables to use in your scripts.
#
# To use npm or node, use the alias `ynh_npm` and `ynh_node`
# Those alias will use the correct version installed for the app
# For example: use `ynh_npm install` instead of `npm install`
#
# With `sudo` or `ynh_exec_as`, use instead the fallback variables `$ynh_npm` and `$ynh_node`
# Exemple: `ynh_exec_as $app $ynh_npm install`
#
# $PATH contains the path of the requested version of node.
# However, $PATH is duplicated into $node_PATH to outlast any manipulation of $PATH
# You can use the variable `$ynh_node_load_PATH` to quickly load your node version
#  in $PATH for an usage into a separate script.
# Exemple: $ynh_node_load_PATH $final_path/script_that_use_npm.sh`
#
#
# Finally, to start a nodejs service with the correct version, 2 solutions
#  Either the app is dependent of node or npm, but does not called it directly.
#  In such situation, you need to load PATH
#    `Environment="__NODE_ENV_PATH__"`
#    `ExecStart=__FINALPATH__/my_app`
#     You will replace __NODE_ENV_PATH__ with $ynh_node_load_PATH
#
#  Or node start the app directly, then you don't need to load the PATH variable
#    `ExecStart=__YNH_NODE__ my_app run`
#     You will replace __YNH_NODE__ with $ynh_node
#
#
# 2 other variables are also available
#   - $nodejs_path: The absolute path to node binaries for the chosen version.
#   - $nodejs_version: Just the version number of node for this app. Stored as 'nodejs_version' in settings.yml.
#
# usage: ynh_use_nodejs
#
# Requires YunoHost version 2.7.12 or higher.
EXPERIMENTAL_ynh_use_nodejs () {
	nodejs_version=$(ynh_app_setting_get --app=$app --key=nodejs_version)

	# Get the absolute path of this version of node
	nodejs_path="$node_version_path/$nodejs_version/bin"

	# Allow alias to be used into bash script
	shopt -s expand_aliases

	# Create an alias for the specific version of node and a variable as fallback
	ynh_node="$nodejs_path/node"
	alias ynh_node="$ynh_node"
	# And npm
	ynh_npm="$nodejs_path/npm"
	alias ynh_npm="$ynh_npm"

	# Load the path of this version of node in $PATH
	[[ :$PATH: == *":$nodejs_path"* ]] || PATH="$nodejs_path:$PATH"
	node_PATH="$PATH"
	# Create an alias to easily load the PATH
	ynh_node_load_PATH="PATH=$node_PATH"
}

# Install a specific version of nodejs
#
# n (Node version management) uses the PATH variable to store the path of the version of node it is going to use.
# That's how it changes the version
#
# ynh_install_nodejs will install the version of node provided as argument by using n.
#
# usage: ynh_install_nodejs --nodejs_version=nodejs_version
# | arg: -n, --nodejs_version - Version of node to install. When possible, your should prefer to use major version number (e.g. 8 instead of 8.10.0). The crontab will then handle the update of minor versions when needed.
#
# Refer to ynh_use_nodejs for more information about available commands and variables
#
# Requires YunoHost version 2.7.12 or higher.
EXPERIMENTAL_ynh_install_nodejs () {
	# Use n, https://github.com/tj/n to manage the nodejs versions

	# Declare an array to define the options of this helper.
	local legacy_args=n
	declare -Ar args_array=( [n]=nodejs_version= )
	local nodejs_version
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"

	# Create $n_install_dir
	mkdir -p "$n_install_dir"

	# Load n path in PATH
	CLEAR_PATH="$n_install_dir/bin:$PATH"
	# Remove /usr/local/bin in PATH in case of node prior installation
	PATH=$(echo $CLEAR_PATH | sed 's@/usr/local/bin:@@')

	# Move an existing node binary, to avoid to block n.
	test -x /usr/bin/node && mv /usr/bin/node /usr/bin/node_n
	test -x /usr/bin/npm && mv /usr/bin/npm /usr/bin/npm_n

	# If n is not previously setup, install it
	if ! test $(n --version > /dev/null 2>&1)
	then
		ynh_install_n
	fi

	# Modify the default N_PREFIX in n script
	ynh_replace_string --match_string="^N_PREFIX=\${N_PREFIX-.*}$" --replace_string="N_PREFIX=\${N_PREFIX-$N_PREFIX}" --target_file="$n_install_dir/bin/n"

	# Restore /usr/local/bin in PATH
	PATH=$CLEAR_PATH

	# And replace the old node binary.
	test -x /usr/bin/node_n && mv /usr/bin/node_n /usr/bin/node
	test -x /usr/bin/npm_n && mv /usr/bin/npm_n /usr/bin/npm

	# Install the requested version of nodejs
	uname=$(uname -m)
	if [[ $uname =~ aarch64 || $uname =~ arm64 ]]
	then
		n $nodejs_version --arch=arm64
	else
		n $nodejs_version
	fi

	# Find the last "real" version for this major version of node.
	real_nodejs_version=$(find $node_version_path/$nodejs_version* -maxdepth 0 | sort --version-sort | tail --lines=1)
	real_nodejs_version=$(basename $real_nodejs_version)

	# Create a symbolic link for this major version if the file doesn't already exist
	if [ ! -e "$node_version_path/$nodejs_version" ]
	then
		ln --symbolic --force --no-target-directory $node_version_path/$real_nodejs_version $node_version_path/$nodejs_version
	fi

	# Store the ID of this app and the version of node requested for it
	echo "$YNH_APP_INSTANCE_NAME:$nodejs_version" | tee --append "$n_install_dir/ynh_app_version"

	# Store nodejs_version into the config of this app
	ynh_app_setting_set --app=$app --key=nodejs_version --value=$nodejs_version

	# Build the update script and set the cronjob
	ynh_cron_upgrade_node

	ynh_use_nodejs
}

# Remove the version of node used by the app.
#
# This helper will check if another app uses the same version of node,
# if not, this version of node will be removed.
# If no other app uses node, n will be also removed.
#
# usage: ynh_remove_nodejs
#
# Requires YunoHost version 2.7.12 or higher.
EXPERIMENTAL_ynh_remove_nodejs () {
	nodejs_version=$(ynh_app_setting_get --app=$app --key=nodejs_version)

	# Remove the line for this app
	sed --in-place "/$YNH_APP_INSTANCE_NAME:$nodejs_version/d" "$n_install_dir/ynh_app_version"

	# If no other app uses this version of nodejs, remove it.
	if ! grep --quiet "$nodejs_version" "$n_install_dir/ynh_app_version"
	then
		$n_install_dir/bin/n rm $nodejs_version
	fi

	# If no other app uses n, remove n
	if [ ! -s "$n_install_dir/ynh_app_version" ]
	then
		ynh_secure_remove --file="$n_install_dir"
		ynh_secure_remove --file="/usr/local/n"
		sed --in-place "/N_PREFIX/d" /root/.bashrc
		rm -f /etc/cron.daily/node_update
	fi
}

# Set a cron design to update your node versions
#
# [internal]
#
# This cron will check and update all minor node versions used by your apps.
#
# usage: ynh_cron_upgrade_node
#
# Requires YunoHost version 2.7.12 or higher.
ynh_cron_upgrade_node () {
	# Build the update script
	cat > "$n_install_dir/node_update.sh" << EOF
#!/bin/bash

version_path="$node_version_path"
n_install_dir="$n_install_dir"

# Log the date
date

# List all real installed version of node
all_real_version="\$(find \$version_path/* -maxdepth 0 -type d | sed "s@\$version_path/@@g")"

# Keep only the major version number of each line
all_real_version=\$(echo "\$all_real_version" | sed 's/\..*\$//')

# Remove double entries
all_real_version=\$(echo "\$all_real_version" | sort --unique)

# Read each major version
while read version
do
	echo "Update of the version \$version"
	sudo \$n_install_dir/bin/n \$version

	# Find the last "real" version for this major version of node.
	real_nodejs_version=\$(find \$version_path/\$version* -maxdepth 0 | sort --version-sort | tail --lines=1)
	real_nodejs_version=\$(basename \$real_nodejs_version)

	# Update the symbolic link for this version
	sudo ln --symbolic --force --no-target-directory \$version_path/\$real_nodejs_version \$version_path/\$version
done <<< "\$(echo "\$all_real_version")"
EOF

	chmod +x "$n_install_dir/node_update.sh"

	# Build the cronjob
	cat > "/etc/cron.daily/node_update" << EOF
#!/bin/bash

$n_install_dir/node_update.sh >> $n_install_dir/node_update.log
EOF

	chmod +x "/etc/cron.daily/node_update"
}
