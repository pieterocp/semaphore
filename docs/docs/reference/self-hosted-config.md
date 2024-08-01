---
description: Self-hosted agents configuration reference
---

# Self-hosted Agents Settings

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import Available from '@site/src/components/Available';
import VideoTutorial from '@site/src/components/VideoTutorial';

<Available plans={['Startup (Hybrid)', 'Scaleup (Hybrid)']}/>

This page describes all the settings available to configure [self-hosted agents](../using-semaphore/self-hosted).

## Overview

Self-hosted agents accept configuration settings in three ways. In order of precedence:

- **command line arguments**: used when starting the agent, e.g. `agent start --endpoint my-org.semaphoreci.com`
- **environment variables**: supplied when starting the agent. All configuration variable names are prefixed with `SEMAPHORE_AGENT`. So, for example the `--disconnect-after-job` argument is transformed into `SEMAPHORE_AGENT_DISCONNECT_AFTER_JOB`
- **configuration file**: using the `--config` option when starting the agent, e.g. `agent start --config config.yml`


## Configuration parameters

This section describes the available configuration parameters.

### Endpoint {#endpoint}

- **argument name**: `endpoint`
- **mandatory**: yes
- **default value**: Empty string
- **environment variable**: `SEMAPHORE_AGENT_ENDPOINT`

