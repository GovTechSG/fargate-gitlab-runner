# fargate-gitlab-runner

Docker image for ECS task for Fargate GitLab runner managers, using [GitLab custom executor driver for AWS Fargate](https://gitlab.com/gitlab-org/ci-cd/custom-executor-drivers/fargate).

This repo is part of a set of repos for the complete setup of ECS Service for managers and workers:
* [fargate-gitlab-runner](../../../fargate-gitlab-runner): Docker image for the ECS task for all runner managers 
* [fargate-gitlab-runner-worker](../../../fargate-gitlab-runner-worker): Sample docker images for the worker ECS tasks
* [fargate-gitlab-runner-terraform](../../../fargate-gitlab-terraform): Terraform code to set up complete ECS Service for managers and workers


## Features
* Use environment variables for dynamic runtime setup
* Support multiple manager configurations, each has its own runner tag list, worker's docker image, network and security setting. For example:
```json
{
  "w1": {
    "manager_name": "w1",
    "tag_list": "a,b,c",
    "limit": 10,
    "worker_ecs_cluster_arn": "ecs_cluster_arn_1",
    "worker_aws_region": "region-1",
    "worker_subnet_id": "subnet-123",
    "worker_security_group_id": "sg-321",
    "worker_task_definition_arn": "task_definition_arn_1",
    "worker_ssh_user": "user_1"
  },
  "w2": {
    "manager_name": "w2",
    "tag_list": "d,e",
    "limit": 20,
    "worker_ecs_cluster_arn": "ecs_cluster_arn_2",
    "worker_aws_region": "region-2",
    "worker_subnet_id": "subnet-456",
    "worker_security_group_id": "sg-654",
    "worker_task_definition_arn": "task_definition_arn_2",
    "worker_ssh_user": "user_2"
  }
}
```

## Architecture
![ECS Fargate GitLab runner Architecture](assets/ECS%20Fargate%20GitLab%20runner%20Architecture.png)


## Build the image
* Set `IMAGE_NAME` and `IMAGE_TAG` variables as desired.
* Use `docker-compose build` to build the image. Alternatively run: `docker build -t ${IMAGE_NAME}:${IMAGE_TAG}`.

**Note:** If you use `podman` instead of `docker`, install [podman-compose](https://github.com/containers/podman-compose) to work with `docker-compose.yml`.


## Local test
* Set `RUNNER_NAME_PREFIX`, `GITLAB_REGISTRATION_TOKEN`, `GITLAB_URL` and `MANAGERS_CONFIGS` variables. `MANAGERS_CONFIGS` can be set using the sample config: `export MANAGERS_CONFIGS=$(cat samples/managers_configs.json)`.
* To test the image, use `docker-compose down >/dev/null 2>&1; docker-compose up` or `docker run --rm -e GITLAB_URL -e GITLAB_REGISTRATION_TOKEN -e RUNNER_NAME_PREFIX -e MANAGERS_CONFIGS ${IMAGE_NAME}:${IMAGE_TAG}`.


## Publish to ECR
* Set `AWS_ACCOUNT_ID` and `AWS_REGION` variables as desired.
* Login to ECR `aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com`
* Publish to ECR using `docker-compose push` or `docker push ${IMAGE_NAME}:${IMAGE_TAG}` where `${IMAGE_NAME}` starts with the ecr domain `${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com`


## Known limitation:
* The Fargate driver doesn't support ECS Exec yet. For more info: https://gitlab.com/gitlab-org/ci-cd/custom-executor-drivers/fargate/-/issues/49


## Credits:
* This image is adapted from https://gitlab.com/DanielCMiranda/docker-gitlab-runner-fargate-driver and https://www.proud2becloud.com/a-serverless-approach-for-gitlab-integration-on-aws/.
