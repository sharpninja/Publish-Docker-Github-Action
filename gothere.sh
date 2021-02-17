#!/bin/sh
#set -e
echo "::debug::Start. $1 $2 $3 $4"

main() {
    echo "::debug::Main." # see https://github.com/actions/toolkit/issues/168

    if usesBoolean "$ACTIONS_STEP_DEBUG"; then
        echo "::debug::ACTIONS_STEP_DEBUG: $ACTIONS_STEP_DEBUG"
        set -x
    fi

    registry_urlToLower
    nameToLower

    echo "::debug::registry_url: $registry_url"
    registry_url_NO_PROTOCOL=$(echo "${registry_url}" | sed -e 's/^https:\/\///g')
    if uses "${registry_url}" && ! isPartOfTheName "${registry_url_NO_PROTOCOL}"; then
        name="${registry_url_NO_PROTOCOL}/${name}"
        echo "::debug::name: $name"
    fi

    echo "::debug::tags: $tags"
    if uses "${tags}"; then
        TAGS=$(echo "$tags" | sed "s/,/ /g")
        echo "::debug::TAGS: $TAGS"
    else
        translateDockerTag
    fi

    echo "::debug::workdir: $workdir"
    if uses "${workdir}"; then
        changeWorkingDirectory
    fi

    echo "::debug::username: $username"
    echo "::debug::password: $password"
    echo "::debug::tenantId: $tenantId"
    if uses "${username}" && uses "${password}"; then
        echo "::debug::docker login -u ${username} -p ${password} ${registry_url}"
        docker login -u ${username} -p ${password} ${registry_url}
    fi

    FIRST_TAG=$(echo "${$1}" | cut -d ' ' -f1)
    echo "::debug::FIRST_TAG: $FIRST_TAG"
    DOCKERNAME="${name}:${FIRST_TAG}"
    echo "::debug::DOCKERNAME: $DOCKERNAME"
    BUILDPARAMS=""
    CONTEXT="."

    if uses "${dockerfile}"; then
        useCustomDockerfile
    fi
    if uses "${buildargs}"; then
        addBuildArgs
    fi
    if uses "${context}"; then
        CONTEXT="${context}"
        echo "::debug::CONTEXT: $CONTEXT"
    fi
    if usesBoolean "${cache}"; then
        useBuildCache
    fi
    if usesBoolean "${snapshot}"; then
        useSnapshot
    fi

}

sanitize() {
    echo "::debug::sanitize [$1] [$2]"
    if [ -z "$1" ]; then
        echo >&2 "Unable to find the $2. Did you set with: $2?"
        exit 1
    fi
}

registry_urlToLower() {
    echo "::debug::registry_urlToLower [$registry_url]"
    registry_url=$(echo "$registry_url" | tr '[A-Z]' '[a-z]')
    echo "::debug::registry_url: $registry_url"
}

nameToLower() {
    echo "::debug::nameToLower"
    name=$(echo "${name}" | tr '[A-Z]' '[a-z]')
    echo "::debug::name: $name"
}

isPartOfTheName() {
    echo "::debug::isPartOfTheName [$1]"
    [ $(echo "${name}" | sed -e "s/${1}//g") != "${name}" ]
}

translateDockerTag() {
    echo "::debug::translateDockerTag [$1]"
    local BRANCH=$(echo "$1" | sed -e "s/refs\/heads\///g" | sed -e "s/\//-/g")
    if hasCustomTag; then
        TAGS=$(echo "${name}" | cut -d':' -f2)
        echo "::debug::TAGS: $TAGS"
        name=$(echo "${name}" | cut -d':' -f1)
        echo "::debug::name: $name"
    elif isOnDefaultBranch; then
        TAGS="latest"
        echo "::debug::TAGS: $TAGS"
    elif isGitTag && usesBoolean "${INPUT_TAG_SEMVER}" && isSemver "${GITHUB_REF}"; then
        if isPreRelease "${GITHUB_REF}"; then
            TAGS=$(echo "$1" | sed -e "s/refs\/tags\///g" | sed -E "s/v?([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-zA-Z]+(\.[0-9]+)?)?/\1.\2.\3\4/g")
            echo "::debug::TAGS: $TAGS"
        else
            TAGS=$(echo "$1" | sed -e "s/refs\/tags\///g" | sed -E "s/v?([0-9]+)\.([0-9]+)\.([0-9]+)/\1.\2.\3\4 \1.\2\4 \1\4/g")
            echo "::debug::TAGS: $TAGS"
        fi
    elif isGitTag && usesBoolean "${INPUT_TAG_NAMES}"; then
        TAGS=$(echo "$1" | sed -e "s/refs\/tags\///g")
        echo "::debug::TAGS: $TAGS"
    elif isGitTag; then
        TAGS="latest"
        echo "::debug::TAGS: $TAGS"
    elif isPullRequest; then
        TAGS="${GITHUB_SHA}"
        echo "::debug::TAGS: $TAGS"
    else
        TAGS="${BRANCH}"
        echo "::debug::TAGS: $TAGS"
    fi
}

