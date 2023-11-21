#!/bin/bash

set -e

COVERAGE_THRESHOLD=$1
TARGET_BRANCH=$2
GITHUB_TOKEN=$3
GITHUB_USERNAME=$(echo "$GITHUB_REPOSITORY" | cut -d'/' -f1)
GITHUB_REPO=$(echo "$GITHUB_REPOSITORY" | cut -d'/' -f2)
GITHUB_ISSUE_NUMBER=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/pulls/$GITHUB_PULL_REQUEST_NUMBER" | jq -r '.number')
GITHUB_SHA=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/pulls/$GITHUB_ISSUE_NUMBER" | jq -r '.head.sha')

# Step 1: Install dependencies (if needed)
# For example, if you use Composer:
composer install

# Step 2: Run PHPUnit to generate coverage information
vendor/bin/phpunit --coverage-clover coverage.xml

# Step 3: Compare coverage with the target branch
COVERAGE=$(grep -oP 'filename="\K[^"]+' coverage.xml)

COMMENT="## Code Coverage Comparison\n\n"
COMMENT+="| Folder | Target Branch Coverage | Current Branch Coverage | Difference |\n"
COMMENT+="|--------|------------------------|-------------------------|-------------|\n"

for FOLDER in $COVERAGE; do
  TARGET_COVERAGE=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/compare/$TARGET_BRANCH...$GITHUB_SHA" | \
    jq -r --arg folder "$FOLDER" '.files[] | select(.filename == $folder) | .patch' | \
    grep -oP 'lines-total="\K[^"]+')

  CURRENT_COVERAGE=$(grep -oP "filename=\"$FOLDER\".*?lines-total=\"\K[^']+" coverage.xml)

  COMMENT+="| $FOLDER | $TARGET_COVERAGE%      | $CURRENT_COVERAGE%       | +$((CURRENT_COVERAGE - TARGET_COVERAGE))% |\n"
done

# Update the pull request description using the GitHub API
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  -X PATCH \
  -d "{\"body\":\"$COMMENT\"}" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/pulls/$GITHUB_PULL_REQUEST_NUMBER"

# Step 4: Compare coverages and update pull request description
if [ "$CURRENT_COVERAGE" -lt "$COVERAGE_THRESHOLD" ]; then
  echo "Coverage failed: New files added with less than ${COVERAGE_THRESHOLD}% coverage."
  exit 1
fi

if [ "$CURRENT_COVERAGE" -lt "$TARGET_COVERAGE" ]; then
  echo "Coverage failed: Existing files have less coverage than the target branch."
  exit 1
fi
