locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Cluster     = var.cluster_name
    },
    var.tags
  )
}

# ─── 1. EKS Cluster IAM Role ──────────────────────────────────────────────────

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "vpc_resource_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# ─── 2. Cluster & Worker Node Security Groups ─────────────────────────────────

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS control plane ENIs (${var.cluster_name})"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })
}

resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node-sg"
  description = "Security group for EKS managed worker nodes (${var.cluster_name})"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name                                        = "${var.cluster_name}-node-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# Nodes -> Control Plane HTTPS API (443)
resource "aws_security_group_rule" "cluster_ingress_nodes_https" {
  description              = "Allow worker nodes to communicate with EKS API Server on 443"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

# Control Plane -> Nodes (kubelet & webhooks)
resource "aws_security_group_rule" "cluster_egress_nodes" {
  description              = "Allow control plane to connect to worker node kubelets and webhooks"
  type                     = "egress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

# Node-to-Node internal cluster communication (Pods, CoreDNS, Services)
resource "aws_security_group_rule" "node_ingress_self" {
  description       = "Allow all traffic between worker nodes within the cluster"
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.node.id
}

# Control Plane -> Nodes inbound (kubelet 10250, webhooks 443, ephemeral ports)
resource "aws_security_group_rule" "node_ingress_cluster" {
  description              = "Allow worker nodes to receive control plane requests"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

# Nodes outbound internet/VPC egress (via NAT Gateway for image pulls & AWS APIs)
resource "aws_security_group_rule" "node_egress_all" {
  description       = "Allow worker nodes outbound egress to VPC and NAT Gateway"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node.id
}

# ─── 3. Control Plane CloudWatch Log Group ────────────────────────────────────

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Name = "/aws/eks/${var.cluster_name}/cluster"
  })
}

# ─── 4. Amazon EKS Cluster (Control Plane) ────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name                      = var.cluster_name
  version                   = var.cluster_version
  role_arn                  = aws_iam_role.cluster.arn
  enabled_cluster_log_types = var.enabled_cluster_log_types

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = var.service_ipv4_cidr
  }

  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  tags = merge(local.common_tags, {
    Name = var.cluster_name
  })

  depends_on = [
    aws_cloudwatch_log_group.eks,
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.vpc_resource_controller
  ]
}

# ─── 5. Worker Node IAM Role (Minimal Node-Level Permissions) ─────────────────

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ─── 6. Managed Node Groups (System, Application, Monitoring) ─────────────────

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-${each.key}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  disk_size      = each.value.disk_size

  scaling_config {
    min_size     = each.value.min_size
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-${each.key}-ng"
    NodeGroup = each.key
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_readonly
  ]
}

# ─── 7. EKS Access Entries (PlatformAdmin, Developer, ReadOnly) ───────────────

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-access-${each.key}"
    Role = each.key
  })
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.key].principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope_type
    namespaces = each.value.access_scope_type == "namespace" ? each.value.namespaces : []
  }
}

# ─── 8. EKS Pod Identity Foundation & EBS CSI Driver Role ─────────────────────

data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-pod-identity-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ebs-csi-pod-identity-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ebs-csi-pod-identity"
  })
}

# ─── 9. Foundational AWS-Managed EKS Addons ───────────────────────────────────

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags

  depends_on = [
    aws_eks_node_group.this,
    aws_eks_pod_identity_association.ebs_csi,
    aws_eks_addon.pod_identity_agent
  ]
}
