function be_valid {
if [[ "$BE_PROJECT" = "" ]]
then
    echo "BE_PROJECT not set. This variable must contains your Project name"
    return 1
fi
}

function be_setup {
    if [ -f ~/.bashrc ] && [ "$(grep 'alias build-env=' ~/.bashrc)" = "" ]
    then
       echo "alias build-env='if [ -f build-env.sh ] ; then source build-env.sh ; else echo "Please move to your project where build-env.sh exists." ; fi'" >> ~/.bashrc
       echo "Alias build-env added to your existing .bashrc. Next time your could simply move to the project dir and call 'build-env'. The source task will done for you."
    fi
}

function be_ci_detected {
    export CI_ENABLED=FALSE
    if [[ "$WORKSPACE" != "" ]]
    then
        set +xe
        echo "Jenkins environment detected"
        export CI_WORKSPACE="$WORKSPACE"
        export CI_ENABLED=TRUE
    fi

}

function be_ci_run {
    if [[ "$CI_ENABLED" = "TRUE" ]]
    then
        set -xe
    fi

}

function be_docker_setup {
    if [ -f .be-docker ]
    then
       export BUILD_ENV_DOCKER="$(cat .be-docker)"
    else
       echo "Using docker directly. (no sudo)"
       export BUILD_ENV_DOCKER="docker"
    fi

    $BUILD_ENV_DOCKER version > /dev/null
    if [ $? -ne 0 ]
    then
       echo "$BUILD_ENV_DOCKER version fails. Check docker before going further. If you configured docker through sudo, please add --sudo:
    source build-env.sh --sudo ..."
       return 1
    fi
}

function be_common_load {
    if [ "$BUILD_ENV_PATH" = "" ]
    then
       export BE_PROJECT
       export BUILD_ENV_LOADED=true
       export BUILD_ENV_PROJECT=$(pwd)
       BUILD_ENV_PATH=$PATH
       for MOD in $MODS
       do
           ${MOD}_set_path
       done
       export PATH=$(pwd)/bin:$PATH
       PROMPT_ADDONS_BUILD_ENV="BE: $(basename ${BUILD_ENV_PROJECT})"
       echo "Build env loaded. To unload it, call 'build-env-unset'"
       alias build-env-unset='cd $BUILD_ENV_PROJECT && source build-unset.sh'
    fi
}

function unset_build_env {
    if [ "$BUILD_ENV_PATH" != "" ]
    then
        if [[ -f $BUILD_ENV_PROJECT/.build-env.def ]]
        then
            for var in $(sed 's/^\(.*\)=.*/\1/g' $BUILD_ENV_PROJECT/.build-env.def)
            do
               unset $var
            done
            echo "build-env.def unloaded."
        fi
        export PATH=$BUILD_ENV_PATH
        unset BUILD_ENV_PATH
        unset PROMPT_ADDONS_BUILD_ENV
        unset BUILD_ENV_LOADED
        unset BUILD_ENV_PROJECT
        unset BE_PROJECT
        unset beWrappers
        unalias build-env-unset
        local fcts="`compgen -A function be`"
        unset -f $fcts
        alias build-env='if [ -f build-env.sh ] ; then source build-env.sh ; else echo "Please move to your project where build-env.sh exists." ; fi'

        # TODO: Be able to load from a defined list of build env type. Here it is GO
        local MODS=(`cat build-env.modules`)
        for MOD in $MODS
        do
            unset_${MOD}
        done
    fi
}

function be_create_wrapper {
    echo "#!/bin/bash
# This file is generated by BuildEnv. Avoid updating it manually.
# Instead, contribute to BuildEnv and use 'be_update'
#
" > bin/$1
    echo "MOD=$2
    " >> bin/$1
    cat $BASE_DIR/bin/pre-wrapper.sh >> bin/$1
    be_create_wrapper_$MOD $1 bin/$1
    if [[ -f $BASE_DIR/bin/post-wrapper.sh ]]
    then
        cat $BASE_DIR/bin/post-wrapper.sh >> bin/$1
    fi
    chmod +x bin/$1
    echo "$2 Wrapper 'bin/$1' created."

}

