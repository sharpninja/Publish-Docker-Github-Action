#!/bin/sh
#set -e
echo "::debug::Start. $1 $2 $3 $4"

main() {
    echo "::debug::Main." # see https://github.com/actions/toolkit/issues/168

    if usesBoolean "$ACTIONS_STEP_DEBUG"; then
        echo "::debug::ACTIONS_STEP_DEBUG: $ACTIONS_STEP_DEBUG"
        set -x
    fi

    registryToLower
    nameToLower

    REGISTRY_NO_PROTOCOL=$(echo "${registry}" | sed -e 's/^https:\/\///g')
    if uses "${registry}" && ! isPartOfTheName "${REGISTRY_NO_PROTOCOL}"; then
        INPUT_NAME="${REGISTRY_NO_PROTOCOL}/${INPUT_NAME}"
        echo "::debug::INPUT_NAME: $INPUT_NAME"
    fi

    if uses "${tags}"; then
        TAGS=$(echo "$1" | sed "s/,/ /g")
        echo "::debug::TAGS: $TAGS"
    else
        translateDockerTag
    fi

    if uses "${workdir}"; then
        changeWorkingDirectory
    fi

    if uses "${username}" && uses "${password}"; then
        echo "::debug::docker login -u ${username} -p ${password} ${registry} --verbose"
        docker login -u ${username} -p ${password} ${registry} --verbose
    fi

}

sanitize() {
    echo "::debug::sanitize [$1] [$2]"
    if [ -z "$1" ]; then
        echo >&2 "Unable to find the $2. Did you set with: $2?"
        exit 1
    fi
}

registryToLower() {
    echo "::debug::registryToLower [$1]"
    registry=$(echo "$1" | tr '[A-Z]' '[a-z]')
    echo "::debug::registry: $registry"
}

nameToLower() {
    echo "::debug::nameToLower"
    INPUT_NAME=$(echo "${INPUT_NAME}" | tr '[A-Z]' '[a-z]')
    echo "::debug::INPUT_NAME: $INPUT_NAME"
}

isPartOfTheName() {
    echo "::debug::isPartOfTheName [$1]"
    [ $(echo "${INPUT_NAME}" | sed -e "s/${1}//g") != "${INPUT_NAME}" ]
}

translateDockerTag() {
    local BRANCH=$(echo "$1" | sed -e "s/refs\/heads\///g" | sed -e "s/\//-/g")
    if hasCustomTag; then
        TAGS=$(echo "${INPUT_NAME}" | cut -d':' -f2)
        echo "::debug::TAGS: $TAGS"
        INPUT_NAME=$(echo "${INPUT_NAME}" | cut -d':' -f1)
        echo "::debug::INPUT_NAME: $INPUT_NAME"
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
    echo "::debug::hasCustomTag"
    [ $(echo "${INPUT_NAME}" | sed -e "s/://g") != "${INPUT_NAME}" ]
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
    BUILDPARAMS="${BUILDPARAMS} -f ${INPUT_DOCKERFILE}"
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
        BUILD_TAGS="${BUILD_TAGS}-t ${INPUT_NAME}:${TAG} "
        echo "::debug::BUILD_TAGS: $BUILD_TAGS"
    done
    echo "docker build ${INPUT_BUILDOPTIONS} ${BUILDPARAMS} ${BUILD_TAGS} ${CONTEXT}"
    docker build ${INPUT_BUILDOPTIONS} ${BUILDPARAMS} ${BUILD_TAGS} ${CONTEXT}
}

push() {
    echo "::debug::push"
    for TAG in ${TAGS}; do
        echo "::debug::docker push \"${INPUT_NAME}:${TAG}\""
        docker push "${INPUT_NAME}:${TAG}"
    done
}

main

echo "::debug::Finished."
