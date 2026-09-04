#!/bin/sh
#
# Xcode Cloud runs this after cloning the repository and before building.
#
# Two things have to be true for a hosted build to be usable, and neither is
# true by default here.
#
# The build number. Xcode Cloud sets CI_BUILD_NUMBER from its own counter,
# which starts at 1 for a new workflow and knows nothing about what has already
# been uploaded. This project had reached 408 by hand, so the first hosted
# build arrived as "2" — unique, but lower than every build before it, and App
# Store Connect will not accept a build that goes backwards within a version.
# Offsetting past the highest build already uploaded puts the sequence back in
# order and keeps it there.
#
# The project itself. project.yml is the source of truth and xcodegen writes
# Florin.xcodeproj from it. The generated project is committed so Xcode Cloud
# has something to open, but a commit that changed project.yml without
# regenerating would build stale settings. Regenerating here means the build
# always reflects the manifest, whatever state the committed project is in.

set -e

# Past 408, the highest build uploaded before Xcode Cloud took over. Raise this
# only if builds are ever uploaded by hand again.
BUILD_OFFSET=500
BUILD_NUMBER=$((BUILD_OFFSET + ${CI_BUILD_NUMBER:-0}))

echo "ci_post_clone: CI_BUILD_NUMBER=${CI_BUILD_NUMBER:-unset} -> build ${BUILD_NUMBER}"

cd "$CI_PRIMARY_REPOSITORY_PATH/apps/ios"

# XcodeGen is not on the Xcode Cloud image. Homebrew is.
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ci_post_clone: installing xcodegen"
  brew install xcodegen
fi

# Rewrite both declarations — the app target and the widget extension. They
# must match exactly: an extension carrying a different version from the app
# that contains it is rejected as an invalid binary, which is how build 407
# died.
sed -i '' "s/CURRENT_PROJECT_VERSION: [0-9][0-9]*/CURRENT_PROJECT_VERSION: ${BUILD_NUMBER}/g" project.yml

echo "ci_post_clone: regenerating the project"
xcodegen generate --spec project.yml

echo "ci_post_clone: versions now"
grep -n "CURRENT_PROJECT_VERSION\|MARKETING_VERSION" project.yml
