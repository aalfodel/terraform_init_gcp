#!/usr/bin/env bash


### CONSTANTS

## REQUIRED GCP IAM ROLES FOR THE USER EXECUTING THIS SCRIPT ##
# NOTE
# Remember that granting GCP IAM access to or revoking IAM access from resources is only **eventually consistent**
# See:
#   * https://cloud.google.com/storage/docs/consistency#eventually_consistent_operations
#   * https://stackoverflow.com/questions/51410633/service-account-does-not-have-storage-objects-get-access-for-google-cloud-storage
USER_REQUIRED_ROLES=(
    roles/iam.securityAdmin        # (Security Admin)
    roles/servicemanagement.admin  # (Service Management Administrator)
    roles/storage.admin            # (Storage Admin)
)

# echo params for pretty print
NOCOLOR='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
SCRIPTNAME="[$(basename $0 .sh)]"


### FUNCTIONS

check_installed() {
    if ! command -v "$1"; then
        echo -e "$SCRIPTNAME ${RED}ERROR No locally installed \"$1\" command found.${NOCOLOR}"
        echo -e "$SCRIPTNAME ${RED}      See: https://cloud.google.com/sdk/install for GCP tools.${NOCOLOR}"
        echo -e "$SCRIPTNAME ${RED}      See: https://www.terraform.io/downloads.html for Terraform tools. Note that \"terraform\" command must be in your \"\$PATH\".${NOCOLOR}"
        exit 1
    fi
}

check_user_logged_in() {
    logged_in_account=$(gcloud config list account --format="value(core.account)")
    if [ -z "$logged_in_account" ];then
        echo -e "$SCRIPTNAME ${RED}ERROR Can\'t find any logged-in account{NOCOLOR}"
        echo -e "$SCRIPTNAME ${RED}      See: https://cloud.google.com/sdk/gcloud/reference/auth/login${NOCOLOR}"
        exit 1
    fi
}

check_project_exist() {
    if [ -z "$(gcloud projects list --filter="PROJECT_ID:$1" --format="[no-heading](PROJECT_ID)")" ]; then
        echo -e "$SCRIPTNAME ${RED}ERROR No project with Project ID \"$1\" found${NOCOLOR}"
        echo -e "$SCRIPTNAME ${RED}      Are you using a Project Name instead of a Project ID maybe ?${NOCOLOR}"
        echo -e "$SCRIPTNAME ${RED}      See: https://cloud.google.com/resource-manager/docs/creating-managing-projects#identifying_projects${NOCOLOR}"
        exit 1
    fi
}

check_iam_roles() {
    for role in "${USER_REQUIRED_ROLES[@]}"; do
        if [ -z "$(gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' --format='table[no-heading](bindings.role)' --filter="bindings.members:$logged_in_account AND ROLE:$role")" ]; then
            echo -e "$SCRIPTNAME ${RED}ERROR Missing role \"$role\" for user \"$logged_in_account\" on project \"$PROJECT_ID\"${NOCOLOR}"
            exit 1
        fi
    done
}

check_dir_writable() {
    if [ ! -w "$1" ]; then
        echo -e "$SCRIPTNAME ${RED}ERROR Directory \"$1\" is not writable${NOCOLOR}"
        echo -e "$SCRIPTNAME ${RED}      This script needs permission to create files into \"$1\"${NOCOLOR}"
        exit 1
    fi
}

check_file_exist() {
    if [ -f "$1" ]; then
        echo -e "$SCRIPTNAME ${RED}ERROR File \"$1\" already exists${NOCOLOR}"
        echo -e "$SCRIPTNAME ${RED}      Do a backup of \"$1\" before running this script (for example with: mv $1 $1.bak)${NOCOLOR}"
        exit 1
    fi
}

check_dir_exist() {
    if [ -d "$1" ]; then
        echo -e "$SCRIPTNAME ${RED}ERROR Directory \"$1\" already exists${NOCOLOR}"
        echo -e "$SCRIPTNAME ${RED}      Do a backup of \"$1\" before running this script (for example with: mv $1 $1.bak)${NOCOLOR}"
        exit 1
    fi
}

