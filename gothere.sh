#!/bin/sh
#set -e
echo "::debug::Start."

main() {
    echo "::debug::Main." # see https://github.com/actions/toolkit/issues/168

    if usesBoolean "${ACTIONS_STEP_DEBUG}"; then
        echo "::debug::ACTIONS_STEP_DEBUG: $ACTIONS_STEP_DEBUG"
        #     echo "::add-mask::${INPUT_USERNAME}"
        #     echo "::add-mask::${INPUT_PASSWORD}"
        set -x
    fi
}

hasCustomTag() {
  [ $(echo "${INPUT_NAME}" | sed -e "s/://g") != "${INPUT_NAME}" ]
}

isOnDefaultBranch() {
  if uses "${INPUT_DEFAULT_BRANCH}"; then
    [ "${BRANCH}" = "${INPUT_DEFAULT_BRANCH}" ]
  else
    [ "${BRANCH}" = "master" ] || [ "${BRANCH}" = "main" ]
  fi
}

isGitTag() {
  [ $(echo "${GITHUB_REF}" | sed -e "s/refs\/tags\///g") != "${$1}" ]
}

isPullRequest() {
  [ $(echo "${GITHUB_REF}" | sed -e "s/refs\/pull\///g") != "${$1}" ]
}

changeWorkingDirectory() {
  cd "${INPUT_WORKDIR}"
  echo "::debug::INPUT_WORKDIR: $INPUT_WORKDIR"
}

useCustomDockerfile() {
  BUILDPARAMS="${BUILDPARAMS} -f ${INPUT_DOCKERFILE}"
  echo "::debug::BUILDPARAMS: $BUILDPARAMS"
}

addBuildArgs() {
  for ARG in $(echo "${$1}" | tr ',' '\n'); do
    BUILDPARAMS="${BUILDPARAMS} --build-arg ${ARG}"
    echo "::debug::BUILDPARAMS: $BUILDPARAMS"
    echo "::debug::ARG: $ARG"
  done
}

useBuildCache() {
  if docker pull "${DOCKERNAME}" 2>/dev/null; then
    BUILDPARAMS="${BUILDPARAMS} --cache-from ${DOCKERNAME}"
    echo "::debug::BUILDPARAMS: $BUILDPARAMS"
  fi
}

uses() {
  [ ! -z "${1}" ]
}

usesBoolean() {
  [ ! -z "${1}" ] && [ "${1}" = "true" ]
}

isSemver() {
  echo "${1}" | grep -Eq '^refs/tags/v?([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-zA-Z]+(\.[0-9]+)?)?$'
}

isPreRelease() {
  echo "${1}" | grep -Eq '-'
}

useSnapshot() {
  local TIMESTAMP=`date +%Y%m%d%H%M%S`
  local SHORT_SHA=$(echo "${$1}" | cut -c1-6)
  local SNAPSHOT_TAG="${TIMESTAMP}${SHORT_SHA}"
  TAGS="${TAGS} ${SNAPSHOT_TAG}"
  echo "::set-output name=snapshot-tag::${SNAPSHOT_TAG}"
  echo "::debug::TAGS: $TAGS"
}

build() {
  local BUILD_TAGS=""
  for TAG in ${TAGS}; do
    BUILD_TAGS="${BUILD_TAGS}-t ${INPUT_NAME}:${TAG} "
    echo "::debug::BUILD_TAGS: $BUILD_TAGS"
  done
  echo "docker build ${INPUT_BUILDOPTIONS} ${BUILDPARAMS} ${BUILD_TAGS} ${CONTEXT}"
  docker build ${INPUT_BUILDOPTIONS} ${BUILDPARAMS} ${BUILD_TAGS} ${CONTEXT}
}

push() {
  for TAG in ${TAGS}; do
    echo "::debug::docker push \"${INPUT_NAME}:${TAG}\""
    docker push "${INPUT_NAME}:${TAG}"
  done
}

main

echo "::debug::Finished."
