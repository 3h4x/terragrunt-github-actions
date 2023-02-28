#!/bin/bash

function terragruntPlan {
  # Gather the output of `terragrunt plan`.
  echo "plan: info: planning Terragrunt configuration in ${tfWorkingDir}"
  ${tfBinary} plan -detailed-exitcode -input=false -compact-warnings -no-color -out=tfplan.binary ${*} 2>/dev/null > plan_output
  planExitCode=${?}

  # Get only changes from plan
  echo "### Plan for ${tfWorkingDir}}" > plan
  echo >> plan
  csplit -n2 plan_output '/Terraform will perform the following actions:/' "{*}"
  ls -lah
  rm xx00 # First split doesn't contain anything useful
  for i in xx*; do
    grep -B1000 'Plan: ' $i >> plan
  done

  planHasChanges=false
  planCommentStatus="Failed"

  # Exit code of 0 indicates success with no changes. Print the output and exit.
  if [ ${planExitCode} -eq 0 ]; then
    echo "plan: info: successfully planned Terragrunt configuration in ${tfWorkingDir}"
    echo
    echo ::set-output name=tf_actions_plan_has_changes::${planHasChanges}
    exit ${planExitCode}
  fi

  # Exit code of 2 indicates success with changes. Print the output, change the
  # exit code to 0, and mark that the plan has changes.
  if [ ${planExitCode} -eq 2 ]; then
    planExitCode=0
    planHasChanges=true
    planCommentStatus="Success"
    echo "plan: info: successfully planned Terragrunt configuration in ${tfWorkingDir}"
    echo

    # If output is longer than max length (65536 characters), keep last part
    # planOutput=$(echo "${planOutput}" | tail -c 65000 )

    if [[ "${planJsonOutputEnabled}" == "true" ]]; then
      # Generate plan in JSON
      plans=($(find . -name tfplan.binary))

      planjsons=()
      for plan in "${plans[@]}"; do
        # Find the Terraform working directory for running terragrunt show
        # We want to take the dir of the plan file and strip off anything after the .terraform-cache dir
        # to find the location of the Terraform working directory that contains the Terraform code
        dir=$(dirname $plan)
        dir=$(echo "$dir" | sed 's/\(.*\)\/\.terragrunt-cache\/.*/\1/')

        # Customize this to how you run Terragrunt
        echo "Running terragrunt show for $(basename $plan) for $dir"
        terragrunt show -json $(basename $plan) --terragrunt-working-dir=$dir > tfplan.json
      done

      find . -name tfplan.json
      planJsonOutput=$(find . -name tfplan.json -exec jq -c '.resource_changes[]' {} \; | jq -s 'map({(.address): select(.change.actions[] | contains("no-op") | not )}) | add')
      echo ${planJsonOutput} > tfplan.json
    fi

    echo "::set-output name=tf_actions_plan_json_output::${planJsonOutput}"
  fi

  # Exit code of !0 indicates failure.
  if [ ${planExitCode} -ne 0 ]; then
    echo "plan: error: failed to plan Terragrunt configuration in ${tfWorkingDir}"
    echo
  fi

  # Comment on the pull request if necessary.
  if [ "$GITHUB_EVENT_NAME" == "pull_request" ] && [ "${tfComment}" == "1" ] && ([ "${planHasChanges}" == "true" ] || [ "${planCommentStatus}" == "Failed" ]); then
    planCommentWrapper="#### \`${tfBinary} plan\` ${planCommentStatus}
<details><summary>Show Output</summary>

\`\`\`
${planJsonOutput}
\`\`\`

</details>

*Workflow: \`${GITHUB_WORKFLOW}\`, Action: \`${GITHUB_ACTION}\`, Working Directory: \`${tfWorkingDir}\`, Workspace: \`${tfWorkspace}\`*"

    planCommentWrapper=$(stripColors "${planCommentWrapper}")
    echo "plan: info: creating JSON"
    planPayload=$(echo "${planCommentWrapper}" | jq -R --slurp '{body: .}')
    planCommentsURL=$(cat ${GITHUB_EVENT_PATH} | jq -r .pull_request.comments_url)
    echo "plan: info: commenting on the pull request"
    echo "${planPayload}" | curl -s -S -H "Authorization: token ${GITHUB_TOKEN}" --header "Content-Type: application/json" --data @- "${planCommentsURL}" > /dev/null
  fi

  echo ::set-output name=tf_actions_plan_has_changes::${planHasChanges}

  # https://github.com/orgs/community/discussions/26288
  planOutput=$(cat plan)
  planOutput="${planOutput//'%'/'%25'}"
  planOutput="${planOutput//$'\n'/'%0A'}"
  planOutput="${planOutput//$'\r'/'%0D'}"

  echo "::set-output name=tf_actions_plan_output::${planOutput}"
  exit ${planExitCode}
}