function be_create_wrapper_core {
    echo "# Added from $BASE_DIR/bin/inenv" >> $2
    cat $BASE_DIR/bin/inenv.sh >> $2

}

function be_create_wrappers {
    for FILE in ${beWrappers[$1]}
    do
        be_create_wrapper ${FILE} $1
    done
}

function be_create {
    if [[ ! -f build-env.sh ]] || [[ "$1" = force ]]
    then
        echo "
# Build Environment created by buildEnv
BE_PROJECT=$BE_PROJECT

# Add any module parameters here

source lib/source-build-env.sh" > build-env.sh
        echo ".build-env.sh created"
    fi

    if [[ ! -f build-unset.sh ]] || [[ "$1" = force ]]
    then
        echo "
# Build Environment created by buildEnv

# unset any module parameters here

unset_build_env
fcts=\"\`compgen -A function unset\`\"
unset -f \$fcts
unset fcts" > build-unset.sh
        echo ".build-unset.sh created"
    fi

    echo "$BASE_DIR" > .be-source
    echo ".be-source created."

    if [[ "$1" = force ]]
    then
        shift
    fi

    > build-env.modules
    for MOD in "$@"
    do
        echo "$MOD" >> build-env.modules
    done
    echo "build-env.modules has '$@'"
}

function be_update {
    local loaded=false
    if [[ "$BASE_DIR" = "" ]]
    then
        loaded=true
        BASE_DIR=$(cat .be-source)
        if [[ ! -f $BASE_DIR/configure-build-env.sh ]]
        then
            echo "BuildEnv upstream repo not found in '$BASE_DIR'. You may need to update '.be-source'."
            return
        fi
        echo "Using $BASE_DIR as upstream BuildEnv reference."
    fi

    if [[ -d .git ]]
    then
        if [[ -f .gitignore ]]
        then
            if [[ "$(cat .gitignore | grep -e "^.be-\*$")" = ""  ]]
            then
                echo ".be-*" >> .gitignore
                echo ".gitignore updated"
            fi
        else
            echo ".gitignore created"
        fi
    fi

    mkdir -vp bin lib build-env-docker

    cp -v $BASE_DIR/lib/* lib/

    if [[ $loaded = true ]]
    then
        source lib/build-env.fcts.sh
        echo "build-env.fcts refreshed"
    fi

    local MODS=(`cat build-env.modules`)
    for MOD in $MODS core
    do
        if [[ $MOD = core ]]
        then
            docker_build_env $MOD
        fi
        if [[ -d $BASE_DIR/modules/$MOD ]]
        then
            cp -v $BASE_DIR/modules/$MOD/lib/*.sh lib/
            docker_build_env $MOD
            echo "Module $MOD added."
        fi
    done
    if [[ $loaded = true ]]
    then
        unset BASE_DIR
    fi
    echo "build-env.modules created"
}

function docker_build_env {
    if [[ "$1" = "" ]]
    then
        return
    fi
    if [[ $1 != core ]]
    then
        source $BASE_DIR/modules/$MOD/lib/source-be-$1.sh
    fi

    be_create_wrappers $1

    if [[ "$1" != core ]]
    then
        be_create_${1}_docker_build
    fi

    if [[ $1 = core ]]
    then
        _be_gitignore
    fi
}

function _be_gitignore {
    if [[ -f .gitignore ]]
    then
       if [[ "$(grep '^.be-\*$' .gitignore)" = "" ]]
       then
           echo ".be-*" >> .gitignore
           echo ".gitignore updated."
       fi
    else
        echo ".be-*" > .gitignore
        echo ".gitignore created."
    fi

}

function _be_set_debug {
    if [[ $old_setting != x ]]
    then
        set -x
    fi
}

function _be_restore_debug {
    if [[ $old_setting != x ]]
    then
        set +x
    fi
}

export old_setting=${-//[^x]/}

declare -A beWrappers

beWrappers[core]="inenv"
