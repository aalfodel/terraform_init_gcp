# README-terraform.md

## 0. Table of Contents

1. [Terraform bootstrap](#1.-terraform-bootstrap)
2. [Open an already Terraform bootstrapped GCP Project](#2.-open-an-already-terraform-bootstrapped-gcp-project)
3. [Add / modify Terraform managed resources (.tf files) to the GCP Project](#3.-add-/-modify-terraform-managed-resources-(.tf-files)-to-the-gcp-project)
4. [Switch from *dev* to *prod* environment](#4.-switch-from-*dev*-to-*prod*-environment)
5. [Useful Terraform commands](#5.-useful-terraform-commands)
6. [Terraform un-bootstrap](#6.-terraform-un-bootstrap)
7. [Official documentation](#7.-official-documentation)
8. [Other useful documentation](#8.-other-useful-documentation)

## 1. Terraform bootstrap

The following procedure will create the objects needed by Terraform to correctly work an a *GCP Project*, and should be executed only **once** per *GCP Project*.

Terraform will be bootstrapped on an **existing** *GCP Project* using the `terraform_bootstrap.sh` script attached to this repository. 


### Prerequisites

* The following commands must be installed on you machine
  * *gcloud*
  * *gsutil*
  * *terraform*

To install *gcloud* and *gsutil*, follow this guide: https://cloud.google.com/sdk/install

To install *terraform*, see: https://learn.hashicorp.com/tutorials/terraform/install-cli

 Note that the *terraform* binary must be into your `$PATH` directory; to do this you can use:

  `cp <binary_download_path>/terraform /usr/local/bin/`

* Your *gcloud* command must be authorized to GCP (that is, you must be logged-in through the cli)

For more info, see: https://cloud.google.com/sdk/docs/authorizing

* You must know the *GCP Project ID* of the project where you want to bootstrap Terraform

To get the *GCP Project ID*, see: https://cloud.google.com/resource-manager/docs/creating-managing-projects#identifying_projects

  * *roles/iam.securityAdmin* (Security Admin)
  * *roles/servicemanagement.admin* (Service Management Administrator)
  * *roles/storage.admin* (Storage Admin)

For more info, see: https://cloud.google.com/iam/docs/quickstart#grant_an_iam_role

* The script must have write permissions on the *terraform* directory of this repository and on its parent directory. For example, if you cloned the repository on path */home/foo/workdir*, the script must have write permissions on:
  * */home/foo/workdir/terraform*
  * */home/foo/workdir*

### Running the script

1. **The script must be run inside the *terraform* directory of this repository**

2. Execute:

    `./terraform_bootstrap.sh`

3. Follow the interactive prompt

4. If the script runs successfully, the following resources will be created:

* local resources:

    * file *terraform/../.gitignore*
    * directory *terraform/../secrets*
    * file *terraform/../secrets/README-secrets.md*
    * file *terraform/../secrets/\<project_id\>-terraform-key.json*
    * file *terraform/../secrets/\<project_id\>-terraform-backend.txt*
    * file *terraform/terraform_remote_backend.tf*
    * file *terraform/providers.tf*
    * file *terraform/variables.tf*
    * directory *terraform/tfvars*
    * file *terraform/tfvars/dev.tfvars*
    * directory *terraform/.terraform*
    * file *terraform/.terraform/terraform.tfstate*
    * directory *terraform/.terraform/plugins* and relative files

* remote resources:
    * service account *terraform@\<project-id\>.iam.gserviceaccount.com*
    * bucket *\<project-id\>-terraform-bucket*
    * secret *\<project-id\>-terraform-secret-backend*	
    * secret *\<project-id\>-terraform-secret-key*

5. Push the new local resources to the repository remote.

**NOTE** Files inside *terraform/../secrets* (except for *README-secrets.md*) **won't be managed by git. This is an inteded behaviour, for security reasons.** For future use, the missing files can be retireved from the two remote secrets.

### Fixing IAM errors

In the last step of the script (*Running "terraform init" with proper params*) errors like the following may appear:

> Error: Failed to get existing workspaces: querying Cloud Storage failed: googleapi: Error 403: terraform@\<project-id\>.iam.gserviceaccount.com does not have storage.objects.list access to the Google Cloud Storage bucket., forbidden

The root cause may be the existence of a previously deleted *terraform@\<project-id\>.iam.gserviceaccount.com* service account with missing IAM roles. This happens because granting IAM access to or revoking IAM access from resources is only eventually consistent.

**To fix this problem:**

1. follow: https://stackoverflow.com/questions/51410633/service-account-does-not-have-storage-objects-get-access-for-google-cloud-storage

2. then re-run the script

### Testing Terraform

To test that Terraform works correctly, you can try to deploy the example resource included in *terraform_testvm.tf*

1. **The script must be run inside the *terraform* directory of this repository**

2. Execute:

`terraform apply -var-file=./tfvars/dev.tfvars`

3. Check that the test vm has been created into the *GCP Project*:

`gcloud compute instances list --filter="NAME:<project_id>-terraform-testvm"`

---

> ### **NOTE**  All the following *terraform* commands must be executed while in the *terraform* directory

## 2. Open an already Terraform bootstrapped GCP Project

The following procedure will initialize/re-initialize an **already Terraform bootstrapped project**.

This procedure is a **necessary step** before adding / modifying new Terraform managed resources on your GCP Project.

1. **IMPORTANT Remove the "stateful" files: delete the directory *terraform/.terraform* and the content of *terraform/../secrets* (or do a fresh download/clone of the repo containing your Terraform project)**

2. Download and properly name the following files from *GCP Secret Manager*:
    * private key of the Service Account used by Terraform

      >file name: *\<project_id\>-terraform-key.json*
    * Terraform backend configuration
    
      >file name: *\<project_id\>-terraform-backend.txt*
   
   **NOTE To do this, you need the role:**
   
    * *roles/secretmanager.secretAccessor* (Secret Manager Secret Accessor)
   
   To download a secret and save it into a file, you can use the command:
   
   `gcloud secrets versions access latest --secret=<secret_name> --project=<project_id> > <file_name>`

3. Put the two files into the *terraform/../secrets* directory

4. **Run the command**:
   
   `terraform init -backend-config=../secrets/<backend_file_name>`
   
   **NOTE**
   
   You might get this kind of error:
   
    > Error: Failed to get existing workspaces: querying Cloud Storage failed: googleapi: Error 403: terraform@\<project-id\>.iam.gserviceaccount.com does not have storage.objects.list access to the Google Cloud Storage bucket., forbidden

    The root cause may be the existence of a previously deleted *terraform@\<project-id\>.iam.gserviceaccount.com* service account with missing IAM roles. This happens because granting IAM access to or revoking IAM access from resources is only eventually consistent.

    **To fix this problem**, follow: https://stackoverflow.com/questions/51410633/service-account-does-not-have-storage-objects-get-access-for-google-cloud-storage

5. **Check if the backend has been correctly loaded**:
    
    * Check if the loaded remote *.tfstate* is the correct one:

      `terraform show`

      The  shown resources should have the same parameters as your local *.tfvars* file.
    
    * As an additional check:
    
      `terraform plan -var-file=./tfvars/<tfvars_file>`

      The plan should notify that no changes are needed.

## 3. Add / modify Terraform managed resources (.tf files) to the GCP Project

0. **IMPORTANT** Before doing the next steps, **you must already have initialized Terraform** (see the paragraph: [Open an already Terraform bootstrapped GCP Project](#2.-open-an-already-terraform-bootstrapped-gcp-project))

1. Add / modify Terraform resources files (**`.tf` files**)

2. Validate the Terraform syntax of your *.tf* files with:

    `terraform validate`

3. Check the updated Terraform plan, **choosing the appropriate `.tfvars` file (for example, a *.tfvars* file for *dev* and a *.tfvars* file for *prod*)**

    `terraform plan -var-file=./tfvars/<tfvars_file>`

    Example:
   
   >*terraform plan -var-file=./tfvars/dev.tfvars*

4. Apply the updated Terraform plan, **choosing the appropriate `.tfvars` file (for example, a *.tfvars* file for *dev* and a *.tfvars* file for *prod*)**

    `terraform apply -var-file=./tfvars/<tfvars_file>`

    Example:
   
   >*terraform apply -var-file=./tfvars/dev.tfvars*

## 4. Switch from *dev* to *prod* environment

Let's suppose you have the GCP project *example**dev*** and that you want to clone it to your *example<ins>prod</ins>* GCP project.

0. Execute the Terraform bootstrap procedure on the **new** *example<ins>prod</ins>* GCP Project. 

    This time, you **must not push the new local resources to the repository remote**; you can also safetely delete all locally generated files, **except for the new** *terraform/tfvars/**dev**.tfvars*

     **IMPORTANT** Rename *terraform/tfvars/**dev**.tfvars* into *terraform/tfvars/<ins>prod</ins>.tfvars* and move it to *example**dev*** repo. Commit and push the changes of *example**dev*** repo.

    **NOTE** You can skip step 0 if *example<ins>prod</ins>* has already been Terraform bootstrapped and *terraform/tfvars/<ins>prod</ins>.tfvars* is already present in *example**dev*** repo

1. **IMPORTANT Remove the "stateful" files from** *example**dev*** **: delete the directory *terraform/.terraform* and the content of *terraform/../secrets* (or do a fresh download/clone of the** *example**dev*** **repo)**

2. From *example<ins>prod</ins>* GCP Secret Manager, download and properly name the following files to the local *example**dev*** repo:
    * private key of the Service Account used by Terraform

      >file name: *example<ins>prod</ins>-terraform-key.json*
    * Terraform backend configuration
    
      >file name: *example<ins>prod</ins>-terraform-backend.txt*
   
   **NOTE To do this, you need on *example<ins>prod</ins>* the role:**
   
    * *roles/secretmanager.secretAccessor* (Secret Manager Secret Accessor)
   
   To download a secret and save it into a file, you can use the command:
   
   `gcloud secrets versions access latest --secret=<secret_name> --project=exampleprod > <file_name>`

3. Put the two files into the *terraform/../secrets* directory of *example**dev***

4. **Run the command**:
   
   `terraform init -backend-config=../secrets/<prod_backend_file_name>`
     
    Example:

    >*terraform init -backend-config=../secrets/example<ins>prod</ins>-terraform-backend.txt*

   **NOTE**
   
   You might get this kind of error:
   
    > Error: Failed to get existing workspaces: querying Cloud Storage failed: googleapi: Error 403: terraform@\<project-id\>.iam.gserviceaccount.com does not have storage.objects.list access to the Google Cloud Storage bucket., forbidden

    The root cause may be the existence of a previously deleted *terraform@\<project-id\>.iam.gserviceaccount.com* service account with missing IAM roles. This happens because granting IAM access to or revoking IAM access from resources is only eventually consistent.

    **To fix this problem**, follow: https://stackoverflow.com/questions/51410633/service-account-does-not-have-storage-objects-get-access-for-google-cloud-storage

5. **Check if the backend has been correctly loaded, this time choosing the** <ins>prod</ins> **tfvars file**:

    `terraform plan -var-file=./tfvars/<prod_tfvars_file>`

    Example:

    >*terraform plan -var-file=./tfvars/<ins>prod</ins>.tfvars*

    The plan should notify that **all** the resources of ***dev*** are going to be replicated, **but with the different parameters declared** in *<ins>prod</ins>.tfvars*.

6. Apply the updated Terraform plan, **choosing the** <ins>prod</ins> **tfvars file**:

    `terraform apply -var-file=./tfvars/prod.tfvars`

    Example:
   
   >*terraform apply -var-file=./tfvars/<ins>prod</ins>.tfvars*

## 5. Useful Terraform commands 

* Debug Terraform commands:

  `TF_LOG=DEBUG terraform <command> ...`

  Example:

  >*TF_LOG=DEBUG terraform init -backend-config=../secrets/exampledev-terraform-backend.txt*

* Force re-creation of a single resource:

  `terraform taint <terraform_res_type>.<terraform_res_name>`

  `terraform apply -var-file=<tfvars_file>`

  Example:

  >*terraform taint google_compute_instance.testvm*

  >*terraform apply -var-file=./tfvars/dev.tfvars*


* Plan (or apply) only a single resource:

    `terraform plan(apply) -var-file=<tfvras_file> -target=<terraform_res_type>.<terraform_res_name>`

  Example:

  >*terraform apply -var-file=./tfvars/dev.tfvars -target=google_compute_instance.testvm*

* Destroy **all** resources:

    `terraform destroy -var-file=<tfvars_file>`

   **NOTE** *Some resources may have `prevent_destroy` in their configuration to prevent accidental deletion. You might need to comment such directives to destroy the resource*.

## 6. Terraform un-bootstrap

> ### **WARNING The following procedure will permanently delete the remotely preserved Terraform state**

In case you need to clean your GCP Project from the resources created by the Terraforn bootstapping, these are the objects you'll have to delete:

* the service account used by Terraform: 

  *terraform@\<project_id\>.iam.gserviceaccount.com*

* secrets containing 
    * the remote backend configuration file:

      *\<project_id\>-terraform-secret-backend*

    * the Terraform service account secret key:

      *\<project_id\>-terraform-secret-key*

* the bucket containing the remote Terraform state:

  *\<project_id\>-terraform-bucket*

## 7. Official documentation

* https://www.terraform.io/docs/index.html

* https://www.terraform.io/docs/providers/google/index.html

## 8. Other useful documentation

* https://www.thedevcoach.co.uk/terraform-best-practices/
* https://learn.hashicorp.com/tutorials/terraform/organize-configuration?in=terraform/modules
* https://learn.hashicorp.com/tutorials/terraform/state-import
* https://cloud.google.com/solutions/managing-infrastructure-as-code#configuring_terraform_to_store_state_in_a_cloud_storage_bucket
* https://terragrunt.gruntwork.io/