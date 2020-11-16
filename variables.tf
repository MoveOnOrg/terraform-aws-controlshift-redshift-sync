variable "aws_region" {
  default     = "us-east-1"
  type        = string
  description = "The AWS Region to use. Should match the location of your Redshift instance"
}

variable "controlshift_aws_region" {
  default     = "us-east-1"
  type        = string
  description = "The AWS Region your ControlShift platform instance lives in. Consult controlshift support if you're not sure."
}

variable "redshift_cluster_identifier" {
  type = string
  description = "Your target Redshift cluster ID"
}

variable "redshift_database_name" {
  type = string
}

variable "redshift_username" {
  type = string
}

variable "redshift_password" {
  type = string
}

variable "redshift_schema" {
  type  = string
  default = "public"
  description = "The Redshift schema to load tables into"
}
variable "manifest_bucket_name" {
  type        = string
  description = "Your S3 bucket name to store manifests of ingests processed in. Will be placed in the controlshift_aws_region AWS region"
}
variable "glue_scripts_bucket_name" {
  type        = string
  description = "Your S3 bucket name to store Glue scripts in"
}
variable "manifest_prefix" {
  default = "manifests"
  type        = string
  description = "A file prefix that will be used for manifest logs on success"
}
variable "failed_manifest_prefix" {
  default = "failed"
  type        = string
  description = "A file prefix that will be used for manifest logs on failure"
}
variable "success_topic_name" {
  default = "ControlshiftLambdaLoaderSuccess"
  type        = string
  description = "An SNS topic name that will be notified about batch processing successes"
}
variable "failure_topic_name" {
  default = "ControlshiftLambdaLoaderFailure"
  type        = string
  description = "An SNS topic name that will be notified about batch processing failures"
}
variable "success_topic_name_for_run_glue_job_lambda" {
  default = "ControlshiftGlueJobSuccess"
  type        = string
  description = "An SNS topic name that will be notified about batch processing successes"
}
variable "failure_topic_name_for_run_glue_job_lambda" {
  default = "ControlshiftGlueJobFailure"
  type        = string
  description = "An SNS topic name that will be notified about batch processing failures"
}

variable "controlshift_hostname" {
  default = "staging.controlshiftlabs.com"
  type        = string
  description = "The hostname of your ControlShift instance. Likely to be something like action.myorganization.org"
}

variable "receiver_timeout" {
  default = 60
  type        = number
  description = "The timeout for the receiving Lambda, in seconds"
}

variable "controlshift_environment" {
  default = "production"
  type        = string
  description = "The environment of your ControlShift instance. Either staging or production"
}

variable "controlshift_organization_slug" {
  type = string
  description = "The organization's slug in ControlShift platform. Ask support team (support@controlshiftlabs.com) to find this value."
}

variable "lambda_loader_subnet_ids" {
  type = list(string)
  description = "List of subnet IDs where AWS Lambda may be run. Add more than one for Multi AZ reliability"
  default = []
}

variable "lambda_loader_security_group_ids" {
  type = list(string)
  description = "List of AWS security groups IDs that should be assigned to the lambda that loads tables into Redshift"
  default = []
}

variable "glue_physical_connection_requirements" {
  type = object({ availability_zone=string, subnet_id=string, security_group_id_list=list(string) })
  description = "A terraform map of the physical_connection_requirements property of the glue redshift connection. See Terraform aws_glue_connection docs."
  default = null
}
