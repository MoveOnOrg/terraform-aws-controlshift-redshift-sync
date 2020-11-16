data "aws_redshift_cluster" "sync_data_target" {
  cluster_identifier = "${var.redshift_cluster_identifier}"
}
