##################################################
# PATH Modifications
##################################################
# If we are on WSL (path contains /mnt/c/), delete the following dirs from PATH to make it less laggy
if [[ "$PATH" == *"/mnt/c/"* ]]; then
    if type "perl" > /dev/null; then
        PATH=$(echo "$PATH" | perl -pe "s|\/mnt\/c\/Program Files \(x86\)\/.*?:||g")
        PATH=$(echo "$PATH" | perl -pe "s|\/mnt\/c\/Program Files\/.*?:||g")
        # VSCode is in Users dir so lets not delete it
        # PATH=$(echo "$PATH" | perl -pe "s|\/mnt\/c\/Users\/.*?:||g")
        # For some reason Windows folder has duplicated entries, lets delete the uppercase one
        PATH=$(echo "$PATH" | perl -pe "s|\/mnt\/c\/WINDOWS.*?:||g")
    else
        echo "TBM13 Plugin: Install perl to delete unwanted Windows entries from PATH"
    fi
fi

# If ~/bin directory exists, add it to PATH
if [ ! -d "~/bin" ]; then
    PATH="$PATH:$HOME/bin"
fi

##################################################
# Variables
##################################################
WIN_DRIVE="/mnt/c"
USL="$WIN_DRIVE/USL"

PHOME="$WIN_DRIVE/Users/mateo"
PD="$PHOME/Desktop"
PDOC="$PHOME/Documents"
PDL="$PHOME/Downloads"

##################################################
# Aliases
##################################################
alias bkernel="build_kernel"
alias chls="stat -c '%a %n' *"
alias dif="code --diff"
alias gcd="git clone --depth=1"
alias gcds="git clone --depth=1 --single-branch"
alias gcs="git clone --single-branch"
alias python="python3"
alias py="python3"

##################################################
# Utils
##################################################
log_warn() {
	printf '\n\033[1;33mWarn:\033[0;33m ';
	printf '%s ' $1;
	printf '\033[0m\n';
}
log_error() {
	printf '\n\033[1;31mError:\033[0;31m ';
	printf '%s ' $1;
	printf '\033[0m\n';
}
log_success() {
	printf '\033[0;32m';
	printf '%s ' $1;
	printf '\033[0m\n';
}

config_git() {
    # These two features slow down navigation on big Git repos, so disable them
    git config --global --add oh-my-zsh.hide-status 1
    git config --global --add oh-my-zsh.hide-dirty 1
    sudo git config --global --add oh-my-zsh.hide-status 1
    sudo git config --global --add oh-my-zsh.hide-dirty 1

    git config --global user.name "TBM13"
    git config --global user.email "32852493+TBM13@users.noreply.github.com"
    sudo git config --global user.name "TBM13"
    sudo git config --global user.email "32852493+TBM13@users.noreply.github.com"

    log_success "Done!"
}

##################################################
# Windows
##################################################
cmd() {
    command="$1"
    working_dir=${2:-"$WIN_DRIVE/"}
    curr_path="$PWD"

    if [ ! -d "$working_dir" ]; then
        log_error "cmd: can't execute '$command': invalid working dir '$working_dir'"
        return
    fi

    cd $working_dir
    cmd.exe /c "$command"
    cd $curr_path
}