check_api_enabled() {
    count_wait=0
    while [ -z "$(gcloud services list --enabled --filter="NAME:$1" --format="[no-heading](NAME)")" ]; do
        sleep 5
        ((count_wait+=1))
        if [ $count_wait -gt 35 ]; then
            echo -e "$SCRIPTNAME ${RED}ERROR Timed out waiting for API \"$1\" to be enabled${NOCOLOR}"
            exit 2
        fi
    done
}

add_iam_binding_sa() {
    bind_project=$1
    bind_email=$2
    bind_role=$3
    bind_condition=$4

    if [ -z "$bind_condition" ]; then
        bind_condition="None"
    fi

    gcloud projects add-iam-policy-binding $bind_project \
      --member serviceAccount:$bind_email \
      --role $bind_role \
      --condition=$bind_condition
}


### MAIN

set -e
echo -e "$SCRIPTNAME ${GREEN}Terraform bootstrap started${NOCOLOR}"

## READ USER PARAMS

echo "$SCRIPTNAME Setting primary constants"
######################################################################
# CONSTANTS TO BE CUSTOMIZED TO BOOTSTRAP TERRAFORM ON A GCP PROJECT #
PROJECT_ID=""
PREFIX=""               # suggested: same as PROJECT_ID
DEFAULT_REGION=""       # suggested: europe-west1
DEFAULT_MULTIREGION=""  # suggested: eu
######################################################################
flag="n"
while [ "$flag" != "y" ]; do
    echo
    echo "  Please insert your values"

    PROJECT_ID_REGEX='^[a-z][-a-z0-9]{4,28}[a-z0-9]$'  # Reference: https://cloud.google.com/resource-manager/docs/creating-managing-projects
    read -e -p "  GCP Project ID: " PROJECT_ID
    while [[ -z "$PROJECT_ID" || ! "$PROJECT_ID" =~ $PROJECT_ID_REGEX ]]; do
        echo -e "  $SCRIPTNAME ${RED}Empty or invalid GCP Project ID value. Admitted values: $PROJECT_ID_REGEX${NOCOLOR}"
        read -e -p "  GCP Project ID: " PROJECT_ID
    done

    read -e -p "  GCP Resources prefix [default: $PROJECT_ID]: " PREFIX
    PREFIX=${PREFIX:-$PROJECT_ID}

    read -e -p "  GCP Default Region [default: europe-west1]: " DEFAULT_REGION
    DEFAULT_REGION=${DEFAULT_REGION:-europe-west1}

    read -e -p "  GCP Default Multiregion [default: eu]: " DEFAULT_MULTIREGION
    DEFAULT_MULTIREGION=${DEFAULT_MULTIREGION:-eu}

    echo
    echo "  Values recap"
    echo "  GCP Project ID:          $PROJECT_ID"
    echo "  GCP Resources prefix:    $PREFIX"
    echo "  GCP Default Region:      $DEFAULT_REGION"
    echo "  GCP Default Multiregion: $DEFAULT_MULTIREGION"
    read -e -p "  Confirm ? (y/n/exit): " flag
    if [ "$flag" = "exit" ]; then
        echo
        echo -e "$SCRIPTNAME Exiting. No resources were created."
        exit 1
    fi
done
echo

echo "$SCRIPTNAME Calculating secondary constants from previous replies"
SERVICE_ACCOUNT_NAME=terraform
SERVICE_ACCOUNT_KEYFILE=$PREFIX-$SERVICE_ACCOUNT_NAME-key.json
SERVICE_ACCOUNT_SECRET=$PREFIX-$SERVICE_ACCOUNT_NAME-secret-key
TERRAFORM_BUCKET=$PREFIX-$SERVICE_ACCOUNT_NAME-bucket
TERRAFORM_BACKENDFILE=$PREFIX-$SERVICE_ACCOUNT_NAME-backend.txt
TERRAFORM_SECRET=$PREFIX-$SERVICE_ACCOUNT_NAME-secret-backend

## PRELIMINARY CHECKS

echo "$SCRIPTNAME Checking locally installed tools"
check_installed gcloud
check_installed gsutil
check_installed terraform

echo "$SCRIPTNAME Checking gcloud logged-in user"
check_user_logged_in

