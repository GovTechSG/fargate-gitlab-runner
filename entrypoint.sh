#!/bin/bash -e

# Adapted from https://gitlab.com/DanielCMiranda/docker-gitlab-runner-fargate-driver/-/blob/master/docker-entrypoint.sh
# -----------------------------------------------------------------------------
# Important: this scripts depends on some predefined environment variables:
# - GITLAB_REGISTRATION_TOKEN (required): registration token for your project
# - GITLAB_URL (optional): the URL to the GitLab instance (defaults to https://gitlab.com)
# - RUNNER_TAG_LIST (optional): comma separated list of tags for the runner
# - FARGATE_CLUSTER (required): the AWS Fargate cluster name
# - FARGATE_REGION (required): the AWS region where the task should be started
# - FARGATE_SUBNET (required): the AWS subnet where the task should be started
# - FARGATE_SECURITY_GROUP (required): the AWS security group where the task
#   should be started
# - FARGATE_TASK_DEFINITION (required): the task definition used for the task
# -----------------------------------------------------------------------------

check_variable() {
  [ $(eval "echo \${$1}") ] || (echo Env variable $1 is required && exit 1)
}

check_variable RUNNER_NAME
check_variable GITLAB_REGISTRATION_TOKEN
check_variable GITLAB_URL
check_variable FARGATE_CLUSTER
check_variable FARGATE_REGION
check_variable FARGATE_SUBNET
check_variable FARGATE_SECURITY_GROUP
check_variable FARGATE_TASK_DEFINITION


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

    runner_identification="${RUNNER_NAME}_$(date +%Y%m%d_%H%M%S)"

    # Uses the environment variable "GITLAB_REGISTRATION_TOKEN" to register the runner

    result_json=$(
        curl --request POST "${GITLAB_URL}/api/v4/runners" \
            --form "token=$1" \
            --form "description=${runner_identification}" \
            --form "tag_list=$2"
    )

    # Read the authentication token

    auth_token=$(echo $result_json | jq -r '.token')

    # Recreate the runner config.toml based on our template

    export RUNNER_NAME=$runner_identification
    export RUNNER_AUTH_TOKEN=$auth_token
    envsubst < /tmp/config.toml > ${HOME}/.gitlab-runner/config.toml
}

###############################################################################
# Create the Fargate driver TOML configuration file based on a template
# that is persisted in the repository. It uses the environment variables
# passed to the container to set the correct values in that file.
#
# Globals:
#   - FARGATE_CLUSTER
#   - FARGATE_REGION
#   - FARGATE_SUBNET
#   - FARGATE_SECURITY_GROUP
#   - FARGATE_TASK_DEFINITION
###############################################################################
create_driver_config() {
    envsubst < /tmp/ecs.toml > ${HOME}/.gitlab-runner/ecs.toml
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

create_driver_config

register_runner ${GITLAB_REGISTRATION_TOKEN} ${RUNNER_TAG_LIST}

# launch gitlab-runner passing all arguments
exec gitlab-runner "$@"

unregister_runner ${auth_token}
