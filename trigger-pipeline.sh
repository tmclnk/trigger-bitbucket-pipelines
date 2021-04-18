#!/usr/bin/env bash

set -e
################################################################################
# Help Text
################################################################################
help(){
cat <<"EOF"
Runs the bitbucket pipe. If no commit is specified, will check the current
working directory. If it's a git repo, uses that bitbucket repo
and branch.

Flags:
--username            required
--password            required; create in https://bitbucket.org/account/settings/app-passwords/
--pipeline-variables  comma separated
--pipeline            name of a custom pipeline to run on the current branch
--workspace           required
--repo-slug           defaults to the current git repo
--branch              defaults to the current branch
--commit              commit to run pipeline against
--dry-run             just print the generated curl command, don't run it

Example:
./trigger-pipeline.sh --username tom --password myapppassword01234 
./trigger-pipeline.sh --username tom --password myapppassword01234 --workspace mycompany --dry-run

./trigger-pipeline.sh --username tom --password myapppassword01234 --workspace mycompany \
    --pipeline my-environment

./trigger-pipeline.sh --username tom --password myapppassword01234 \
    --workspace mycompany \
    --pipeline deploy-task \
    --pipeline-variables "DESTINATION=my-environment"

./trigger-pipeline.sh --username tom \
    --password myapppassword01234 \
    --workspace mycompany \
    --pipeline deploy-task \
    --pipeline-variables "DESTINATION=my-environment" \
    --commit a3c4e02c9a3755eccdc3764e6ea13facdf30f923

./trigger-pipeline.sh --username tom --password myapppassword01234 \
    --workspace mycompany \
    --pipeline deploy-task \
    --pipeline-variables "DESTINATION=my-environment,DEBUG=true"

EOF
}

################################################################################
# Pretty Colors
################################################################################
RED='\033[0;31m'
NC='\033[0m' # No Color

################################################################################
# Parse Arguments
################################################################################
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -h|--help)
    help
    exit 0
    ;;
    --pipeline)
    pipeline="$2"
    shift # past argument
    shift # past value
    ;;
    --pipeline-variables)
    pipeline_variables="$2"
    shift # past argument
    shift # past value
    ;;
    --workspace)
    workspace="$2"
    shift # past argument
    shift # past value
    ;;
    --username)
    username="$2"
    shift # past argument
    shift # past value
    ;;
    --password)
    password="$2"
    shift # past argument
    shift # past value
    ;;
    --repo-slug)
    repo_slug="$2"
    shift # past argument
    shift # past value
    ;;
    --branch)
    branch="$2"
    shift # past argument
    shift # past value
    ;;
    --commit)
    commit="$2"
    shift # past argument
    shift # past value
    ;;
    --dry-run)
    dry_run="true"
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

################################################################################
# Check Required Variables
################################################################################
if [ -z "$username"  ] || [ -z "$password" ]; then
  help
  >&2 echo -e "${RED}Username and password are required${NC}"
  exit 1
fi

################################################################################
# Set Defaults
################################################################################
repo_slug=${repo_slug:-$(basename "$(git remote show -n origin | grep Fetch | cut -d: -f2-)" | sed 's/\.git//')}

################################################################################
# Parse variables into json
################################################################################
# maybe it's time to start using a "real" language for this crap
variables=',"variables":['
if [ -n "$pipeline_variables" ]; then
  IFS=',' read -ra vars <<< "$pipeline_variables"
  for v in "${vars[@]}"; do
    variables="$variables"$(cat <<EOF
    { "key": "${v%=*}", "value": "${v##*=}" },
EOF
)
  done
  # remove trailing comma
  # shellcheck disable=SC2001
  variables=$(echo "$variables" | sed 's/,$//' )
fi
variables="$variables]"

if [ -n "$pipeline" ]; then
  selector=$(cat <<EOF
  ,"selector": {
    "type": "custom",
    "pattern": "$pipeline"
  }
EOF
)
fi

################################################################################
# Make API Call
################################################################################
# https://developer.atlassian.com/bitbucket/api/2/reference/resource/repositories/%7Bworkspace%7D/%7Brepo_slug%7D/pipelines/#post
if [ -z "$commit" ]; then
branch=${branch:-$(git branch --show-current)}
json=$(jq . <<EOF
{
    "target": {
      "type": "pipeline_ref_target",
      "ref_type": "branch",
      "ref_name": "$branch"
      $selector
    }
    $variables
}
EOF
)
else
json=$(jq . <<EOF
{
    "target": {
      "commit": {
        "hash":"$commit",
        "type": "commit"
        },
        "type":"pipeline_commit_target"
        $selector
    }
    $variables
}
EOF
)
fi

cmd="curl -X POST -is -u $username:$password  -H 'Content-Type: application/json'  https://api.bitbucket.org/2.0/repositories/$workspace/$repo_slug/pipelines/ -d '$json'"

################################################################################
# Run it (or not)
################################################################################
echo "$cmd"
if [ "$dry_run" == "true" ]; then
  echo "Dry run only..."
else
  exec sh -c "$cmd && echo ''"
fi