echo "$SCRIPTNAME Switching to project \"$PROJECT_ID\""
check_project_exist "$PROJECT_ID"
gcloud config set project "$PROJECT_ID"

echo "$SCRIPTNAME Checking user roles on project \"$PROJECT_ID\""
check_iam_roles

echo "$SCRIPTNAME Checking existing files and directories to prevent accidental overrides"
check_file_exist "$(dirname $(pwd))"/.gitignore
check_dir_exist "$(dirname $(pwd))"/secrets

echo "$SCRIPTNAME Checking if directories are writable"
check_dir_writable "$(dirname $(pwd))"  # parent dir
check_dir_writable "$(pwd)"

## CREATE SUPPORT FILES

echo "$SCRIPTNAME Creating \"secrets\" directory"
mkdir "$(dirname $(pwd))/secrets"  # creates the new dir inside the parent directory of the current dir
[ -d "$(dirname $(pwd))/secrets" ] && echo -e "$SCRIPTNAME ${YELLOW}INFO Directory \"secrets\" has been created into \"$(dirname $(pwd))\"${NOCOLOR}"

echo "$SCRIPTNAME Creating \"secrets/README-secrets.md\" file"
cat << EOF > "../secrets/README-secrets.md"
# README-secrets
Put secrets into this directory.
**Files inside this directory will not be managed by git.**
EOF
[ -f "$(dirname $(pwd))/secrets/README-secrets.md" ] && echo -e "$SCRIPTNAME ${YELLOW}INFO File \"README-secrets.md\" has been created into \"$(dirname $(pwd))/secrets\"${NOCOLOR}"

echo "$SCRIPTNAME Creating \".gitignore\" file"
cat << EOF > "../.gitignore"
## SECRETS

**/secrets/**
!**/secrets/README-secrets.md

## TERRAFORM

# Ignore local .terraform directories
**/.terraform/*

# Ignore .tfstate files
**/*.tfstate
**/*.tfstate.*

# Ignore crash log files
**/crash.log

# Ignore override files as they are usually used to override resources locally and so
# are not checked in
**/override.tf
**/override.tf.json
**/*_override.tf
**/*_override.tf.json

# Ignore the plan output of command: terraform plan -out=tfplan
**/*tfplan*

# Ignore CLI configuration files
**/.terraformrc
**/terraform.rc
EOF
[ -f "$(dirname $(pwd))/.gitignore" ] && echo -e "$SCRIPTNAME ${YELLOW}INFO File \".gitignore\" has been created into \"$(dirname $(pwd))\"${NOCOLOR}"

## CREATE GCP RESOURCES

echo "$SCRIPTNAME Creating service account for Terraform"
gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME
service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "$SCRIPTNAME Creating key file for Terraform service account"
gcloud iam service-accounts keys create ../secrets/$SERVICE_ACCOUNT_KEYFILE \
  --iam-account $service_account_email
[ -f "$(dirname $(pwd))/secrets/$SERVICE_ACCOUNT_KEYFILE" ] && echo -e "$SCRIPTNAME ${YELLOW}INFO File \"$SERVICE_ACCOUNT_KEYFILE\" has been created into \"$(dirname $(pwd))/secrets\"${NOCOLOR}"

echo "$SCRIPTNAME Adding roles to Terraform service account"
terraform_sa_roles=(
    roles/editor
    roles/iam.securityAdmin
    roles/storage.admin
    roles/compute.networkAdmin
    roles/logging.admin
)
for tf_sa_role in "${terraform_sa_roles[@]}"; do
    add_iam_binding_sa "$PROJECT_ID" "$service_account_email" "$tf_sa_role"
done
echo "$SCRIPTNAME Waiting 60 seconds to let IAM Roles get consistent"
sleep 60

echo "$SCRIPTNAME Creating versioned bucket for remote tfstate"
gsutil mb -l "$DEFAULT_MULTIREGION" -b on gs://$TERRAFORM_BUCKET
gsutil versioning set on gs://$TERRAFORM_BUCKET

