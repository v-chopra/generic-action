#!/bin/bash
# Varun Chopra <vchopra@eightfold.ai>
#
# This action runs every time a PR is updated & prepares it for CI.
# CI checks pull requests that are labeled 'needs_ci' and runs unit tests and lint.

set -e

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Set the GITHUB_TOKEN env variable."
  exit 1
fi

if [[ -z "$GITHUB_REPOSITORY" ]]; then
  echo "Set the GITHUB_REPOSITORY env variable."
  exit 1
fi

if [[ -z "$GITHUB_EVENT_PATH" ]]; then
  echo "Set the GITHUB_EVENT_PATH env variable."
  exit 1
fi

# unit_test_psa="Hey there!\\n\\nWhen modifying or adding files on the backend, it's always a good idea to add unit tests. \
# Please consider reading [the following thread](https://eightfoldai.atlassian.net/wiki/spaces/EP/pages/168034305/Testing+Python+Code) and adding unit tests."

URI="https://api.github.com"
API_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"

action=$(jq --raw-output .action "$GITHUB_EVENT_PATH")
pr_body=$(jq --raw-output .pull_request.body "$GITHUB_EVENT_PATH")
number=$(jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH")
title=$(jq --raw-output .pull_request.title "$GITHUB_EVENT_PATH")

echo $title

has_hotfix_label=false
hotfix_failed=false

if [[ "$title" =~ ^HOTFIX.*$ ]]; then
  needs_hotfix=true
fi

add_comment(){
  curl -sSL \
    -H "${AUTH_HEADER}" \
    -H "${API_HEADER}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"body\":\"${1}\"}" \
    "${URI}/repos/${GITHUB_REPOSITORY}/issues/${number}/comments"
}

add_label(){
  curl -sSL \
    -H "${AUTH_HEADER}" \
    -H "${API_HEADER}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"labels\":[\"${1}\"]}" \
    "${URI}/repos/${GITHUB_REPOSITORY}/issues/${number}/labels"
}

remove_label(){
  curl -sSL \
    -H "${AUTH_HEADER}" \
    -H "${API_HEADER}" \
    -X DELETE \
    "${URI}/repos/${GITHUB_REPOSITORY}/issues/${number}/labels/${1// /%20}"
}

body=$(curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}/pulls/${number}")
# changed_files=$(curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}/pulls/${number}/files")

# added_and_modified_files=$(echo "$changed_files" | jq --raw-output '.[] | select(.status == ("modified", "added")).filename')

# for i in $added_and_modified_files; do
#   if [[ "$i" =~ ^.*.py$ ]]; then
#     has_python_files=true
#     break
#   fi
# done
# has_pytest=false

# if [ "$has_python_files" = true ]; then
#   for i in $added_and_modified_files; do
#     echo "$i in added_and_modified_files"
#     if [[ "$i" =~ .*test.*.py$ ]]; then
#       echo "Found a pytest"
#       has_pytest=true
#       break
#     fi
#   done
# fi

labels=$(echo "$body" | jq --raw-output '.labels[].name')

IFS=$'\n'

for label in $labels; do
  case $label in
    needs_revision)
      echo "Removing label: $label"
      remove_label "$label"
      ;;
    ci_verified)
      echo "Removing label: $label"
      remove_label "$label"
      ;;
    needs_hotfix)
      echo "Setting has_hotfix_label=true"
      has_hotfix_label=true
      ;;
    "hotfix:failed")
      echo "Setting hotfix_failed=true"
      hotfix_failed=true
      ;;
#     needs_pytest)
#       if [[ "$has_pytest" = true ]]; then
#         remove_label "$label"
#         add_comment "Thank you for adding unit tests! :metal:"
#       fi
#       ;;
    *:success)
      echo "Removing label: $label"
      remove_label "$label"
      ;;
    *)
      echo "Unknown label $label"
      ;;
  esac
done

add_label "needs_ci"

if [[ ("$needs_hotfix" = true && "$has_hotfix_label" = false && "$hotfix_failed" = false) ]]; then
  echo "Detected HOTFIX pull request that isn't already labeled."
  add_label "needs_hotfix"
fi

# if [[ ("$has_python_files" = true && "$has_pytest" = false) ]]; then
#   echo "Python files detected but pytests are not present!"
#   add_label "needs_pytest"
#   if [[ "$action" == "opened" ]]; then
#     add_comment "$unit_test_psa"
#   fi
# fi

echo "Pull request passed all checkpoints!"
