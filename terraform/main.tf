
# Filter out local zones, which are not currently supported 
# with managed node groups
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# locals.tf

locals {
  # General Configuration
  project_name  = "demo"
  environment   = "dev"
  region        = "us-east-1"
  app_name      = "payroll"

  # VPC and Cluster Names
  vpc_name      = "${local.project_name}-vpc"
  cluster_name  = "${local.project_name}-eks-cluster" 

  # GitHub Repo and Other Resources
  github_repo   = "github.com/demo/repo"

  # Subnets Configuration
  cidr          = "10.0.0.0/16"
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  # EKS Cluster Settings
  cluster_version                = "1.31"
  cluster_endpoint_public_access = true
  enable_cluster_creator_admin_permissions = true

  # NAT Gateway Settings
  enable_nat_gateway             = true
  single_nat_gateway             = true
  enable_dns_hostnames           = true

  # Node Group Configuration
  instance_type                  = "t3.small"
  min_size                       = 1
  max_size                       = 2
  desired_size                   = 1

  # AMI Type for EKS Node Group
  ami_type                       = var.ami_type  # Referencing the variable

  # Tags
  tags = {
    Project      = local.project_name
    Environment  = local.environment
    Application  = local.app_name
    GithubRepo   = local.github_repo
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.vpc_name

  cidr = local.cidr
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway   = local.enable_nat_gateway
  single_nat_gateway   = local.single_nat_gateway
  enable_dns_hostnames = local.enable_dns_hostnames

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version

  cluster_endpoint_public_access           = local.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = local.enable_cluster_creator_admin_permissions

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type = local.ami_type  # Using the local reference of the ami_type
  }

  eks_managed_node_groups = {
    two = {
      name = "node-group-2"

      instance_types = [local.instance_type]

      min_size     = local.min_size
      max_size     = local.max_size
      desired_size = local.desired_size
    }
  }
}

# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}