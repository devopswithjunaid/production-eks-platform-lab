locals {
  name_prefix = "${var.name}-${var.environment}"
  nat_count   = var.single_nat_gateway ? 1 : length(var.availability_zones)

  common_tags = merge(
    {
      Project     = var.name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# ─── 1. VPC ───────────────────────────────────────────────────────────────────

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpc"
    }
  )
}

# ─── 2. Internet Gateway ──────────────────────────────────────────────────────

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-igw"
    }
  )
}

# ─── 3. Public Subnets (ALB & NAT Gateway) ────────────────────────────────────

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name                                        = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
      Tier                                        = "public"
      "kubernetes.io/role/elb"                    = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
  )
}

# ─── 4. Private EKS Subnets (Worker Nodes & Pods) ─────────────────────────────

resource "aws_subnet" "private_eks" {
  count = length(var.private_eks_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_eks_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    local.common_tags,
    {
      Name                                        = "${local.name_prefix}-private-eks-${var.availability_zones[count.index]}"
      Tier                                        = "private-eks"
      "kubernetes.io/role/internal-elb"           = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
  )
}

# ─── 5. Private Data Subnets (RDS & ElastiCache) ──────────────────────────────

resource "aws_subnet" "private_data" {
  count = length(var.private_data_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_data_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-data-${var.availability_zones[count.index]}"
      Tier = "private-data"
    }
  )
}

# ─── 6. Elastic IP(s) for NAT Gateway(s) ──────────────────────────────────────

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-eip-${var.availability_zones[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

# ─── 7. NAT Gateway(s) ────────────────────────────────────────────────────────

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-${var.availability_zones[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

# ─── 8. Public Route Table & Associations ─────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public-rt"
    }
  )
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ─── 9. Private EKS Route Table(s) & Associations ─────────────────────────────

resource "aws_route_table" "private_eks" {
  count  = local.nat_count
  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = var.single_nat_gateway ? "${local.name_prefix}-private-eks-rt" : "${local.name_prefix}-private-eks-rt-${var.availability_zones[count.index]}"
    }
  )
}

resource "aws_route" "private_eks_nat_gateway" {
  count = local.nat_count

  route_table_id         = aws_route_table.private_eks[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private_eks" {
  count = length(aws_subnet.private_eks)

  subnet_id      = aws_subnet.private_eks[count.index].id
  route_table_id = aws_route_table.private_eks[var.single_nat_gateway ? 0 : count.index].id
}

# ─── 10. Private Data Route Table & Associations (Isolated) ───────────────────

resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-data-rt"
    }
  )
}

resource "aws_route_table_association" "private_data" {
  count = length(aws_subnet.private_data)

  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private_data.id
}
