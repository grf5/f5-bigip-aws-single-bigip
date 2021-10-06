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

provider "bigip" {
  alias = "primary"
  address = "${aws_network_interface.F5_BIGIP_AZ1ENI_MGMT.private_ip}"
  username = "admin"
  password = "${var.bigipAdminPassword}"
}

provider "bigip" {
  alias = "secondary"
  address = "${aws_network_interface.F5_BIGIP_AZ2ENI_MGMT.private_ip}"
  username = "admin"
  password = "${var.bigipAdminPassword}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "tls_private_key" "newkey" {
  algorithm = "RSA"
  rsa_bits = 4096
}

# create a new local ssh identity
resource "local_file" "newkey_pem" { 
  filename = "${abspath(path.root)}/.ssh/${var.projectPrefix}-key-${random_id.buildSuffix.hex}.pem"
  sensitive_content = tls_private_key.newkey.private_key_pem
  file_permission = "0400"
}

# create a new AWS ssh identity
resource "aws_key_pair" "deployer" {
  key_name = "${var.projectPrefix}-key-${random_id.buildSuffix.hex}"
  public_key = tls_private_key.newkey.public_key_openssh
}

# retrieve the local public IP address
data "http" "ip_address" {
  url = var.get_address_url
  request_headers = var.get_address_request_headers
}

data "http" "ipv6_address" {
  url = var.get_address_url_ipv6
  request_headers = var.get_address_request_headers
}

# Get the current AWS caller identity
data "aws_caller_identity" "current" {}

##
## Locals
##

locals {
  awsAz1 = var.awsAz1 != null ? var.awsAz1 : data.aws_availability_zones.available.names[0]
  awsAz2 = var.awsAz2 != null ? var.awsAz1 : data.aws_availability_zones.available.names[1]
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

data "aws_ami" "f5BigIP_AMI" {
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

##########################
## F5 BIG-IP HA Cluster ##
##########################

##
## VPC
##

resource "aws_vpc" "f5BigIPVPC" {
  cidr_block = var.f5BigIPCIDR
  assign_generated_ipv6_cidr_block = "true"
  tags = {
    Name = "${var.projectPrefix}-f5BigIPVPC-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_security_group" "f5BigIPSG" {
  vpc_id = aws_vpc.f5BigIPVPC.id
  tags = {
    Name = "${var.projectPrefix}-f5BigIPSG-${random_id.buildSuffix.hex}"
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
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = [var.ClientSubnetCIDR,var.f5BigIPCIDR]
  }
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = [var.ClientSubnetCIDR,var.f5BigIPCIDR]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "f5BigIPSubnetAZ1-MGMT" {
  vpc_id = aws_vpc.f5BigIPVPC.id
  cidr_block = var.f5BigIPSubnetAZ1-MGMT
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.f5BigIPVPC.ipv6_cidr_block, 8, 1)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.projectPrefix}-f5BigIPSubnetAZ1-MGMT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "f5BigIPSubnetAZ1-DATA" {
  vpc_id = aws_vpc.f5BigIPVPC.id
  cidr_block = var.f5BigIPSubnetAZ1-DATA
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.f5BigIPVPC.ipv6_cidr_block, 8, 3)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.projectPrefix}-f5BigIPSubnetAZ1-DATA-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "f5BigIPSubnetAZ2-MGMT" {
  vpc_id = aws_vpc.f5BigIPVPC.id
  cidr_block = var.f5BigIPSubnetAZ2-MGMT
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.f5BigIPVPC.ipv6_cidr_block, 8, 2)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.projectPrefix}-f5BigIPSubnetAZ2-MGMT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "f5BigIPSubnetAZ2-DATA" {
  vpc_id = aws_vpc.f5BigIPVPC.id
  cidr_block = var.f5BigIPSubnetAZ2-DATA
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.f5BigIPVPC.ipv6_cidr_block, 8, 4)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.projectPrefix}-f5BigIPSubnetAZ2-DATA-${random_id.buildSuffix.hex}"
  }
}

