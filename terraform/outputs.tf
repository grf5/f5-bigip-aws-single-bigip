output "Server_Public_IP" {
  description = "the public IP address of the Juice Shop server"
  value = aws_eip.ServerEIP.public_ip
}
output "BIG-IP_Mgmt_URL" {
  description = "URL for managing the Primary BIG-IP in AZ1"
  value = format("https://%s/",aws_eip.F5_BIGIP_EIP_MGMT.public_ip)
}
output "BIG-IP_Virtual_Server_Public_IP" {
  description = "the public IP address of the virtual server on the BIG-IP"
  value = aws_eip.F5_BIGIP_EIP_DATA.public_ip
}
output "SSH_Bash_aliases" {
  description = "cut/paste block to create ssh aliases"
  value =<<EOT
# SSH Aliases
alias server='ssh ubuntu@${aws_eip.ServerEIP.public_ip} -p 22 -o StrictHostKeyChecking=off -i "${local_sensitive_file.newkey_pem.filename}"'
alias bigip='ssh admin@${aws_eip.F5_BIGIP_EIP_MGMT.public_ip} -p 22 -o StrictHostKeyChecking=off -i "${local_sensitive_file.newkey_pem.filename}"'
EOT
}