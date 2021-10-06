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

#######################################
## F5 BIG-IP Advanced WAF HA Cluster ##
#######################################

##
## VPC
##

resource "aws_vpc" "f5BigIPVPC" {
  cidr_block = var.f5BigIPCIDR
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
    from_port = 80
    to_port = 80
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = [var.juiceShopAPICIDR,var.f5BigIPCIDR]
  }
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = [var.juiceShopAPICIDR,var.f5BigIPCIDR]
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
  tags = {
    Name = "${var.projectPrefix}-f5BigIPSubnetAZ1-MGMT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "f5BigIPSubnetAZ1-DATA" {
  vpc_id = aws_vpc.f5BigIPVPC.id
  cidr_block = var.f5BigIPSubnetAZ1-DATA
  availability_zone = local.awsAz1
  tags = {
    Name = "${var.projectPrefix}-f5BigIPSubnetAZ1-DATA-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "f5BigIPSubnetAZ2-MGMT" {
  vpc_id = aws_vpc.f5BigIPVPC.id
  cidr_block = var.f5BigIPSubnetAZ2-MGMT
  availability_zone = local.awsAz2
  tags = {
    Name = "${var.projectPrefix}-f5BigIPSubnetAZ2-MGMT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "f5BigIPSubnetAZ2-DATA" {
  vpc_id = aws_vpc.f5BigIPVPC.id
  cidr_block = var.f5BigIPSubnetAZ2-DATA
  availability_zone = local.awsAz2
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
    pool_member_1 = "${aws_network_interface.juiceShopAPIAZ1ENI.private_ip}"
    pool_member_2 = "${aws_network_interface.juiceShopAPIAZ2ENI.private_ip}"    
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
    pool_member_1 = "${aws_network_interface.juiceShopAPIAZ1ENI.private_ip}"
    pool_member_2 = "${aws_network_interface.juiceShopAPIAZ2ENI.private_ip}"    
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

####################################################################
########################## Juice Shop API ##########################
####################################################################

##
## VPC
##

resource "aws_vpc" "juiceShopAPIVPC" {
  cidr_block = var.juiceShopAPICIDR
  tags = {
    Name = "${var.projectPrefix}-juiceShopAPIVPC-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_security_group" "juiceShopAPISG" {
  vpc_id = aws_vpc.juiceShopAPIVPC.id
  tags = {
    Name = "${var.projectPrefix}-juiceShopAPISG-${random_id.buildSuffix.hex}"
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
    from_port = 80
    to_port = 80
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "juiceShopAPISubnetAZ1" {
  vpc_id = aws_vpc.juiceShopAPIVPC.id
  cidr_block = var.juiceShopAPISubnetAZ1
  availability_zone = local.awsAz1
  tags = {
    Name = "${var.projectPrefix}-juiceShopAPISubnetAZ1-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "juiceShopAPISubnetAZ2" {
  vpc_id = aws_vpc.juiceShopAPIVPC.id
  cidr_block = var.juiceShopAPISubnetAZ2
  availability_zone = local.awsAz2
  tags = {
    Name = "${var.projectPrefix}-juiceShopAPISubnetAZ2-${random_id.buildSuffix.hex}"
  }
}

resource "aws_internet_gateway" "juiceShopAPIIGW" {
  vpc_id = aws_vpc.juiceShopAPIVPC.id
  tags = {
    Name = "${var.projectPrefix}-juiceShopAPIIGW-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_route_table" "juiceShopAPIMainRT" {
  default_route_table_id = aws_vpc.juiceShopAPIVPC.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.juiceShopAPIIGW.id
  }
  tags = {
    Name = "${var.projectPrefix}-juiceShopAPIMainRT-${random_id.buildSuffix.hex}"
  }
}

##
## Juice Shop API AZ1
##

resource "aws_network_interface" "juiceShopAPIAZ1ENI" {
  subnet_id = aws_subnet.juiceShopAPISubnetAZ1.id
  tags = {
    Name = "juiceShopAPIAZ1ENI"
  }
}

resource "aws_eip" "juiceShopAPIAZ1EIP" {
  vpc = true
  network_interface = aws_network_interface.juiceShopAPIAZ1ENI.id
  associate_with_private_ip = aws_network_interface.juiceShopAPIAZ1ENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.juiceShopAPIIGW
  ]
  tags = {
    Name = "juiceShopAPIAZ1EIP"
  }
}

resource "aws_instance" "juiceShopAPIAZ1" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.juiceShopEC2InstanceType}"
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
    network_interface_id = aws_network_interface.juiceShopAPIAZ1ENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.juiceShopAPIAZ1EIP
  ]
  tags = {
    Name = "${var.projectPrefix}-juiceShopAPIAZ1-${random_id.buildSuffix.hex}"
  }
}

##
## Juice Shop API AZ2
##

resource "aws_network_interface" "juiceShopAPIAZ2ENI" {
  subnet_id = aws_subnet.juiceShopAPISubnetAZ2.id
  tags = {
    Name = "juiceShopAPIAZ2ENI"
  }
}

resource "aws_eip" "juiceShopAPIAZ2EIP" {
  vpc = true
  network_interface = aws_network_interface.juiceShopAPIAZ2ENI.id
  associate_with_private_ip = aws_network_interface.juiceShopAPIAZ2ENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.juiceShopAPIIGW
  ]
  tags = {
    Name = "juiceShopAPIAZ2EIP"
  }
}

resource "aws_instance" "juiceShopAPIAZ2" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.juiceShopEC2InstanceType}"
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
    network_interface_id = aws_network_interface.juiceShopAPIAZ2ENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.juiceShopAPIAZ2EIP
  ]
  tags = {
    Name = "${var.projectPrefix}-juiceShopAPIAZ2-${random_id.buildSuffix.hex}"
  }
}

##
## Network Load Balancing for API
##

resource "aws_lb" "juiceShopAPINLB" {
  name = "${var.projectPrefix}-juiceShopAPINLB-${random_id.buildSuffix.hex}"
  load_balancer_type = "network"
  internal = false
  subnet_mapping {
    subnet_id = aws_subnet.juiceShopAPISubnetAZ1.id
  }
  subnet_mapping {
    subnet_id = aws_subnet.juiceShopAPISubnetAZ2.id
  }
  enable_cross_zone_load_balancing = true
  tags = {
    Name = "${var.projectPrefix}-juiceShopAPINLB-${random_id.buildSuffix.hex}"
  }
}

resource "aws_lb_target_group" "juiceShopAPITG" {
  name = "${var.projectPrefix}-juiceShopAPITG-${random_id.buildSuffix.hex}"
  port = 80
  protocol = "TCP"
  vpc_id = aws_vpc.juiceShopAPIVPC.id
  health_check {
    enabled = true
    interval = 10
  }
  tags = {
    Name = "${var.projectPrefix}-juiceShopAPITG-${random_id.buildSuffix.hex}"
  }  
}

resource "aws_lb_listener" "juiceShopAPINLBListener" {
  load_balancer_arn = aws_lb.juiceShopAPINLB.arn
  port = "80"
  protocol = "TCP"
  default_action {
    target_group_arn = aws_lb_target_group.juiceShopAPITG.arn
    type = "forward"
  }
}

resource "aws_lb_target_group_attachment" "juiceShopAPIAZ1TGAttachment" {
  target_group_arn = aws_lb_target_group.juiceShopAPITG.arn
  target_id = aws_instance.juiceShopAPIAZ1.id
}

resource "aws_lb_target_group_attachment" "juiceShopAPIAZ2TGAttachment" {
  target_group_arn = aws_lb_target_group.juiceShopAPITG.arn
  target_id = aws_instance.juiceShopAPIAZ2.id
}

##
## AWS API Gateway
##

resource "aws_api_gateway_rest_api" "f5-awaf-aws-api-gateway" {
  name = "${var.projectPrefix}-apigw-${random_id.buildSuffix.hex}"
}

resource "aws_api_gateway_resource" "f5-awaf-aws-api-gateway-resource" {
  parent_id = aws_api_gateway_rest_api.f5-awaf-aws-api-gateway.root_resource_id
  path_part = "gateway-resource"
  rest_api_id = aws_api_gateway_rest_api.f5-awaf-aws-api-gateway.id
}

resource "aws_api_gateway_method" "f5-awaf-aws-api-gateway-method" {
  authorization = "NONE"
  http_method = "ANY"
  resource_id = aws_api_gateway_resource.f5-awaf-aws-api-gateway-resource.id
  rest_api_id = aws_api_gateway_rest_api.f5-awaf-aws-api-gateway.id
}

resource "aws_api_gateway_integration" "f5-awaf-aws-api-gateway-integration" {
  http_method = aws_api_gateway_method.f5-awaf-aws-api-gateway-method.http_method
  resource_id = aws_api_gateway_resource.f5-awaf-aws-api-gateway-resource.id
  rest_api_id = aws_api_gateway_rest_api.f5-awaf-aws-api-gateway.id
  type = "MOCK"
}

resource "aws_api_gateway_deployment" "f5-awaf-aws-api-gateway-deployment" {
  rest_api_id = aws_api_gateway_rest_api.f5-awaf-aws-api-gateway.id
  triggers = {
    "redeployment " = sha1(jsonencode([
      aws_api_gateway_resource.f5-awaf-aws-api-gateway-resource.id,
      aws_api_gateway_method.f5-awaf-aws-api-gateway-method.id,
      aws_api_gateway_integration.f5-awaf-aws-api-gateway-integration.id,
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "f5-awaf-aws-api-gateway-deployment" {
  deployment_id = aws_api_gateway_deployment.f5-awaf-aws-api-gateway-deployment.id
  rest_api_id = aws_api_gateway_rest_api.f5-awaf-aws-api-gateway.id
  stage_name = "apigw"
}

resource "aws_api_gateway_vpc_link" "f5toJuiceShopVPCLink" {
  name = "${var.projectPrefix}-vpclink-${random_id.buildSuffix.hex}"
  description = "stitches together the F5 and Juice Shop VPCs"
  target_arns = [aws_lb.juiceShopAPINLB.arn]
}
