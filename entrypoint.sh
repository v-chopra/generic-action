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

unit_test_psa="Hey there!\\n\\nWhen modifying or adding files on the backend, it's always a good idea to add unit tests. \
Please consider reading [the following thread](https://eightfoldai.atlassian.net/wiki/spaces/EP/pages/168034305/Testing+Python+Code) and adding unit tests."

URI="https://api.github.com"
API_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"

action=$(jq --raw-output .action "$GITHUB_EVENT_PATH")
pr_body=$(jq --raw-output .pull_request.body "$GITHUB_EVENT_PATH")
number=$(jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH")

add_comment(){
  curl -sSL \
    -H "${AUTH_HEADER}" \
    -H "${API_HEADER}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"body\":[\"${1}\"]}" \
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
    "${URI}/repos/${GITHUB_REPOSITORY}/issues/${number}/labels/${1}"
}

body=$(curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}/pulls/${number}")
changed_files=$(curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}/pulls/${number}/files")

added_and_modified_files=$(echo "$changed_files" | jq --raw-output '.[] | select(.status == ("modified", "added")).filename')

for i in $added_and_modified_files; do
  if [[ "$i" =~ ^.*.py$ ]]; then
    has_python_files=true
    break
  fi
done
has_pytest=false

if [ "$has_python_files" = true ]; then
  for i in $added_and_modified_files; do
    echo "$i in added_and_modified_files"
    if [[ "$i" =~ test_.*.py$ ]]; then
      echo "Found a pytest"
      has_pytest=true
      break
    fi
  done
fi

echo "+----------+ ACTION +----------+"
echo "$action"

echo "+----------+ BODY +----------+"
echo "$body"

labels="$(echo "$body" | jq --raw-output '.labels[].name')"

echo "+----------+ LABELS +----------+"
echo "$labels"

for label in $labels; do
  case $label in
    needs_revision)
      remove_label "$label"
      ;;
    ci_verified)
      remove_label "$label"
      ;;
    needs_test_plan)
      if [[ "pr_body" == *"TEST PLAN"* ]]; then
        remove_label "$label"
      fi
      ;;
    needs_pytest)
      if [[ "$has_pytest" = true ]]; then
        remove_label "$label"
        add_comment "Thank you for adding unit tests! :metal:"
      fi
      ;;
    *)
      echo "Unkown label $label"
      ;;
  esac
done

add_label "needs_ci"

if [[ ("$has_python_files" = true && "$has_pytest" = false) ]]; then
  echo "Python files detected but pytests are not present!"
  add_label "needs_pytest"
  if [[ "$action" == "opened" ]]; then
    add_comment "$unit_test_psa"
  fi
fi

echo "+----------+ RESULT +----------+"
if [[ "$pr_body" != *"TEST PLAN"* ]]; then
  echo "Test plan is not present!"
  add_label "needs_test_plan"
  exit 40  
fi

echo "Pull request passed all checkpoints!"