##################################################
# Android
##################################################
build_kernel_parse_var() {
    # Make $1 lowercase
    arg="${1:l}"

    if [[ "$arg" = "arm" || "$arg" = "arm64" || "$arg" == "arch="* ]]; then
        # remove arch=, lets make sure it's ARCH= (uppercase)
        arg=${arg#"arch="}
        export TBM_ARCH="ARCH=$arg"
        return 0
    fi

    if [ "$arg" = "ccache" ]; then
        export TBM_CCACHE="ccache "
        return 0
    fi

    if [[ "$arg" == "-j"* ]]; then
        export TBM_THREADS="$arg"
        return 0
    fi

    if [[ "$arg" == "kconfig_config="* ]]; then
        arg=${arg#"kconfig_config="}
        export TBM_KCONFIG_CONFIG="KCONFIG_CONFIG=$arg"
        return 0
    fi

    if [[ "$arg" == *"gcc"* || "$arg" == *"aarch64"* || "$arg" == "cross_compile="* ]]; then
        arg=${arg#"cross_compile="}
        export CROSS_COMPILE="$arg"
        return 0
    fi

    if [[ "$arg" == *".img"* || "$arg" == *"defconfig"* ]]; then
        export TBM_BUILD_TARGET="$arg"
        return 0
    fi

    if [[ "$arg" == "platform_version="* ]]; then
        arg=${arg#"platform_version="}
        export PLATFORM_VERSION="$arg"
        return 0
    fi
    if [[ "$arg" == "android_major_version="* ]]; then
        arg=${arg#"android_major_version="}
        export ANDROID_MAJOR_VERSION="$arg"
        return 0
    fi

    log_error "Unsure what this argument is supposed to be: '$arg'"
    return -1
}

get_kernel_image_path() {
    if [ ! -z "$TBM_ARCH" ]; then
        found_arch="$TBM_ARCH"
        # remove arch= from beggining
        found_arch=${found_arch#"ARCH="}
    fi
    if [ ! -z "$ARCH" ]; then
        found_arch="$ARCH"
    fi

    if [ -z "$found_arch" ]; then
        echo "ARCH is not set, trying common archs..."
        archs=("arm64" "arm" "x86" "mips")
    else
        archs=($found_arch)
    fi
    
    for a in ${(k)archs}; do
        image_paths=("./arch/$a/boot/Image")
        for p in ${(k)image_paths}; do
            if [ -f "$p" ]; then
                log_success "Found kernel Image at '$p'"
                kernel_image="$p"
                return 0
            fi
        done
    done

    log_error "Couldn't find kernel image"
    return -1
}

build_kernel() {
    # only the value of these will be saved to the config file
    saveable_value_vars=(TBM_ARCH TBM_THREADS TBM_CCACHE TBM_KCONFIG_CONFIG)
    # value and key of these will be saved to the config file
    saveable_keyvalue_vars=(CROSS_COMPILE PLATFORM_VERSION ANDROID_MAJOR_VERSION)
    # these won't be saved to the config file
    other_vars=(ARCH)

    # lets make sure there aren't any residual variables left
    # from another different build on the same shell session
    all_vars=(TBM_BUILD_TARGET ${(k)saveable_value_vars} ${(k)saveable_keyvalue_vars} ${(k)other_vars})
    for v in ${(k)all_vars}; do
        unset $v
    done

    # Load and parse variables from config file
    savefile="./tbm_build_config"
    if [ -f "$savefile" ]; then
        echo "Reading build settings from '$savefile'..."
        while read -r line; do
            build_kernel_parse_var "$line"
            if [ $? != 0 ]; then
                return
            fi
        done <$savefile
    fi

    # Parse variables passed to this function
    for v in "$@"; do
        build_kernel_parse_var "$v"
        if [ $? != 0 ]; then
            return
        fi
    done

    # Print variables and save them to config file
    if [ -f "$savefile" ]; then
        rm "$savefile"
    fi
    for v in ${(k)saveable_value_vars}; do
        value=${(P)v}
        if [ ! -z "$value" ]; then
            echo "$v: $value"
            echo "$value" >> "$savefile"
        fi
    done
    for v in ${(k)saveable_keyvalue_vars}; do
        value=${(P)v}
        if [ ! -z "$value" ]; then
            echo "$v: $value"
            echo "$v=$value" >> "$savefile"
        fi
    done

    echo
    echo "##############################################"
    echo
    GCC="gcc"
    GCC="$CROSS_COMPILE$GCC"
    # If we are using a custom toolchain, lets make sure it actually exists
    if [ ! -z "$CROSS_COMPILE" ] && [ ! -f "$GCC" ]; then
        # Maybe the toolchain is available on $PATH, check it
        if ! type "$GCC" > /dev/null; then
            log_error "Couldn't find GCC! It was supposed to be at '$GCC'"
            return
        fi
    fi

    start=`date +%s`
    make $TBM_ARCH $TBM_THREADS CC="$TBM_CCACHE$GCC" CROSS_COMPILE="$CROSS_COMPILE" $TBM_KCONFIG_CONFIG $TBM_BUILD_TARGET
    build_status=$?
    end=`date +%s`
    build_time=$((end-start))

    echo
    echo "##############################################"
    if [ $build_status != 0 ]; then
        log_error "Build failed after $build_time seconds"
        return
    fi

    log_success "Build succeeded after $build_time seconds"
    echo
}

move_kernel_to_aik() {
    if [ -z "$1" ]; then
        log_error "Usage: move-kernel-to-aik <AIK ID> [kernel image]"
        return
    fi

    if [ -z "$2" ]; then
        get_kernel_image_path
        if [ $? != 0 ]; then
            return
        fi
    else
        kernel_image="$2"
        if [ ! -f "$kernel_image" ]; then
            log_error "Couldn't find kernel image at '$kernel_image'"
            return
        fi
    fi

    aik_path="$USL/AIK$1"
    if [ ! -d "$aik_path" ]; then
        log_error "Couldn't find AIK dir at '$aik_path'"
        return
    fi

    aik_split="$aik_path/split_img"
    aik_image=$(find "$aik_split" -iname "*-kernel")
    if [ -z "$aik_image" ]; then
        log_error "Couldn't find AIK kernel image path at '$aik_split'. Is the image unpacked?"
        return
    fi

    cp "$kernel_image" "$aik_image"
    cmd "repackimg.bat" "$aik_path"
}

# Based on https://github.com/TBM13/Archived-Projects/blob/master/systemrw.sh
# This function makes an Android system image writable, by removing its
# shared_blocks feature. This was useful back when I tried to boot Google's
# Android 12 GSI on my A20, as I needed to edit the system image to make a fix
make_system_rw() {
    if [ -z "$1" ]; then
        log_error "Usage: make_system_rw <system.img>"
        return
    fi

    if [ ! -f "$1" ]; then
        log_error "Couldn't find image '$1'"
        exit 1
    fi

    if [[ "`tune2fs -l $1 | grep "feat"`" == *"shared_blocks"* ]]; then
        fi_name=${1//*\/}

        current_size=$(wc -c < $1)
        current_size_mb=$(echo $current_size | awk '{print int($1 / 1024 / 1024)}')
        current_size_blocks=$(echo $current_size | awk '{print int($1 / 512)}')
        printf "Current size of $fi_name in bytes: $current_size\n"
        printf "Current size of $fi_name in MB: $current_size_mb\n"
        printf "Current size of $fi_name in 512-byte sectors: $current_size_blocks\n\n"

        new_size_blocks=$(echo $current_size | awk '{print ($1 * 1.25) / 512}')
        printf "Increasing filesystem size of $fi_name...\n"
        resize2fs -f $1 $new_size_blocks

        printf "Removing 'shared_blocks feature' of %s...\n" $fi_name
        if ( ! e2fsck -y -E unshare_blocks $1 > /dev/null ); then
            log_error "There was a problem removing the read-only lock of '$fi_name'"
        else
            printf "Read-only lock of %s successfully removed\n\n" $fi_name
        fi
    else
        log_error "NO 'shared_blocks feature' detected on image, so it should already be rw"
        return
    fi

    echo "Operation finished"
}