resource "aws_internet_gateway" "f5BigIPIGW" {
  vpc_id = aws_vpc.f5BigIPVPC.id
  tags = {
    Name = "${var.projectPrefix}-f5BigIPIGW-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_route_table" "f5BigIPMainRT" {
  default_route_table_id = aws_vpc.f5BigIPVPC.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.f5BigIPIGW.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.f5BigIPIGW.id
  }
  route {
    cidr_block = aws_subnet.ClientSubnetAZ1.cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ClientSubnetAZ1.ipv6_cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ClientSubnetAZ2.cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ClientSubnetAZ2.ipv6_cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ServerSubnetAZ1.cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ServerSubnetAZ1.ipv6_cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ServerSubnetAZ2.cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ServerSubnetAZ2.ipv6_cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  tags = {
    Name = "${var.projectPrefix}-f5BigIPMainRT-${random_id.buildSuffix.hex}"
  }
}

## 
## BIG-IP AMI/Onboarding Config
##

data "template_file" "bigip_runtime_init_AZ1" {
  template = "${file("${path.module}/bigip_runtime_init_user_data.tpl")}"
  vars = {
    bigipAdminPassword = "${var.bigipAdminPassword}"
    bigipLicenseType = "${var.bigipLicenseType == "BYOL" ? "BYOL" : "PAYG"}"
    bigipLicense = "${var.bigipLicenseAZ1}"
    f5_do_version = "${var.f5_do_version}"
    f5_do_schema_version = "${var.f5_do_schema_version}"
    f5_as3_version = "${var.f5_as3_version}"
    f5_as3_schema_version = "${var.f5_as3_schema_version}"
    f5_ts_version = "${var.f5_ts_version}"
    f5_ts_schema_version = "${var.f5_ts_schema_version}"
    service_address = "${aws_eip.F5_BIGIP_AZ1EIP_DATA.public_ip}"
    pool_member_1 = "${aws_network_interface.ClientAZ1ENI.private_ip}"
    pool_member_2 = "${aws_network_interface.ClientAZ2ENI.private_ip}"    
  }
}

data "template_file" "bigip_runtime_init_AZ2" {
  template = "${file("${path.module}/bigip_runtime_init_user_data.tpl")}"
  vars = {
    bigipAdminPassword = "${var.bigipAdminPassword}"
    bigipLicenseType = "${var.bigipLicenseType == "BYOL" ? "BYOL" : "PAYG"}"
    bigipLicense = "${var.bigipLicenseAZ2}"
    f5_do_version = "${var.f5_do_version}"
    f5_do_schema_version = "${var.f5_do_schema_version}"
    f5_as3_version = "${var.f5_as3_version}"
    f5_as3_schema_version = "${var.f5_as3_schema_version}"
    f5_ts_version = "${var.f5_ts_version}"
    f5_ts_schema_version = "${var.f5_ts_schema_version}"
    service_address = "${aws_eip.F5_BIGIP_AZ2EIP_DATA.public_ip}"    
    pool_member_1 = "${aws_network_interface.ClientAZ1ENI.private_ip}"
    pool_member_2 = "${aws_network_interface.ClientAZ2ENI.private_ip}"    
  }
}

##
## AZ1 F5 BIG-IP Instance
##

resource "aws_network_interface" "F5_BIGIP_AZ1ENI_DATA" {
  subnet_id = aws_subnet.f5BigIPSubnetAZ1-DATA.id
  tags = {
    Name = "F5_BIGIP_AZ1ENI_DATA"
  }
}

resource "aws_network_interface" "F5_BIGIP_AZ1ENI_MGMT" {
  subnet_id = aws_subnet.f5BigIPSubnetAZ1-MGMT.id
  tags = {
    Name = "F5_BIGIP_AZ1ENI_MGMT"
  }
}

resource "aws_eip" "F5_BIGIP_AZ1EIP_MGMT" {
  vpc = true
  network_interface = aws_network_interface.F5_BIGIP_AZ1ENI_MGMT.id
  associate_with_private_ip = aws_network_interface.F5_BIGIP_AZ1ENI_MGMT.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.f5BigIPIGW
  ]
  tags = {
    Name = "F5_BIGIP_AZ1EIP_MGMT"
  }
}

resource "aws_eip" "F5_BIGIP_AZ1EIP_DATA" {
  vpc = true
  network_interface = aws_network_interface.F5_BIGIP_AZ1ENI_DATA.id
  associate_with_private_ip = aws_network_interface.F5_BIGIP_AZ1ENI_DATA.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.f5BigIPIGW
  ]
  tags = {
    Name = "F5_BIGIP_AZ1EIP_DATA"
  }
}

