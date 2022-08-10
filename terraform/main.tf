##
## General Environment Setup
##

provider "aws" {
  region = var.awsRegion
  default_tags {
    tags = {
      Owner = "${var.resourceOwner}"
    }
  }
}
data "aws_availability_zones" "available" {
  state = "available"
}
resource "tls_private_key" "newkey" {
  algorithm = "RSA"
  rsa_bits = 4096
}
resource "local_sensitive_file" "newkey_pem" { 
  # create a new local ssh identity
  filename = "${abspath(path.root)}/.ssh/${var.projectPrefix}-key-${random_id.buildSuffix.hex}.pem"
  content = tls_private_key.newkey.private_key_pem
  file_permission = "0400"
}
resource "aws_key_pair" "deployer" {
  # create a new AWS ssh identity
  key_name = "${var.projectPrefix}-key-${random_id.buildSuffix.hex}"
  public_key = tls_private_key.newkey.public_key_openssh
}
data "http" "ip_address" {
  # retrieve the local public IP address
  url = var.get_address_url
  request_headers = var.get_address_request_headers
}
data "http" "ipv6_address" {
  # trieve the local public IPv6 address
  url = var.get_address_url_ipv6
  request_headers = var.get_address_request_headers
}

data "aws_caller_identity" "current" {
  # Get the current AWS caller identity
}

##
## Locals
##

locals {
  awsAz = var.awsAz != null ? var.awsAz : data.aws_availability_zones.available.names[0]
}

##
## Juice Shop VM AMI - Ubuntu
##

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

##
## BIG-IP AMI - F5
##

data "aws_ami" "F5BIG-IP_AMI" {
  most_recent = true
  name_regex = ".*${lookup(var.bigip_ami_mapping, var.bigipLicenseType)}.*"

  filter {
    name = "name"
    values = ["F5 BIGIP-${var.bigip_version}*"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["679593333241"]
}

## 
## BIG-IP AMI/Onboarding Config
##

##
##  F5 BIG-IP Primary
##

resource "aws_network_interface" "F5_BIGIP_ENI_DATA" {
  source_dest_check = false
  subnet_id = aws_subnet.ServerSubnet.id
  tags = {
    Name = "F5_BIGIP_ENI_DATA"
    f5_cloud_failover_label = "f5_cloud_failover-${random_id.buildSuffix.hex}"
    f5_cloud_failover_nic_map = "data"
  }
}

resource "aws_network_interface" "F5_BIGIP_ENI_MGMT" {
  subnet_id = aws_subnet.ServerMgmtSubnet.id
  # Disable IPV6 dual stack management because it breaks DO clustering
  ipv6_address_count = 0
  tags = {
    Name = "F5_BIGIP_ENI_MGMT"
  }
}

resource "aws_eip" "F5_BIGIP_EIP_MGMT" {
  vpc = true
  network_interface = aws_network_interface.F5_BIGIP_ENI_MGMT.id
  associate_with_private_ip = aws_network_interface.F5_BIGIP_ENI_MGMT.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ServerIGW
  ]
  tags = {
    Name = "F5_BIGIP_EIP_MGMT"
  }
}

resource "aws_eip" "F5_BIGIP_EIP_DATA" {
  vpc = true
  network_interface = aws_network_interface.F5_BIGIP_ENI_DATA.id
  associate_with_private_ip = aws_network_interface.F5_BIGIP_ENI_DATA.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ServerIGW
  ]
  tags = {
    Name = "F5_BIGIP_EIP_DATA"
  }
}

