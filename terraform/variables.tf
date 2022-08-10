resource "random_id" "buildSuffix" {
  byte_length = 2
}
variable "projectPrefix" {
  description = "projectPrefix name for tagging"
  default     = "1-bigip"
}
variable "resourceOwner" {
  description = "Owner of the deployment for tagging purposes"
  default     = "G-Rob"
}
variable "awsRegion" {
  description = "aws region"
  type        = string
  default     = "us-east-2"
}
variable "awsAz" {
  description = "Availability zone, will dynamically choose one if left empty"
  type        = string
  default     = null
}
variable "bigipAdminPassword" {
  description = "BIG-IP Admin Password (set on first boot)"
  default = "f5c0nfig123!"
  type = string
  sensitive = true
}
variable "labDomain" {
  description = "domain name for lab hostnames"
  default = "mylab.local"
  type = string

}
variable "bigipLicense" {
  description = "BIG-IP License for AZ1 instance"
  type = string
  default = "PAYG"
}
variable "ServerSubnetCIDR" {
  description = "CIDR block for entire Juice Shop API VPC"
  default = "10.30.0.0/16"
  type = string
}
variable "ServerSubnet" {
  description = "Subnet for Juice Shop API"
  default = "10.30.100.0/24"
  type = string
}
variable "ServerMgmtSubnet" {
  description = "Subnet for BIG-IP Mgmt"
  default = "10.30.1.0/24"
  type = string
}
variable "ServerEC2InstanceType" {
  description = "EC2 instance type for Juice Shop servers"
  default = "m5.xlarge"
}
variable get_address_url {
  type = string
  default = "https://api.ipify.org"
  description = "URL for getting external IP address"
}
variable get_address_url_ipv6 {
  type = string
  default = "https://api6.ipify.org"
  description = "URL for getting external IP address"
}
variable get_address_request_headers {
  type = map
  default = {
    Accept = "text/plain"
  }
  description = "HTTP headers to send"
}
variable "bigipLicenseType" {
  type = string
  description = "license type BYOL or PAYG"
  default = "PAYG"
}
variable "bigip_ami_mapping" {
  description = "mapping AMIs for PAYG and BYOL"
  default = {
    "BYOL" = "BYOL-All Modules 2Boot Loc"
    "PAYG" = "PAYG-Best 10Gbps"
  }
}
variable "bigip_ec2_instance_type" {
  description = "instance type for the BIG-IP instances"
  default = "c5.xlarge"
}
variable "bigip_version" {
  type = string
  description = "the base TMOS version to use - most recent version will be used"
  default =  "16.1.3.1"
}
variable "f5_do_version" {
  type = string
  description = "f5 declarative onboarding version (see https://github.com/F5Networks/f5-declarative-onboarding/releases/latest)"
  default = "1.27.0"
}
variable "f5_do_schema_version" {
  type = string
  description = "f5 declarative onboarding version (see https://github.com/F5Networks/f5-declarative-onboarding/releases/latest)"
  default = "1.27.0"
}
variable "f5_as3_version" {
  type = string
  description = "f5 application services version (see https://github.com/F5Networks/f5-appsvcs-extension/releases/latest)"
  default = "3.36.0"
}
variable "f5_as3_schema_version" {
  type = string
  description = "f5 application services version (see https://github.com/F5Networks/f5-appsvcs-extension/releases/latest)"
  default = "3.36.0"
}
variable "f5_ts_version" {
  type = string
  description = "f5 telemetry streaming version (see https://github.com/F5Networks/f5-declarative-onboarding/releases/latest)"
  default = "1.27.0"
}
variable "f5_ts_schema_version" {
  type = string
  description = "f5 telemetry streaming version (see https://github.com/F5Networks/f5-declarative-onboarding/releases/latest)"
  default = "1.27.0"
}