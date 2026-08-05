# login-migrator-bot

Monitor Cloud Foundry Cloud Controller users and migrate Shibboleth users to Login.gov as matching accounts in both IdPs are created.

The login migrator bot monitors the cloud.gov UAA (User Account and Authentication) server for new accounts.
If a new Login.gov user account is created in UAA with the same email address as a Shibboleth user (aka "Cloud.gov IdP user"), it will automatically copy the organaization and space roles of the Shibboleth user to the new Login.gov user.  The corresponding Cloud.gov user account in UAA is then deleted to complete the migration.  This is to help:
 - Complete the migration process, once migrated, no additional work needs to be done to this particular account. Ever.
 - Avoid confusion in Stratos (aka "Dashboard") otherwise both accounts would be visible with no indicator on which account is for Login.gov and which is for Cloud.gov as the backing IdP.
 - Without the presence of two accounts for the same user, there cannot be drift in the permissions of each that would need to be syncronized or manually resolved.



## Creating CF Service Keys

The user account used by the pipeline to deploy the app uses a Cloud.gov service account brokered service instance.  To create the instance, log into CF, target the `bots` space and run the following, swapping out `myapp` for an appropriately named instance and key:

```
cf create-service cloud-gov-service-account space-deployer myapp
cf create-service-key myapp myapp-key
cf service-key myapp myapp-key
```

The output of the last command needs to be loaded in Concourse Credhub in `cf-staging-user` or `cf-production-user` depending on the environment.

This is one of 3 accounts needed per environment, see the section below labeled `Description of accounts created` for the accounts used.

## Running rspec

Clone the repo locally and run:

```bash
bundle exec rspec
```


To run an individual rspec file, run:

```bash
bundle exec rspec spec/cf_client_spec.rb
bundle exec rspec spec/monitor_helper_spec.rb
```

## Running the app locally

The following environment variables need to be set and run:

```bash
export CLIENT_ID=login-migrator-bot
export CLIENT_SECRET=... value is in credhub
export DOMAIN_NAME=fr-stage.cloud.gov
export DO_SLACK=false
export SLEEP_TIMEOUT=30
export UAA_URL="https://uaa.fr-stage.cloud.gov"
export SLACK_HOOK=nope
export DELETE_SOURCE_USER=true

bundle && ruby ./monitor.rb
```

Note the `DELETE_SOURCE_USER=true` which deletes the `cloud.gov` account once the corresponding `login.gov` account has the org and space roles copied over to it.  This is not required for the acceptance tests to work but should be the behavior tested and used.

## Running the acceptance tests

The `ci/acceptance_tests.sh` makes the following assumptions:

 - The CF CLI is installed
 - A user with `cloud_controller.admin` has logged in via the CF CLI, the pipeline passes this in
 - A copy of the [cg-scripts/cloudfoundry/copy-user-org-and-space-roles.sh](https://github.com/cloud-gov/cg-scripts/blob/main/cloudfoundry/copy-user-org-and-space-roles.sh) is available locally

With the application running, invoke the acceptance tests with:

```bash
ci/acceptance-tests.sh
```

### Description of accounts created

There are three types of accounts created, each with a different purpose:

 - `login-migrator-bot` - UAA Client, defined in the `clients.yml` in `deploy-cf`.  This is used in the ruby application inside monitor.rb to talk to the CF API to look for new user accounts.  There is a credhub-sync job to keep these values in sync.
 - `login-migrator-bot-user` - UAA User, defined in the `users.yml` in `deploy-cf`. This is used by the acceptance tests to create test orgs and users.  There is a credhub-sync job to keep these values in sync.
 - `cg-login-migrator-bot-*` - An instance of the `cloud-gov-service-account` service broker.  This is used to deploy the ruby app in the Concourse pipeline.  It is scoped only to the `bots` space.

## Migration history storage

There is a dedicated S3 bucket created for each environment (staging and production) to store the migration history. The `run-uaa-queries-*` pipeline jobs write the UAA reporting query results as JSON to the bucket for their environment, under the key prefix `uaa/YYYY/MM/DD/HH/MM/SS/`.

These buckets are provisioned with the Cloud.gov `s3` service broker in the `bots` space where the application is deployed. Each bucket name is supplied to the pipeline via `ci/config.yml` (`uaa-queries-s3-bucket-staging` and `uaa-queries-s3-bucket-production`).

### Downloading the query results

`ci/download-uaa-results.sh` mirrors the `uaa/` prefix from the S3 bucket into a
local directory (default `./uaa-results/`), preserving the
`uaa/YYYY/MM/DD/HH/MM/SS/` key structure. It uses `aws s3 sync`, so re-runs only
fetch new or changed objects.

The bucket name is passed in with `-b` and is intentionally not hard-coded. The
production bucket name is the Concourse credential
`((uaa-queries-s3-bucket-production))` (also recorded in `ci/config.yml`).

Run it from a host whose AWS credentials can reach the GovCloud bucket:

```bash
# BUCKET is the value of ((uaa-queries-s3-bucket-production))
ci/download-uaa-results.sh -b "$BUCKET"

# optional overrides:
#   -o OUTPUT_DIR   local directory to sync into (default: ./uaa-results)
#   -r REGION       AWS region (default: $AWS_DEFAULT_REGION or us-gov-west-1)
ci/download-uaa-results.sh -b "$BUCKET" -o ./uaa-results -r us-gov-west-1
```

The `uaa-results/` download directory is git-ignored.

### Running the summary reports

Both reporting scripts read the downloaded tree (default `./uaa-results/`, or
pass `-d` to point elsewhere) and require no third-party libraries.

`ci/summarize-migration-daily.py` collapses each UTC day to a single row using
that day's **last** snapshot and emits just the active-user counts for the
`cloud.gov` and `login.gov` origins:

```bash
ci/summarize-migration-daily.py            # reads ./uaa-results
ci/summarize-migration-daily.py -d ./uaa-results
```

```
date (UTC)    cloud.gov  login.gov
----------------------------------
2026-08-04           80         40
2026-08-05           70         55
```

`ci/summarize-migration-trend.py` prints a per-snapshot table with the migration
percentage, a net-change summary, and a simple ASCII trend chart of `login.gov`
active users over time:

```bash
ci/summarize-migration-trend.py            # reads ./uaa-results
ci/summarize-migration-trend.py -d ./uaa-results
```


## Public domain

This project is in the worldwide public domain. As stated in CONTRIBUTING:

> This project is in the public domain within the United States, and copyright
> and related rights in the work worldwide are waived through the CC0 1.0
> Universal public domain dedication.

All contributions to this project will be released under the CC0 dedication. By
submitting a pull request, you are agreeing to comply with this waiver of
copyright interest.