resource "aws_instance" "F5_BIGIP_AZ1" {
  ami = data.aws_ami.f5BigIP_AMI.id
  instance_type = "${var.bigip_ec2_instance_type}"
  availability_zone = local.awsAz1
  key_name = aws_key_pair.deployer.id
	user_data = "${data.template_file.bigip_runtime_init_AZ1.rendered}"
  network_interface {
    network_interface_id = aws_network_interface.F5_BIGIP_AZ1ENI_MGMT.id
    device_index = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.F5_BIGIP_AZ1ENI_DATA.id
    device_index = 1
  }
  # Let's ensure an EIP is provisioned so licensing and bigip-runtime-init runs successfully
  depends_on = [
    aws_eip.F5_BIGIP_AZ1EIP_DATA
  ]
  tags = {
    Name = "${var.projectPrefix}-F5_BIGIP_AZ1-${random_id.buildSuffix.hex}"
  }
}

##
## AZ2 F5 BIG-IP Instance
##

resource "aws_network_interface" "F5_BIGIP_AZ2ENI_DATA" {
  subnet_id = aws_subnet.f5BigIPSubnetAZ2-DATA.id
  source_dest_check = false
  tags = {
    Name = "F5_BIGIP_AZ2ENI_DATA"
  }
}

resource "aws_network_interface" "F5_BIGIP_AZ2ENI_MGMT" {
  subnet_id = aws_subnet.f5BigIPSubnetAZ2-MGMT.id
  tags = {
    Name = "F5_BIGIP_AZ2ENI_MGMT"
  }
}

resource "aws_eip" "F5_BIGIP_AZ2EIP_MGMT" {
  vpc = true
  network_interface = aws_network_interface.F5_BIGIP_AZ2ENI_MGMT.id
  associate_with_private_ip = aws_network_interface.F5_BIGIP_AZ2ENI_MGMT.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.f5BigIPIGW
  ]
  tags = {
    Name = "F5_BIGIP_AZ2EIP_MGMT"
  }
}

resource "aws_eip" "F5_BIGIP_AZ2EIP_DATA" {
  vpc = true
  network_interface = aws_network_interface.F5_BIGIP_AZ2ENI_DATA.id
  associate_with_private_ip = aws_network_interface.F5_BIGIP_AZ2ENI_DATA.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.f5BigIPIGW
  ]
  tags = {
    Name = "F5_BIGIP_AZ2EIP_DATA"
  }
}

resource "aws_instance" "F5_BIGIP_AZ2" {
  ami = data.aws_ami.f5BigIP_AMI.id
  instance_type = "${var.bigip_ec2_instance_type}"
  availability_zone = local.awsAz2
  key_name = aws_key_pair.deployer.id
	user_data = "${data.template_file.bigip_runtime_init_AZ2.rendered}"
  network_interface {
    network_interface_id = aws_network_interface.F5_BIGIP_AZ2ENI_MGMT.id
    device_index = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.F5_BIGIP_AZ2ENI_DATA.id
    device_index = 1
  }
  # Let's ensure an EIP is provisioned so licensing and bigip-runtime-init runs successfully
  depends_on = [
    aws_eip.F5_BIGIP_AZ2EIP_DATA
  ]
  tags = {
    Name = "${var.projectPrefix}-F5_BIGIP_AZ2-${random_id.buildSuffix.hex}"
  }
}

############################################################
########################## Client ##########################
############################################################