hasCustomTag() {
    echo "::debug::hasCustomTag [$name]"
    [ $(echo "${name}" | sed -e "s/://g") != "${name}" ]
}

isOnDefaultBranch() {
    echo "::debug::hasCustomTag"
    if uses "${INPUT_DEFAULT_BRANCH}"; then
        [ "${BRANCH}" = "${INPUT_DEFAULT_BRANCH}" ]
    else
        [ "${BRANCH}" = "master" ] || [ "${BRANCH}" = "main" ]
    fi
}

isGitTag() {
    echo "::debug::isGitTag [$1]"
    [ $(echo "${GITHUB_REF}" | sed -e "s/refs\/tags\///g") != "$1" ]
}

isPullRequest() {
    echo "::debug::isPullRequest [$1]"
    [ $(echo "${GITHUB_REF}" | sed -e "s/refs\/pull\///g") != "$1" ]
}

changeWorkingDirectory() {
    echo "::debug::changeWorkingDirectory"
    cd "${workdir}"
    echo "::debug::workdir: $workdir"
}

useCustomDockerfile() {
    echo "::debug::useCustomDockerfile"
    BUILDPARAMS="${BUILDPARAMS} -f ${dockerfile}"
    echo "::debug::BUILDPARAMS: $BUILDPARAMS"
}

addBuildArgs() {
    echo "::debug::hasCustomTag [$1]"
    for ARG in $(echo "$1" | tr ',' '\n'); do
        BUILDPARAMS="${BUILDPARAMS} --build-arg ${ARG}"
        echo "::debug::BUILDPARAMS: $BUILDPARAMS"
        echo "::debug::ARG: $ARG"
    done
}

useBuildCache() {
    echo "::debug::useCustomDockerfile"
    if docker pull "${DOCKERNAME}" 2>/dev/null; then
        BUILDPARAMS="${BUILDPARAMS} --cache-from ${DOCKERNAME}"
        echo "::debug::BUILDPARAMS: $BUILDPARAMS"
    fi
}

uses() {
    echo "::debug::uses [$1]"
    [ ! -z "$1" ]
}

usesBoolean() {
    echo "::debug::usesBoolean [$1]"

    [ ! -z "$1" ] && [ "$1" = "true" ]
}

isSemver() {
    echo "::debug::isSemver [$1]"
    echo "$1" | grep -Eq '^refs/tags/v?([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-zA-Z]+(\.[0-9]+)?)?$'
}

isPreRelease() {
    echo "::debug::isPreRelease [$1]"
    echo "$1" | grep -Eq '-'
}

useSnapshot() {
    echo "::debug::useSnapshot [$1]"
    local TIMESTAMP=$(date +%Y%m%d%H%M%S)
    local SHORT_SHA=$(echo "$1" | cut -c1-6)
    local SNAPSHOT_TAG="${TIMESTAMP}${SHORT_SHA}"
    TAGS="${TAGS} ${SNAPSHOT_TAG}"
    echo "::set-output name=snapshot-tag::${SNAPSHOT_TAG}"
    echo "::debug::TAGS: $TAGS"
}

build() {
    echo "::debug::build"
    local BUILD_TAGS=""
    for TAG in ${TAGS}; do
        BUILD_TAGS="${BUILD_TAGS}-t ${name}:${TAG} "
        echo "::debug::BUILD_TAGS: $BUILD_TAGS"
    done
    echo "docker build ${INPUT_BUILDOPTIONS} ${BUILDPARAMS} ${BUILD_TAGS} ${CONTEXT}"
    docker build ${INPUT_BUILDOPTIONS} ${BUILDPARAMS} ${BUILD_TAGS} ${CONTEXT}
}

push() {
    echo "::debug::push"
    for TAG in ${TAGS}; do
        echo "::debug::docker push \"${name}:${TAG}\""
        docker push "${name}:${TAG}"
    done
}

main

echo "::debug::Finished."
