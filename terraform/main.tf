terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"  # Ensure compatibility with Terraform version
    }
  }
  required_version = ">= 1.5.0"  # Use the latest stable Terraform version
}

locals {
  # Define all variables in the locals block
  aws_region           = "us-east-1"
  cluster_name         = "my-eks-cluster"
  ecr_repository_name  = "my-spring-boot-app"
  vpc_name             = "my-vpc"
  cidr_block           = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  instance_type        = "t2.small"
  node_desired_size    = 1
  node_max_size        = 2
  node_min_size        = 1
  environment          = "dev"
  enable_nat_gateway   = false
  single_nat_gateway   = false
  enable_vpn_gateway   = false
  encryption_type      = "AES256"
  image_tag_mutability = "IMMUTABLE"
  
  tags = {
    Environment = local.environment
    Terraform   = "true"
  }

  /*
  # IAM Policies for the EKS Cluster
  eks_iam_policies = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]*/
}

provider "aws" {
  region = local.aws_region
}

resource "aws_ecr_repository" "my_ecr_repository" {
  name                 = local.ecr_repository_name
  image_tag_mutability = local.image_tag_mutability
  encryption_configuration {
    encryption_type = local.encryption_type
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = local.tags
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"  # Ensure to use a version that aligns with your Terraform version

  name          = local.vpc_name
  cidr          = local.cidr_block
  azs           = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway = local.enable_nat_gateway
  single_nat_gateway = local.single_nat_gateway  
  enable_vpn_gateway = local.enable_vpn_gateway

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"  # Use latest version of the EKS module

  cluster_name 		= local.cluster_name
  cluster_version 	= "1.31"
  
  # EKS Addons
  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }
  
  vpc_id        = module.vpc.vpc_id
  subnet_ids 	= module.vpc.private_subnets
  
  tags = {
    Terraform   = "true"
    Environment = local.environment
  }

  eks_managed_node_groups = {
    one = {
      instance_type= local.instance_type
      max_size     = local.node_max_size
      min_size     = local.node_min_size
      desired_size = local.node_desired_size	  

    }
  }
  
  #tags = local.tags
  /*
  # Configure IAM role for the EKS Cluster (optional best practice)
  cluster_iam_role_additional_policies = local.eks_iam_policies*/
}

output "ecr_repository_url" {
  value = aws_ecr_repository.my_ecr_repository.repository_url
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_arn" {
  value = module.eks.cluster_arn
}