echo "$SCRIPTNAME Creating Terraform backend file"
cat << EOF > "../secrets/$TERRAFORM_BACKENDFILE"
bucket      = "$TERRAFORM_BUCKET"
credentials = "../secrets/$SERVICE_ACCOUNT_KEYFILE"
EOF
[ -f "$(dirname $(pwd))/secrets/$TERRAFORM_BACKENDFILE" ] && echo -e "$SCRIPTNAME ${YELLOW}INFO File \"$TERRAFORM_BACKENDFILE\" has been created into \"$(dirname $(pwd))/secrets\"${NOCOLOR}"

echo "$SCRIPTNAME Enablig GCP API for Secret Manager"
gcloud services enable secretmanager.googleapis.com
check_api_enabled "secretmanager.googleapis.com"

echo "$SCRIPTNAME Creating secret for Terraform service account key file"
gcloud secrets create $SERVICE_ACCOUNT_SECRET --replication-policy=automatic
echo "$SCRIPTNAME Adding service account key file into secret"
gcloud secrets versions add $SERVICE_ACCOUNT_SECRET --data-file=../secrets/$SERVICE_ACCOUNT_KEYFILE

echo "$SCRIPTNAME Creating secret for Terraform backend file"
gcloud secrets create $TERRAFORM_SECRET --replication-policy=automatic
echo "$SCRIPTNAME Adding Terraform backend file into secret"
gcloud secrets versions add $TERRAFORM_SECRET --data-file=../secrets/$TERRAFORM_BACKENDFILE

## CREATE BASIC TERRAFORM PROJECT FILES

echo "$SCRIPTNAME Creating \"terraform_remote_backend.tf\" file"
cat << EOF > terraform_remote_backend.tf
# NOTE See companion file: ../secrets/\$TERRAFORM_BACKENDFILE
terraform {
    backend "gcs" {
    }
}
EOF
[ -f "terraform_remote_backend.tf" ] && echo -e "$SCRIPTNAME ${YELLOW}INFO File \"terraform_remote_backend.tf\" has been created into \"$(pwd)\"${NOCOLOR}"

echo "$SCRIPTNAME Creating starter \"variables.tf\" file"
cat << EOF > variables.tf
variable "global_params" {
    type = map
}
EOF
[ -f "variables.tf" ] && echo -e "$SCRIPTNAME ${YELLOW}INFO File \"variables.tf\" has been created into \"$(pwd)\"${NOCOLOR}"

echo "$SCRIPTNAME Creating starter \"tfvars/dev.tfvars\" file"
mkdir "tfvars"
cat << EOF > tfvars/dev.tfvars
global_params = {
    project_id          = "$PROJECT_ID"
    prefix              = "$PREFIX"
    default_region      = "$DEFAULT_REGION"
    default_multiregion = "$DEFAULT_MULTIREGION"

    gcp_credentials     = "$SERVICE_ACCOUNT_KEYFILE"
}
EOF
[ -f "tfvars/dev.tfvars" ] && echo -e "$SCRIPTNAME ${YELLOW}INFO File \"dev.tfvars\" has been created into \"$(pwd)/tfvars\"${NOCOLOR}"

echo "$SCRIPTNAME Creating \"providers.tf\" file"
cat << EOF > providers.tf
provider "google" {
    version     = "~> 3"  # See: https://www.terraform.io/docs/configuration/terraform.html#specifying-a-required-terraform-version

    credentials = file("../secrets/\${var.global_params["gcp_credentials"]}")

    project     = var.global_params["project_id"]
    region      = var.global_params["default_region"]
}
EOF
[ -f "providers.tf" ] && echo -e "$SCRIPTNAME ${YELLOW}INFO File \"providers.tf\" has been created into \"$(pwd)\"${NOCOLOR}"

## INIT TERRAFORM

echo "$SCRIPTNAME Running \"terraform init\" with proper params"
terraform init -backend-config="../secrets/$TERRAFORM_BACKENDFILE"
if [ $? -eq 0 ]; then
    echo -e "$SCRIPTNAME ${GREEN}Terraform bootstrap completed${NOCOLOR}"
else
    echo -e "$SCRIPTNAME ${RED}ERROR A problem incurred during Terraform bootstrap${NOCOLOR}"
fi
