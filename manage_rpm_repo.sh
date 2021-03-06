#!/usr/bin/env bash

### This will initialise the RPM building environment. Note that this script
### is highly Socorro-specific, so YMMV in other contexts.


# Everybody loves globals.
HELPARGS=("help" "-help" "--help" "-h" "-?")
ACTIONS=(check_token init refresh update)
WORK_DIR="${HOME}/${RANDOM}-${RANDOM}"
BUCKET_URL="s3://myrepo.packages-public/build"
SECRET_KEY="RPM-GPG-KEY-myapp.private"
PUBLIC_KEY="RPM-GPG-KEY-myapp"
REPO_URL="s3://myrepo.packages-public/el/7"
REPO_DIR="${HOME}/myrepo.packages-public"
# Use the default crash-stats region unless otherwise specified.
if [ "x${AWS_DEFAULT_REGION}" == "x" ]; then
    export AWS_DEFAULT_REGION="us-west-2"
fi


# Search through an array for a string.
function contains_element () {
    local i
    for i in "${@:2}"; do
        [[ "$i" == "$1" ]] && return 0
    done
    return 1
}

# Help.
function help {
    echo "USAGE: ${0} <action>"
    echo -n "Valid actions are: "
    local i
    for i in "${ACTIONS[@]}"; do
        echo -n "$i "
    done
    echo ""
    exit 1
}

# Init; this only works once.
function init {
    # Abort if .rpmmacros is already configured; init once only!
    grep -q "tools-socorro" ${HOME}/.rpmmacros
    if [ $? -eq 0 ]; then
        echo "WARNING: Init has already been run on this machine."
        return
    fi

    echo "Get with the init."
    set -ex
    # Initialise the build tree.
    pushd $HOME
    rpmdev-setuptree
    popd

    # Nab the signing keypair.
    mkdir $WORK_DIR
    pushd $WORK_DIR
    aws s3 cp --only-show-errors ${BUCKET_URL}/${SECRET_KEY} .
    aws s3 cp --only-show-errors ${BUCKET_URL}/${PUBLIC_KEY} .
    gpg -q --allow-secret-key-import --import $SECRET_KEY
    gpg -q --import $PUBLIC_KEY
    rm $SECRET_KEY
    rm $PUBLIC_KEY
    popd

    # Set up the RPM macros.
    cat << EOF >> ~/.rpmmacros

%_signature gpg
%_gpg_path ${HOME}/.gnupg
%_gpg_name Mozilla Socorro Builder <tools-socorro@lists.mozilla.org>
%packager Mozilla Socorro Builder <tools-socorro@lists.mozilla.org>
EOF

    # Grab a fresh copy of the repo.
    refresh

    # And we're done.
    rm -rf $WORK_DIR
    set +ex
    echo "Initialisation complete!"
}

# The local repo is out of date and needs to be refreshed from live.
function refresh {
    rm -rf $REPO_DIR
    # Grab a local copy of the public repo.
    # We have to make the destination manually because of a bug. :(
    # https://github.com/aws/aws-cli/issues/1082
    mkdir $REPO_DIR
    pushd $REPO_DIR
    aws s3 sync --only-show-errors $REPO_URL/ .
    popd
    echo "Repo refresh complete!"
}

# Update; do this when you're ready to update the bucket.
function update {
    # Check the token first.
    check_token

    echo "Get with the update."
    set -ex
    pushd $REPO_DIR

    # Generate the update token.
    date +%s > update_token

    # Build the cache et al.
    for arch in x86_64 i386 noarch SRPMS; do
        # Only genereate metadata if
        createrepo --update -q --deltas $arch
    done
    popd

    # Sync it back to the bucket.
    aws s3 sync --delete $REPO_DIR $REPO_URL

    # And we're done.
    set +ex
    echo "Update complete!"
}

# Check the update token.
function check_token {
    echo "Checking the update token."
    set -e
    aws s3 cp --only-show-errors $REPO_URL/update_token $HOME

    # If the freshly-obtained stamp is newer than the local stamp, then we
    # know that the local repo is out of date and must be refreshed.
    local LIVE_STAMP=$(cat ${HOME}/update_token)
    local LOCAL_STAMP=$(cat ${REPO_DIR}/update_token)
    local DIFF_STAMP=0
    # Fun fact: if the resut of let is 0, that will trigger set -e; so add 1.
    let DIFF_STAMP=${LIVE_STAMP}-${LOCAL_STAMP}+1
    if [ $DIFF_STAMP -ge 2 ]; then
        >&2 echo "ERROR: The local repository is too old. You must refresh!"
        exit 1
    fi

    set +e
    echo "You're probably good to go!"
}


# Runtime.

# Is this a cry for help?
contains_element $1 "${HELPARGS[@]}"
if [ $? -eq 0 ]; then
    help
fi

# Not enough arguments? That's a paddlin'.
if [ $# != 1 ]; then
    help
fi

# Validate the requested action.
contains_element $1 "${ACTIONS[@]}"
if [ $? -ne 0 ]; then
    >&2 echo "ERROR: $1 is not a valid action."
    exit 1
fi

# Pre-flight check is good: perform the action.
$1