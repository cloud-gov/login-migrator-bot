# cg-login-migrator-bot

Monitor Cloud Foundry Cloud Controller users and migrate Shibboleth users to Login.gov as matching accounts in both IdPs are created.

The login migrator bot monitors the cloud.gov UAA (User Account and Authentication) server for new accounts.
If a new Login.gov user account is created in UAA with the same email address as a Shibboleth user (aka "Cloud.gov IdP user"), it will automatically copy the organaization and space roles of the Shibboleth user to the new Login.gov user.  The corresponding Cloud.gov user account in UAA is then deleted to complete the migration.  This is to help:
 - Complete the migration process, once migrated, no additional work needs to be done to this particular account. Ever.
 - Avoid confusion in Stratos (aka "Dashboard") otherwise both accounts would be visible with no indicator on which account is for Login.gov and which is for Cloud.gov as the backing IdP.
 - Without the presence of two accounts for the same user, there cannot be drift in the permissions of each that would need to be syncronized or manually resolved.


## Creating UAA client

```shell
uaac client add login-migrator-bot \
	--name "UAA Login Migrator Monitor" \
	--scope "cloud_controller.admin, cloud_controller.read, cloud_controller.write, openid, scim.read" \
	--authorized_grant_types "authorization_code, client_credentials, refresh_token" \
	-s [your-client-secret]
```

This has already been done via adding to the `clients.yml` file in the `deploy-cf` repo


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
 - A user with `cloud_controller.admin` has logged in via the CF CLI
 - A copy of the [cg-scripts/cloudfoundry/copy-user-org-and-space-roles.sh](https://github.com/cloud-gov/cg-scripts/blob/main/cloudfoundry/copy-user-org-and-space-roles.sh) is available locally

With the application running, invoke the acceptance tests with:

```bash
ci/acceptance-tests.sh
```


## Public domain

This project is in the worldwide public domain. As stated in CONTRIBUTING:

> This project is in the public domain within the United States, and copyright
> and related rights in the work worldwide are waived through the CC0 1.0
> Universal public domain dedication.

All contributions to this project will be released under the CC0 dedication. By
submitting a pull request, you are agreeing to comply with this waiver of
copyright interest.