##
## VPC
##

resource "aws_vpc" "ClientVPC" {
  cidr_block = var.ClientSubnetCIDR
  assign_generated_ipv6_cidr_block = "true"  
  tags = {
    Name = "${var.projectPrefix}-ClientVPC-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_security_group" "ClientSG" {
  vpc_id = aws_vpc.ClientVPC.id
  tags = {
    Name = "${var.projectPrefix}-ClientSG-${random_id.buildSuffix.hex}"
  }
  ingress {
    protocol = -1
    self = true
    from_port = 0
    to_port = 0
  }

  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = [aws_subnet.f5BigIPSubnetAZ1-DATA.cidr_block]
  }

ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = [aws_subnet.f5BigIPSubnetAZ2-DATA.cidr_block]
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
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "ClientSubnetAZ1" {
  vpc_id = aws_vpc.ClientVPC.id
  cidr_block = var.ClientSubnetAZ1
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ClientVPC.ipv6_cidr_block, 8, 1)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.projectPrefix}-ClientSubnetAZ1-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "ClientSubnetAZ2" {
  vpc_id = aws_vpc.ClientVPC.id
  cidr_block = var.ClientSubnetAZ2
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ClientVPC.ipv6_cidr_block, 8, 2)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.projectPrefix}-ClientSubnetAZ2-${random_id.buildSuffix.hex}"
  }
}

resource "aws_internet_gateway" "ClientIGW" {
  vpc_id = aws_vpc.ClientVPC.id
  tags = {
    Name = "${var.projectPrefix}-ClientIGW-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_route_table" "ClientMainRT" {
  default_route_table_id = aws_vpc.ClientVPC.default_route_table_id
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.ClientIGW.id
    }
  route {
      ipv6_cidr_block = "::/0"
      gateway_id = aws_internet_gateway.ClientIGW.id
    }
  route {
    cidr_block = aws_subnet.ServerSubnetAZ1.cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ServerSubnetAZ1.ipv6_cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ServerSubnetAZ2.cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ServerSubnetAZ2.ipv6_cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  tags = {
    Name = "${var.projectPrefix}-ClientMainRT-${random_id.buildSuffix.hex}"
  }
}

##
## Client Server AZ1
##

resource "aws_network_interface" "ClientAZ1ENI" {
  subnet_id = aws_subnet.ClientSubnetAZ1.id
  tags = {
    Name = "ClientAZ1ENI"
  }
}

resource "aws_eip" "ClientAZ1EIP" {
  vpc = true
  network_interface = aws_network_interface.ClientAZ1ENI.id
  associate_with_private_ip = aws_network_interface.ClientAZ1ENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ClientIGW
  ]
  tags = {
    Name = "ClientAZ1EIP"
  }
}

resource "aws_instance" "ClientAZ1" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.ClientEC2InstanceType}"
  availability_zone = local.awsAz1
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
    network_interface_id = aws_network_interface.ClientAZ1ENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.ClientAZ1EIP
  ]
  tags = {
    Name = "${var.projectPrefix}-ClientAZ1-${random_id.buildSuffix.hex}"
  }
}

##
## Client AZ2
##

resource "aws_network_interface" "ClientAZ2ENI" {
  subnet_id = aws_subnet.ClientSubnetAZ2.id
  tags = {
    Name = "ClientAZ2ENI"
  }
}

resource "aws_eip" "ClientAZ2EIP" {
  vpc = true
  network_interface = aws_network_interface.ClientAZ2ENI.id
  associate_with_private_ip = aws_network_interface.ClientAZ2ENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ClientIGW
  ]
  tags = {
    Name = "ClientAZ2EIP"
  }
}

