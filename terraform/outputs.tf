output "JuiceShopNLBAPIURL" {
  description = "URL to front-end of Juice Shop API URL (NLB)"
  value = format("http://%s",aws_lb.juiceShopAPINLB.dns_name)
}
output "JuiceShopAPIAZ1URL" {
  description = "URL to front-end of Juice Shop API in AZ1"
  value = format("http://%s",aws_eip.juiceShopAPIAZ1EIP.public_ip)
}
output "JuiceShopAPIAZ2URL" {
  description = "URL to front-end of Juice Shop API in AZ2"
  value = format("http://%s",aws_eip.juiceShopAPIAZ2EIP.public_ip)
}
output "JuiceShopAPIAZ1PrivateIP" {
  description = "the private IP address of the Juice Shop API server in AZ1"
  value = aws_network_interface.juiceShopAPIAZ1ENI.private_ip
}
output "JuiceShopAPIAZ2PrivateIP" {
  description = "the private IP address of the Juice Shop API server in AZ1"
  value = aws_network_interface.juiceShopAPIAZ2ENI.private_ip
}
output "BIG-IP_AZ1_Mgmt_URL" {
  description = "URL for managing the BIG-IP in AZ1"
  value = format("https://%s/",aws_eip.F5_BIGIP_AZ1EIP_MGMT.public_ip)
}
output "BIG-IP_AZ2_Mgmt_URL" {
  description = "URL for managing the BIG-IP in AZ2"
  value = format("https://%s/",aws_eip.F5_BIGIP_AZ2EIP_MGMT.public_ip)
}
output "SSH_Bash_aliases" {
  description = "cut/paste block to create ssh aliases"
  value = "\nCut and paste this block to enable SSH aliases (shortcuts):\n\nalias juiceshop1='ssh ubuntu@${aws_eip.juiceShopAPIAZ1EIP.public_ip} -p 22 -i /${local_file.newkey_pem.filename}'\nalias juiceshop2='ssh ubuntu@${aws_eip.juiceShopAPIAZ2EIP.public_ip} -p 22 -i ${local_file.newkey_pem.filename}'\nalias bigip1='ssh admin@${aws_eip.F5_BIGIP_AZ1EIP_MGMT.public_ip} -p 22 -i ${local_file.newkey_pem.filename}'\nalias bigip2='ssh admin@${aws_eip.F5_BIGIP_AZ2EIP_MGMT.public_ip} -p 22 -i ${local_file.newkey_pem.filename}'\n"
}