
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = ">= 3.61"
    http = ">= 2.1.0"
    bigip = {
      source = "terraform-providers/bigip"
    }
  }
}