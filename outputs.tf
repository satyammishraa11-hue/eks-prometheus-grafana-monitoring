output "cluster_name" {
  value = aws_eks_cluster.lab.name
}

output "region" {
  value = var.aws_region
}

output "worker_subnet_ids" {
  value = local.subnet_ids
}

output "update_kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.lab.name}"
}