resource "aws_instance" "ClientAZ2" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.ClientEC2InstanceType}"
  availability_zone = local.awsAz2
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
    network_interface_id = aws_network_interface.ClientAZ2ENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.ClientAZ2EIP
  ]
  tags = {
    Name = "${var.projectPrefix}-ClientAZ2-${random_id.buildSuffix.hex}"
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
    from_port = 80
    to_port = 80
    cidr_blocks = [aws_subnet.f5BigIPSubnetAZ1-DATA.cidr_block]
  }
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = [aws_subnet.f5BigIPSubnetAZ2-DATA.cidr_block]
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
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "ServerSubnetAZ1" {
  vpc_id = aws_vpc.ServerVPC.id
  cidr_block = var.ServerSubnetAZ1
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ServerVPC.ipv6_cidr_block, 8, 1)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.projectPrefix}-ServerSubnetAZ1-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "ServerSubnetAZ2" {
  vpc_id = aws_vpc.ServerVPC.id
  cidr_block = var.ServerSubnetAZ2
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ServerVPC.ipv6_cidr_block, 8, 2)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.projectPrefix}-ServerSubnetAZ2-${random_id.buildSuffix.hex}"
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
  route {
    cidr_block = aws_subnet.ClientSubnetAZ1.cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ClientSubnetAZ1.ipv6_cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ClientSubnetAZ2.cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ClientSubnetAZ2.ipv6_cidr_block
    gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  tags = {
    Name = "${var.projectPrefix}-ServerMainRT-${random_id.buildSuffix.hex}"
  }
}

##
## Server Server AZ1
##

resource "aws_network_interface" "ServerAZ1ENI" {
  subnet_id = aws_subnet.ServerSubnetAZ1.id
  tags = {
    Name = "ServerAZ1ENI"
  }
}

resource "aws_eip" "ServerAZ1EIP" {
  vpc = true
  network_interface = aws_network_interface.ServerAZ1ENI.id
  associate_with_private_ip = aws_network_interface.ServerAZ1ENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ServerIGW
  ]
  tags = {
    Name = "ServerAZ1EIP"
  }
}

resource "aws_instance" "ServerAZ1" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.ServerEC2InstanceType}"
  availability_zone = local.awsAz1
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
    network_interface_id = aws_network_interface.ServerAZ1ENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.ServerAZ1EIP
  ]
  tags = {
    Name = "${var.projectPrefix}-ServerAZ1-${random_id.buildSuffix.hex}"
  }
}

##
## Server AZ2
##

resource "aws_network_interface" "ServerAZ2ENI" {
  subnet_id = aws_subnet.ServerSubnetAZ2.id
  tags = {
    Name = "ServerAZ2ENI"
  }
}

resource "aws_eip" "ServerAZ2EIP" {
  vpc = true
  network_interface = aws_network_interface.ServerAZ2ENI.id
  associate_with_private_ip = aws_network_interface.ServerAZ2ENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ServerIGW
  ]
  tags = {
    Name = "ServerAZ2EIP"
  }
}

resource "aws_instance" "ServerAZ2" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.ServerEC2InstanceType}"
  availability_zone = local.awsAz2
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
    network_interface_id = aws_network_interface.ServerAZ2ENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.ServerAZ2EIP
  ]
  tags = {
    Name = "${var.projectPrefix}-ServerAZ2-${random_id.buildSuffix.hex}"
  }
}

##
## Transit Gateway
##

resource "aws_ec2_transit_gateway" "awsTransitGateway" {
  description = "Transit Gateway"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags = {
    Name = "${var.projectPrefix}-tgw-${random_id.buildSuffix.hex}"
  }
}

