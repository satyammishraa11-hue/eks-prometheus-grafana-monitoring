variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "cluster_name" {
  type    = string
  default = "monitoring-eks-cluster"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "node_instance_type" {
  type    = string
  default = "c7i-flex.large"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "admin_cidr" {
  type        = string
  description = "Your current public IPv4 CIDR, e.g. 203.0.113.10/32. Do not use 0.0.0.0/0."
  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "Use a valid restricted IPv4 CIDR, not 0.0.0.0/0."
  }
}
