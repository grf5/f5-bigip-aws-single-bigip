output "ServerAZ1PrivateIP" {
  description = "the private IP address of the Juice Shop server in AZ1"
  value = aws_network_interface.ServerAZ1ENI.private_ip
}
output "ServerAZ2PrivateIP" {
  description = "the private IP address of the Juice Shop server in AZ2"
  value = aws_network_interface.ServerAZ2ENI.private_ip
}
output "ClientAZ1PrivateIP" {
  description = "the private IP address of the Ubuntu client in AZ1"
  value = aws_network_interface.ClientAZ1ENI.private_ip
}
output "ClientAZ2PrivateIP" {
  description = "the private IP address of the Ubuntu client in AZ1"
  value = aws_network_interface.ClientAZ2ENI.private_ip
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
  value =<<EOT

===========================================================
Cut and paste this block to enable SSH aliases (shortcuts):
===========================================================
  
alias client1='ssh ubuntu@${aws_eip.ClientAZ1EIP.public_ip} -p 22 -i "${local_file.newkey_pem.filename}"'
alias client2='ssh ubuntu@${aws_eip.ClientAZ2EIP.public_ip} -p 22 -i "${local_file.newkey_pem.filename}"'
alias server1='ssh ubuntu@${aws_eip.ServerAZ1EIP.public_ip} -p 22 -i "${local_file.newkey_pem.filename}"'
alias server2='ssh ubuntu@${aws_eip.ServerAZ2EIP.public_ip} -p 22 -i "${local_file.newkey_pem.filename}"'
alias bigip1='ssh admin@${aws_eip.F5_BIGIP_AZ1EIP_MGMT.public_ip} -p 22 -i "${local_file.newkey_pem.filename}"'
alias bigip2='ssh admin@${aws_eip.F5_BIGIP_AZ2EIP_MGMT.public_ip} -p 22 -i "${local_file.newkey_pem.filename}"'

EOT
}