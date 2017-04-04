#/!bin/bash
# The purpose of this script is to bump up (increment) the version number
# of a release and commit the changes to git with the tag
#
# Only a person with admin privileges can un this script.
# It should be run in the branch that we want to up the version, i.e. master.
# We're assuming that the repo is clean and up-to-date
#
#
set -e

while [[ $# > 1 ]]
do
key="$1"

case $key in
    -v|--version)
    VERSION="$2"
    shift # past argument
    ;;
    -r|--repo)
    ext_repo="$2"
    shift # past argument
    ;;
    *)
          # unknown option
    ;;
esac
shift # past argument or value
done

if [[ -n $1 ]]; then
    echo "Error: Argument specified is unacceptable"
    exit 113
fi

REPO=${ext_repo}

function git_status() {
  git status --porcelain 2> /dev/null
}

function ensure_clean_git() {
  STATUS=$(git_status | tail -n1)
  if [[ -n $STATUS ]]; then
    echo "git repo is dirty - aborting"
    exit 1
  fi
}

function ensure_installed() {
  which $1 || (
    echo "$1 not installed - aborting!"
    exit 1
  )
}

# some pre-flight checks
if [ "$GITHUB_API_TOKEN" == "" ]; then
  echo "No GITHUB_API_TOKEN found - this must be set!"
  exit 1
fi
ensure_clean_git
ensure_installed npm
ensure_installed node

VERSION=$(node -e "console.log(require('./package.json').version)")

echo "Temporarily Disabling master branch required status checks"

orig_state=$(curl "https://api.github.com/repos/$REPO/branches/master" \
  -s -X GET -H "Authorization: token $GITHUB_API_TOKEN" \
  -H "Accept: application/vnd.github.loki-preview" | jq '{ protection: .protection }')
disabled_state=$(echo $orig_state | jq '.protection.required_status_checks.enforcement_level="off"')
patch_result=$(curl "https://api.github.com/repos/$REPO/branches/master" \
  -s -X PATCH -H "Authorization: token $GITHUB_API_TOKEN" \
  -H "Accept: application/vnd.github.loki-preview" \
  -d "${disabled_state}")

# If the current version is a pre-release, bump it to a release first.
# i.e. remove the '-' and everything after
if (echo $VERSION | egrep -- '-[0-9]+$' 1> /dev/null ); then
  echo "Releasing..."
  npm version patch -m "Releasing v%s"
  git push
  git push --tags
else
  git tag -a v$VERSION -m "Releasing v$VERSION"
  git push --tags
fi

echo "Beginning development on next version..."
NEWVER=$(npm version prerelease -m "Beginning development on v%s\n[ci skip]")
git tag -d $NEWVER
git push

echo "Re-enabling master branch required status checks..."
patch_result=$(curl "https://api.github.com/repos/$REPO/branches/master" \
  -s -X PATCH -H "Authorization: token $GITHUB_API_TOKEN" \
  -H "Accept: application/vnd.github.loki-preview" \
  -d "${orig_state}")

echo "Done."