This is the endpoint the agent connects to to register, sync, and pull job information. This is your the same as your [organization URL](../using-semaphore/organizations#general-settings).

### Token {#token}

- **argument name**: `token`
- **mandatory**: yes
- **default value**: Empty string
- **environment variable**: `SEMAPHORE_AGENT_TOKEN`

This is the unique token generated by Semaphore during [agent registration](../using-semaphore/self-hosted-install#register-agent). The registration token is used to validate and secure access to your Semaphore organization.

### Agent name {#name}

- **argument name**: `name`
- **mandatory**: no
- **default value**: Empty string
- **environment variable**: `SEMAPHORE_AGENT_NAME`

Agents generate a random name when this argument is empty. Set this value to force a specific name for this agent. The name length must be between 8 and 64 characters.

A pre-signed AWS STS GetCallerIdentity URL can also be used if the [agent type](../using-semaphore/self-hosted)] allows it.


### Environment variables {#env-vars}

- **argument name**: `env-vars`
- **mandatory**: no
- **default value**: Empty array
- **environment variable**: `SEMAPHORE_AGENT_ENV_VARS`

Environment variables to pass to the agent's job. This is a way of exposing secrets to your jobs via an agent, instead of using Semaphore [secrets](../using-semaphore/secrets).

Command line argument `--env-vars` expects a comma-separated list of `VAR=VALUE`. For example:

```shell
agent start \
  --endpoint my-org.semaphoreci.com \
  --token "..." \
  --env-vars VAR1=A,VAR2=B
```

On configuration files, the agent expects an array of strings using. For example:

```yaml title="config.yml"
endpoint: "my-org.semaphoreci.com"
token: "..."
env-vars:
  - VAR1=A
  - VAR2=B
```

### Files {#files}

- **argument name**: `files`
- **mandatory**: no
- **default value**: Empty array
- **environment variable**: `SEMAPHORE_AGENT_FILES`

You can inject files into the job environment when running Docker containers. This is another way of exposing secrets to your jobs via an agent, instead of using Semaphore [secrets](../using-semaphore/secrets).

On command line usage `--files` the agent expects a comma-separated list of `/host/path:/container/path`. For example:

```shell
agent start \
  --endpoint my-org.semaphoreci.com \
  --token "..." \
  --files /tmp/host/file1:/tmp/container/file1,/tmp/host/file2:/tmp/container/file2
```

With the configuration file, the agent expects an array of strings. For example

```yaml title="config.yml"
endpoint: "my-org.semaphoreci.com"
token: "..."
files:
  - /tmp/host/file1:/tmp/container/file1
  - /tmp/host/file2:/tmp/container/file2
```

### Fail on missing files {#fail-missing-files}

- **argument name**: `fail-on-missing-files`
- **mandatory**: no
- **default value**: false
- **environment variable**: `SEMAPHORE_AGENT_FAIL_ON_MISSING_FILES`

When true, it causes missing [files](#files) to fail the job without starting. Leave as false to continue jobs even when the files are not found.

### Fail on pre-job hook error {#fail-prejob}

- **argument name**: `fail-on-pre-job-hook-error`
- **mandatory**: no
- **default value**: false
- **environment variable**: `SEMAPHORE_AGENT_FAIL_ON_PRE_JOB_HOOK_ERROR`
 
Controls whether the agent should fail the job if the [pre-job hook](#prejob) configured with `--pre-job-hook-path` fails execution. By default, the job continues normally even if the pre-job hook fails.

### Disconnect after job {#disconnect-after-job}

- **argument name**: `disconnect-after-job`
- **mandatory**: no
- **default value**: false
- **environment variable**: `SEMAPHORE_AGENT_DISCONNECT_AFTER_JOB`

When true, the agent will disconnect from Semaphore and shut down after completing a job. Leave false to allow the agent to remain online waiting for new jobs.
 
### Disconnect after idle timeout {#disconnect-after-idle-timeout}

- **argument name**: `disconnect-after-idle-timeout`
- **mandatory**: no
- **default value**: 0
- **environment variable**: `SEMAPHORE_AGENT_DISCONNECT_AFTER_IDLE_TIMEOUT`

If 0, the agent never disconnects due to idleness. To force disconnection after a set duration in seconds, initialize this argument to a value greater than 0.

### Upload job logs {#upload-job-logs}

- **argument name**: `upload-job-logs`
- **mandatory**: no
- **default value**: never
- **environment variable**: `SEMAPHORE_AGENT_UPLOAD_JOB_LOGS`

This setting controls if the job logs are to be uploaded to the [job artifact storage](../using-semaphore/artifacts#jobs). There are three possible options:

- `never`: job logs are never uploaded
- `when-trimmed`: job logs are only uploaded if they were trimmed due to exceeding the [log 16MB limit](./quotas-and-limits#logs)
- `always`: job logs are always uploaded

The logs are uploaded to the path `agent/job_logs.txt` in the job artifact storage.

The agent uses the [artifact CLI](./toolbox#artifact) to upload the logs to Semaphore. If the artifact CLI is not available to the agent, nothing will be uploaded.

### Pre job hook path {#prejob}

- **argument name**: `pre-job-hook-path`
- **mandatory**: no
- **default value**: Empty string
- **environment variable**: `SEMAPHORE_AGENT_PRE_JOB_HOOK_PATH`
 
A path to a Bash or PowerShell script to be executed before the agent starts a job. This setting allows you to set up the environment before the job takes place.

The job continues even if the script is missing or fails. If you want to avoid running the job when the hook script fails, set [`fail-on-pre-job-hook-error`](#fail-prejob) to true.

To control if the script runs on a separate session see [`source-pre-job-hook`](#source-prejob)

### Source pre job hook {#source-prejob}


- **argument name**: `source-pre-job-hook`
- **mandatory**: no
- **default value**: false
- **environment variable**: `SEMAPHORE_AGENT_PRE_JOB_HOOK`

This controls how [`pre-job-hook-path`](#prejob) is executed. When false, the script runs on a separate Bash/PowerShell session. If true, the script is sourced (`source myscript`) in the same session as the job. This allows you to export environment variables into the job environment.

### Post job hook path {#postjob}

- **argument name**: `post-job-hook-path`
- **mandatory**: no
- **default value**: Empty string
- **environment variable**: `SEMAPHORE_AGENT_POST_JOB_HOOK_PATH`

A path to a Bash or PowerShell script to be executed after the agent stops a job. The script will run after the [job epilogue](../using-semaphore/jobs#epilogue), just before terminating the PTY created for the job. Thus, the script has access to all environment variables used in the job.

### Shutdown hook path {#shutdown-path}

- **argument name**: `shutdown-hook-path`
- **mandatory**: no
- **default value**: Empty string
- **environment variable**: `SEMAPHORE_AGENT_SHUTDOWN_HOOK_PATH`

A Bash or PowerShell script to be executed just before the agent shuts down. This can be useful to run clean-up operations like pushing the agent's logs to an external storage. 

It can also be useful when used in conjunction with [`disconnect-after-job`](#disconnect-after-job) or [`disconnect-after-idle-timeout`](#disconnect-after-idle-timeout) in order to rotate agents and make sure you get a clean one for every job you run.

For example, if you want to turn off the machine once the agent shuts down, use the following:

```yaml title="config.yml"
endpoint: "my-org.semaphoreci.com"
token: "..."
shutdown-hook-path: "/opt/semaphore/agent/hooks/shutdown.sh"
```

```sh
# /opt/semaphore/agent/hooks/shutdown.sh
sudo poweroff -f
```

If the path specified does not exist, an error will be logged and the agent will disconnect as usual.

During the shutdown, the reason for the shutdown is specified in the environment variable `SEMAPHORE_AGENT_SHUDOWN_REASON`. Possible values are:

- `IDLE`
- `JOB_FINISHED`
- `UNABLE_TO_SYNC`
- `REQUESTED`
- `INTERRUPTED`

### Interruption grace period {#grace-period}

- **argument name**: `interruption-grace-period`
- **mandatory**: no
- **default value**: 0
- **environment variable**: `SEMAPHORE_AGENT_INTERRUPTION_GRACE_PERIOD`

The agent stops the job and shuts down immediately after receiving an interruption request. Set this value to a number greater than 0 seconds to force the agent to wait this amount of time before shutting down.

## See also

- [How to use self-hosted agents](../using-semaphore/self-hosted)
- [How to install self-hosted agents](../using-semaphore/self-hosted-install)
- [How to configure self-hosted agents](../using-semaphore/self-hosted-configure)
- [How to run an autoscaling fleet of agents in AWS](../using-semaphore/self-hosted-aws)