resource "aws_instance" "BIG-IP" {
  ami = data.aws_ami.F5BIG-IP_AMI.id
  instance_type = "${var.bigip_ec2_instance_type}"
  availability_zone = local.awsAz
  key_name = aws_key_pair.deployer.id
	user_data = templatefile("${path.module}/bigip_runtime_init_user_data.tpl",
    {
      bigipAdminPassword = "${var.bigipAdminPassword}",
      bigipLicenseType = "${var.bigipLicenseType == "BYOL" ? "BYOL" : "PAYG"}",
      bigipLicense = "${var.bigipLicense}",
      f5_do_version = "${var.f5_do_version}",
      f5_do_schema_version = "${var.f5_do_schema_version}",
      f5_as3_version = "${var.f5_as3_version}",
      f5_as3_schema_version = "${var.f5_as3_schema_version}",
      f5_ts_version = "${var.f5_ts_version}",
      f5_ts_schema_version = "${var.f5_ts_schema_version}",
      service_address = "${aws_network_interface.F5_BIGIP_ENI_DATA.private_ip}",
      server_subnet_cidr_ipv4 = "${aws_subnet.ServerSubnet.cidr_block}",
    }
  )
  network_interface {
    network_interface_id = aws_network_interface.F5_BIGIP_ENI_MGMT.id
    device_index = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.F5_BIGIP_ENI_DATA.id
    device_index = 1
  }
  # Let's ensure an EIP is provisioned so licensing and bigip-runtime-init runs successfully
  depends_on = [
    aws_eip.F5_BIGIP_EIP_MGMT
  ]
  tags = {
    Name = "${var.projectPrefix}-F5_BIGIP-${random_id.buildSuffix.hex}"
  }
}

############################################################
########################## Server ##########################
############################################################

##
## VPC
##

resource "aws_vpc" "ServerVPC" {
  cidr_block = var.ServerSubnetCIDR
  assign_generated_ipv6_cidr_block = "true"
  tags = {
    Name = "${var.projectPrefix}-ServerVPC-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_security_group" "ServerSG" {
  vpc_id = aws_vpc.ServerVPC.id
  tags = {
    Name = "${var.projectPrefix}-ServerSG-${random_id.buildSuffix.hex}"
  }
  ingress {
    protocol = -1
    self = true
    from_port = 0
    to_port = 0
  }
  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    ipv6_cidr_blocks = [format("%s/%s",data.http.ipv6_address.body,128)]
  }
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    ipv6_cidr_blocks = [format("%s/%s",data.http.ipv6_address.body,128)]
  }
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    ipv6_cidr_blocks = [format("%s/%s",data.http.ipv6_address.body,128)]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "ServerMgmtSubnet" {
  vpc_id = aws_vpc.ServerVPC.id
  cidr_block = var.ServerMgmtSubnet
  availability_zone = local.awsAz
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ServerVPC.ipv6_cidr_block, 8, 2)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.projectPrefix}-ServerMgmtSubnet-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "ServerSubnet" {
  vpc_id = aws_vpc.ServerVPC.id
  cidr_block = var.ServerSubnet
  availability_zone = local.awsAz
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ServerVPC.ipv6_cidr_block, 8, 22)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.projectPrefix}-ServerSubnet-${random_id.buildSuffix.hex}"
  }
}

resource "aws_internet_gateway" "ServerIGW" {
  vpc_id = aws_vpc.ServerVPC.id
  tags = {
    Name = "${var.projectPrefix}-ServerIGW-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_route_table" "ServerMainRT" {
  default_route_table_id = aws_vpc.ServerVPC.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ServerIGW.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.ServerIGW.id
  }
  tags = {
    Name = "${var.projectPrefix}-ServerMainRT-${random_id.buildSuffix.hex}"
  }
}

##
## Server Server 
##

resource "aws_network_interface" "ServerENI" {
  subnet_id = aws_subnet.ServerSubnet.id
  tags = {
    Name = "ServerENI"
  }
}

resource "aws_eip" "ServerEIP" {
  vpc = true
  network_interface = aws_network_interface.ServerENI.id
  associate_with_private_ip = aws_network_interface.ServerENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ServerIGW
  ]
  tags = {
    Name = "ServerEIP"
  }
}

resource "aws_instance" "Server" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.ServerEC2InstanceType}"
  availability_zone = local.awsAz
  key_name = aws_key_pair.deployer.id
	user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt -y upgrade
              sudo apt -y install apt-transport-https ca-certificates curl software-properties-common docker
              sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
              sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
              sudo apt update
              sudo apt-cache policy docker-ce
              sudo apt -y install docker-ce
              sudo usermod -aG docker ubuntu
              docker pull bkimminich/juice-shop
              docker run -d -p 80:3000 --restart unless-stopped bkimminich/juice-shop
              sudo reboot
              EOF    
  network_interface {
    network_interface_id = aws_network_interface.ServerENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.ServerEIP
  ]
  tags = {
    Name = "${var.projectPrefix}-Server-${random_id.buildSuffix.hex}"
  }
}

