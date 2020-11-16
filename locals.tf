// Additional regions can be added. Please contact support@controlshiftlabs.com
// if you are operating in a region other than these.
locals {
  lambda_buckets = {
    "us-east-1" = "changesprout-lambdas-us-east-1"
    "us-west-1" = "changesprout-lambdas-us-west-1"
  }
}
