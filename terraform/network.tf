resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  for_each = local.azs

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.public
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = { Name = "${var.name}-public-${each.key}" }
}

resource "aws_subnet" "web" {
  for_each = local.azs

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.web
  availability_zone = each.value.az

  tags = { Name = "${var.name}-web-${each.key}" }
}

resource "aws_subnet" "app" {
  for_each = local.azs

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.app
  availability_zone = each.value.az

  tags = { Name = "${var.name}-app-${each.key}" }
}

resource "aws_subnet" "data" {
  for_each = local.azs

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.data
  availability_zone = each.value.az

  tags = { Name = "${var.name}-data-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-rt-public" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = local.azs

  domain = "vpc"
  tags   = { Name = "${var.name}-nat-eip-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = local.azs

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = { Name = "${var.name}-nat-${each.key}" }
}

resource "aws_route_table" "web" {
  for_each = local.azs

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[each.key].id
  }

  tags = { Name = "${var.name}-rt-web-${each.key}" }
}

resource "aws_route_table_association" "web" {
  for_each = aws_subnet.web

  subnet_id      = each.value.id
  route_table_id = aws_route_table.web[each.key].id
}

resource "aws_route_table" "app" {
  for_each = local.azs

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[each.key].id
  }

  tags = { Name = "${var.name}-rt-app-${each.key}" }
}

resource "aws_route_table_association" "app" {
  for_each = aws_subnet.app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

resource "aws_route_table" "data" {
  for_each = local.azs

  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-rt-data-${each.key}" }
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data[each.key].id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [for rt in aws_route_table.web : rt.id],
    [for rt in aws_route_table.app : rt.id],
  )

  tags = { Name = "${var.name}-s3-gw" }
}
