#!/bin/sh
#
# Xcode Cloud runs this after cloning the repository and before building.
#
# project.yml is the source of truth and xcodegen writes Florin.xcodeproj from
# it. The generated project is committed so a hosted build has something to
# open, but a commit that changed project.yml without regenerating would build
# stale settings. Regenerating here means the build always reflects the
# manifest, whatever state the committed project happened to be in.
#
# It deliberately does not touch the build number. Xcode Cloud sets that from
# CI_BUILD_NUMBER when it archives — after this script has run — so anything
# written here is overwritten anyway. An earlier version of this script offset
# the number past the 408 builds uploaded by hand, on the assumption that App
# Store Connect requires build numbers to increase within a version. It does
# not: it requires them to be unique, and build 3 attached to 1.3.4 without
# complaint alongside 406, 407 and 408.

set -e

cd "$CI_PRIMARY_REPOSITORY_PATH/apps/ios"

# XcodeGen is not on the Xcode Cloud image. Homebrew is.
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ci_post_clone: installing xcodegen"
  brew install xcodegen
fi

echo "ci_post_clone: regenerating the project from project.yml"
xcodegen generate --spec project.yml
