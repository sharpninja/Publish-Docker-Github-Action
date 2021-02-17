#!/bin/sh
#set -e

main() {
  echo "::debug::Starting." # see https://github.com/actions/toolkit/issues/168

  if usesBoolean "${ACTIONS_STEP_DEBUG}"; then
#     echo "::add-mask::${INPUT_USERNAME}"
#     echo "::add-mask::${INPUT_PASSWORD}"
    set -x
  fi

# sanitize "${INPUT_NAME}" "name"
# if ! usesBoolean "${INPUT_NO_PUSH}"; then
#     sanitize "${INPUT_USERNAME}" "username"
#     sanitize "${INPUT_PASSWORD}" "password"
# fi

  registryToLower
  nameToLower

  REGISTRY_NO_PROTOCOL=$(echo "${$1}" | sed -e 's/^https:\/\///g')
  if uses "${INPUT_REGISTRY}" && ! isPartOfTheName "${REGISTRY_NO_PROTOCOL}"; then
    INPUT_NAME="${REGISTRY_NO_PROTOCOL}/${INPUT_NAME}"
    echo "::debug::INPUT_NAME: $INPUT_NAME"
  fi

  if uses "${INPUT_TAGS}"; then
    TAGS=$(echo "${$1}" | sed "s/,/ /g")
    echo "::debug::TAGS: $TAGS"
  else
    translateDockerTag
  fi

  if uses "${INPUT_WORKDIR}"; then
    changeWorkingDirectory
  fi

  if uses "${INPUT_USERNAME}" && uses "${INPUT_PASSWORD}"; then
    echo "::debug::docker login -u ${INPUT_USERNAME} -p ${INPUT_PASSWORD} ${INPUT_REGISTRY} --verbose"
    docker login -u ${INPUT_USERNAME} -p ${INPUT_PASSWORD} ${INPUT_REGISTRY} --verbose
  fi

  FIRST_TAG=$(echo "${$1}" | cut -d ' ' -f1)
  echo "::debug::FIRST_TAG: $FIRST_TAG"
  DOCKERNAME="${INPUT_NAME}:${FIRST_TAG}"
  echo "::debug::DOCKERNAME: $DOCKERNAME"
  BUILDPARAMS=""
  echo "::debug::BUILDPARAMS: $BUILDPARAMS"
  CONTEXT="."
  echo "::debug::CONTEXT: $CONTEXT"

  if uses "${INPUT_DOCKERFILE}"; then
    useCustomDockerfile
  fi
  if uses "${INPUT_BUILDARGS}"; then
    addBuildArgs
  fi
  if uses "${INPUT_CONTEXT}"; then
    CONTEXT="${INPUT_CONTEXT}"
    echo "::debug::CONTEXT: $CONTEXT"
  fi
  if usesBoolean "${INPUT_CACHE}"; then
    useBuildCache
  fi
  if usesBoolean "${INPUT_SNAPSHOT}"; then
    useSnapshot
  fi

  build

  if usesBoolean "${INPUT_NO_PUSH}"; then
    if uses "${INPUT_USERNAME}" && uses "${INPUT_PASSWORD}"; then
      echo "::debug::docker logout"
      docker logout
    fi
    exit 0
  fi

  push

  echo "::set-output name=tag::${FIRST_TAG}"
  DIGEST=${docker inspect --format='{{index .RepoDigests 0}}' ${DOCKERNAME}}
  echo "::set-output name=digest::${DIGEST}"
  echo "::debug::FIRST_TAG: $FIRST_TAG"
  echo "::debug::DIGEST: $DIGEST"

  docker logout
}

sanitize() {
  if [ -z "$1" ]; then
    >&2 echo "Unable to find the $2. Did you set with: $2?"
    exit 1
  fi
}

registryToLower(){
 INPUT_REGISTRY=$(echo "${$1}" | tr '[A-Z]' '[a-z]')
 echo "::debug::INPUT_REGISTRY: $INPUT_REGISTRY"
}

nameToLower(){
  INPUT_NAME=$(echo "${INPUT_NAME}" | tr '[A-Z]' '[a-z]')
  echo "::debug::INPUT_NAME: $INPUT_NAME"
}

isPartOfTheName() {
  [ $(echo "${INPUT_NAME}" | sed -e "s/${1}//g") != "${INPUT_NAME}" ]
}

translateDockerTag() {
  local BRANCH=$(echo "${$1}" | sed -e "s/refs\/heads\///g" | sed -e "s/\//-/g")
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
      TAGS=$(echo "${$1}" | sed -e "s/refs\/tags\///g" | sed -E "s/v?([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-zA-Z]+(\.[0-9]+)?)?/\1.\2.\3\4/g")
      echo "::debug::TAGS: $TAGS"
    else
      TAGS=$(echo "${$1}" | sed -e "s/refs\/tags\///g" | sed -E "s/v?([0-9]+)\.([0-9]+)\.([0-9]+)/\1.\2.\3\4 \1.\2\4 \1\4/g")
      echo "::debug::TAGS: $TAGS"
    fi
  elif isGitTag && usesBoolean "${INPUT_TAG_NAMES}"; then
    TAGS=$(echo "${$1}" | sed -e "s/refs\/tags\///g")
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
  fi;
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