### TGW Attachments
resource "aws_ec2_transit_gateway_vpc_attachment" "clientTGWVPCAttachment" {
  vpc_id = aws_vpc.ClientVPC.id
  transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  subnet_ids = [aws_subnet.ClientSubnetAZ1.id,aws_subnet.ClientSubnetAZ2.id]
  transit_gateway_default_route_table_association = "false"
  transit_gateway_default_route_table_propagation = "false"
  ipv6_support = "enable"
  tags = {
    Name = "${var.projectPrefix}-client-tgwvpcattach-${random_id.buildSuffix.hex}"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "serverTGWVPCAttachment" {
  vpc_id = aws_vpc.ServerVPC.id
  transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  subnet_ids = [aws_subnet.ServerSubnetAZ1.id,aws_subnet.ServerSubnetAZ2.id]
  transit_gateway_default_route_table_association = "false"
  transit_gateway_default_route_table_propagation = "false"
  ipv6_support = "enable"
  tags = {
    Name = "${var.projectPrefix}-server-tgwvpcattach-${random_id.buildSuffix.hex}"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "securityTGWVPCAttachment" {
  vpc_id = aws_vpc.f5BigIPVPC.id
  transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  subnet_ids = [aws_subnet.f5BigIPSubnetAZ1-DATA.id,aws_subnet.f5BigIPSubnetAZ2-DATA.id]
  transit_gateway_default_route_table_association = "false"
  transit_gateway_default_route_table_propagation = "false"
  ipv6_support = "enable"
  tags = {
    Name = "${var.projectPrefix}-security-tgwvpcattach-${random_id.buildSuffix.hex}"
  }  
}

### Default Route Table
resource "aws_ec2_transit_gateway_route_table" "default-route-table" {
  transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  tags = {
    Name = "${var.projectPrefix}-default-RT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_ec2_transit_gateway_route_table_propagation" "clientTGWRTAnnouncement" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.clientTGWVPCAttachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.default-route-table.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "serverTGWRTAnnouncement" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.serverTGWVPCAttachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.default-route-table.id
}

### Client Inspection Route Table and Routes
resource "aws_ec2_transit_gateway_route_table" "clientInspection" {
  transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  tags = {
    Name = "${var.projectPrefix}-client-RT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_ec2_transit_gateway_route" "client-inspection" {
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.securityTGWVPCAttachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.clientInspection.id
}

resource "aws_ec2_transit_gateway_route" "client-inspection-v6" {
  destination_cidr_block = "::/0"
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.securityTGWVPCAttachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.clientInspection.id
}

### Server Inspection Route Table and Routes
resource "aws_ec2_transit_gateway_route_table" "serverInspection" {
  transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  tags = {
    Name = "${var.projectPrefix}-server-RT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_ec2_transit_gateway_route" "server-inspection" {
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.securityTGWVPCAttachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.serverInspection.id
}

resource "aws_ec2_transit_gateway_route" "server-inspection-v6" {
  destination_cidr_block = "::/0"
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.securityTGWVPCAttachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.serverInspection.id
}

### Route Table Associations

resource "aws_ec2_transit_gateway_route_table_association" "clientTGWRTAssociation" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.clientTGWVPCAttachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.clientInspection.id
}

resource "aws_ec2_transit_gateway_route_table_association" "serverTGWRTAssociation" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.serverTGWVPCAttachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.serverInspection.id
}

resource "aws_ec2_transit_gateway_route_table_association" "securityTGWRTAssociation" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.securityTGWVPCAttachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.default-route-table.id
}

##
## AS3 Declarations
## 

data "template_file" "bigip_as3_AZ1" {
  template = "${file("${path.module}/ip_forwarding_as3.json")}"
  vars = {
    destination_address = "${aws_network_interface.F5_BIGIP_AZ2ENI_MGMT.private_ip}"
    f5_as3_version = "${var.f5_as3_version}"
    f5_as3_schema_version = "${var.f5_as3_schema_version}"
  }
}

data "template_file" "bigip_as3_AZ2" {
  template = "${file("${path.module}/ip_forwarding_as3.json")}"
  vars = {
    destination_address = "${aws_network_interface.F5_BIGIP_AZ1ENI_MGMT.private_ip}"
    f5_as3_version = "${var.f5_as3_version}"
    f5_as3_schema_version = "${var.f5_as3_schema_version}"
  }
}

resource "bigip_as3" "primary_default-ip-forwarders" {
  as3_json = "${data.template_file.bigip_as3_AZ1.rendered}"
  provider = bigip.primary  
}

resource "bigip_as3" "secondary_default-ip-forwarders" {
  as3_json = "${data.template_file.bigip_as3_AZ2.rendered}"
  provider = bigip.secondary  
}