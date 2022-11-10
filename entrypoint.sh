#!/bin/bash -e

# Adapted from https://gitlab.com/DanielCMiranda/docker-gitlab-runner-fargate-driver/-/blob/master/docker-entrypoint.sh
# -----------------------------------------------------------------------------
# Important: this scripts depends on some predefined environment variables:
# - RUNNER_CONCURRENCY (optional): Number of jobs that can run concurrently, default to 1
# - RUNNER_NAME_PREFIX (required): A prefix to be used for runner name
# - GITLAB_REGISTRATION_TOKEN (required): registration token for your project
# - GITLAB_URL (required): the URL to the GitLab instance
# - MANAGERS_CONFIGS (required): Configs for all managers, with tag list, its worker's docker image, network and security setting.
#      This is expected to be a JSON string with following format:
#        [
#          {
#            "manager_name": "w1",
#            "tag_list" : "a,b,c",
#            "ecs_cluster_arn": "ecs_cluster_arn_1",
#            "aws_region": "region-1",
#            "subnet_id": "subnet-123",
#            "security_group_id": "sg-321",
#            "task_definition_arn": "task_definition_arn_1",
#            "ssh_user": "user_1"
#          },
#          {
#            "manager_name": "w2",
#            "tag_list" : "d,e",
#            "ecs_cluster_arn": "ecs_cluster_arn_2",
#            "aws_region": "region-2",
#            "subnet_id": "subnet-456",
#            "security_group_id": "sg-654",
#            "task_definition_arn": "task_definition_arn_2",
#            "ssh_user": "user_2"
#          }
#        ]
#
# -----------------------------------------------------------------------------

check_variable() {
  [ "$(eval echo \$"$1")" ] || (echo "Env variable $1 is required" && exit 1)
}

check_variable RUNNER_NAME_PREFIX
check_variable GITLAB_REGISTRATION_TOKEN
check_variable GITLAB_URL
check_variable MANAGERS_CONFIGS

###############################################################################
# Remove the Runner from the list of runners of the project identified by the
# authentication token.
#
# Arguments:
#   $1 - Authorization token obtained after registering the runner in the
#        project
###############################################################################
unregister_runner() {
    curl --request DELETE "${GITLAB_URL}/api/v4/runners" --form "token=$1"
}

###############################################################################
# Register the Runner in the desired project, identified by the registration
# token of that project.
#
# The function populates the "auth_token" variable with the authentication
# token for the registered Runner.
#
# Arguments:
#   $1 - Registration token
#   $2 - List of tags for the Runner, separated by comma
###############################################################################
register_runner() {
    # Append date and last 7 chars of task credential id to ensure uniqueness
    runner_identification="${RUNNER_NAME_PREFIX}_${MANAGER_NAME}_$(date +%Y%m%d_%H%M%S)_${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI: -7}"

    echo "Registering new runner with name ${runner_identification}"

    # Uses the environment variable "GITLAB_REGISTRATION_TOKEN" to register the runner

    result_json=$(
        curl --request POST "${GITLAB_URL}/api/v4/runners" \
            --form "token=${GITLAB_REGISTRATION_TOKEN}" \
            --form "description=${runner_identification}" \
            --form "tag_list=${MANAGER_TAG_LIST}"
    )

    # Read the authentication token

    auth_token=$(echo $result_json | jq -r '.token')

    echo "Create runner's driver config file for $runner_identification"
    create_driver_config $runner_identification

    # Recreate the runner config.toml based on our template

    export RUNNER_CONCURRENCY=${RUNNER_CONCURRENCY:-1} # default to 1
    export RUNNER_NAME=$runner_identification
    export RUNNER_AUTH_TOKEN=$auth_token
    echo "Append runner config for $runner_identification to .gitlab-runner/config.toml"
    envsubst < /tmp/config_runner.toml >> "${HOME}"/.gitlab-runner/config.toml
}

###############################################################################
# Create the Fargate driver TOML configuration file based on a template
# that is persisted in the repository. It uses the environment variables
# passed to the container to set the correct values in that file.
#
# Globals:
#   - WORKER_SSH_USER
###############################################################################
create_driver_config() {
    export WORKER_SSH_USER=${WORKER_SSH_USER:-root}
    envsubst < /tmp/fargate_worker.toml > "${HOME}"/.gitlab-runner/"$1".toml
}

update_ca() {
  echo "Updating CA certificates..."
  cp "${CA_CERTIFICATES_PATH}" "${LOCAL_CA_PATH}"
  update-ca-certificates --fresh >/dev/null
}

# gitlab-runner data directory
DATA_DIR="/etc/gitlab-runner"
CONFIG_FILE=${CONFIG_FILE:-$DATA_DIR/config.toml}
# custom certificate authority path
CA_CERTIFICATES_PATH=${CA_CERTIFICATES_PATH:-$DATA_DIR/certs/ca.crt}
LOCAL_CA_PATH="/usr/local/share/ca-certificates/ca.crt"

if [ -f "${CA_CERTIFICATES_PATH}" ]; then
  # update the ca if the custom ca is different than the current
  cmp --silent "${CA_CERTIFICATES_PATH}" "${LOCAL_CA_PATH}" || update_ca
fi

# Use base64 encode and decode to avoid breaking due to special symbols
get_attribute() {
    echo "${1}" | base64 --decode | jq -r "${2}"
}

echo Using MANAGERS_CONFIGS=${MANAGERS_CONFIGS}

echo "Create initial .gitlab-runner/config.toml"
envsubst < /tmp/config.toml > "${HOME}"/.gitlab-runner/config.toml

echo "Go through each worker in the list, populate its fargate driver config and add runner config in config.toml"
for row in $(echo "${MANAGERS_CONFIGS}" | jq -r '.[] | @base64'); do
    export MANAGER_NAME=$(get_attribute "${row}" ".manager_name")
    export MANAGER_TAG_LIST=$(get_attribute "${row}" ".tag_list")
    export RUNNER_LIMIT=$(get_attribute "${row}" ".limit")
    export WORKER_CLUSTER=$(get_attribute "${row}" ".worker_ecs_cluster_arn")
    export WORKER_REGION=$(get_attribute "${row}" ".worker_aws_region")
    export WORKER_SUBNET=$(get_attribute "${row}" ".worker_subnet_id")
    export WORKER_SECURITY_GROUP=$(get_attribute "${row}" ".worker_security_group_id")
    export WORKER_TASK_DEFINITION=$(get_attribute "${row}" ".worker_task_definition_arn")
    export WORKER_SSH_USER=$(get_attribute "${row}" ".worker_ssh_user")

    # Register the runner with GitLab
    register_runner
done

# launch gitlab-runner passing all arguments
exec gitlab-runner "$@"

# Comment out as this cannot be reached, requires a different way to unregister
# unregister_runner ${auth_token}
