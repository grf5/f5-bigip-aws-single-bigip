#!/bin/bash -x 

# Send output to log file and serial console
mkdir -p  /var/log/cloud /config/cloud /var/config/rest/downloads
LOG_FILE=/var/log/cloud/startup-script.log
[[ ! -f $LOG_FILE ]] && touch $LOG_FILE || { echo "Run Only Once. Exiting"; exit; }
npipe=/tmp/$$.tmp
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe -a $LOG_FILE /dev/ttyS0 &
exec 1>&-
exec 1>$npipe
exec 2>&1

### write_files:
# shell script execution with debug enabled
cat << "EOF" > /config/cloud/manual_run.sh
#!/bin/bash

# Set logging level (least to most)
# error, warn, info, debug, silly
export F5_BIGIP_RUNTIME_INIT_LOG_LEVEL=silly

# runtime init execution, with telemetry skipped
f5-bigip-runtime-init --config-file /config/cloud/runtime-init-conf.yaml --skip-telemetry
EOF

# runtime init configuration
cat << "EOF" > /config/cloud/runtime-init-conf.yaml
---
runtime_parameters:
  - name: DATAPLANE_IP
    type: metadata
    metadataProvider: 
      environment: aws
      type: network
      field: local-ipv4s
      index: 1
  - name: DATAPLANE_SUBNET
    type: metadata
    metadataProvider:
      environment: aws
      type: network
      field: subnet-ipv4-cidr-block
      index: 1
  - name: DATAPLANE_CIDR_MASK
    type: metadata
    metadataProvider:
      environment: aws
      type: network
      field: subnet-ipv4-cidr-block
      index: 1
      ipcalc: bitmask
  - name: DATAPLANE_GATEWAY
    type: metadata
    metadataProvider:
      environment: aws
      type: network
      field: local-ipv4s
      index: 1
      ipcalc: first
  - name: DATAPLANE_MASK
    type: metadata
    metadataProvider:
      environment: aws
      type: network
      field: subnet-ipv4-cidr-block
      index: 1
      ipcalc: mask
extension_packages:
    install_operations:
        - extensionType: do
          extensionVersion: ${f5_do_version}
        - extensionType: as3
          extensionVersion: ${f5_as3_version}
        - extensionType: ts
          extensionVersion: ${f5_ts_version}
extension_services:
    service_operations:
    - extensionType: do
      type: inline
      value: 
        schemaVersion: ${f5_do_schema_version}
        class: Device
        async: true
        label: BIG-IP Onboarding
        Common:
          class: Tenant
          systemConfig:
            class: System
            autoCheck: false
            autoPhonehome: false
            cliInactivityTimeout: 3600
            consoleInactivityTimeout: 3600
          sshdConfig:
            class: SSHD
            inactivityTimeout: 3600
          customDbVars:
            class: DbVariables
            provision.extramb: 500
            restjavad.useextramb: true
            ui.system.preferences.recordsperscreen: 250
            ui.system.preferences.advancedselection: advanced
            ui.advisory.enabled: true
            ui.advisory.color: green
            ui.advisory.text: "Advanced WAF for AWS API Gateway"
          ntpConfiguration:
            class: NTP
            servers:
              - 0.pool.ntp.org
              - 1.pool.ntp.org
              - 2.pool.ntp.org
            timezone: EST
          Provisioning:
            class: Provision
            ltm: nominal
            asm: nominal
          admin:
            class: User
            userType: regular
            password: ${bigipAdminPassword}
            shell: bash
          data-vlan:
            class: VLAN
            interfaces:
              - name: '1.1'
                tagged: false
          data-self:
            class: SelfIp
            address: "{{{ DATAPLANE_IP }}}"
            vlan: data-vlan
            allowService: none
            trafficGroup: traffic-group-local-only
          data-default-route:
            class: Route
            gw: "{{{ DATAPLANE_GATEWAY }}}"
            network: default
            mtu: 1500
    - extensionType: as3
      type: inline
      value: 
        class: AS3
        action: deploy
        persist: true
        declaration:
          class: ADC
          schemaVersion: ${f5_as3_schema_version}
          label: "Adv WAF with AWS API Gateway AppSvcs"
          remark: "Tested with 16.1"
          AdvWAF-AWS-APIGw:
            class: Tenant
            AdvWAF-APIGw-HTTPS:
              class: Application
              service:
                class: Service_HTTP
                virtualAddresses: 
                  - "${service_address}"
                pool: api_pool
              api_pool:
                class: Pool
                monitors: 
                  - http
                members:
                  - servicePort: 80
                    serverAddresses: 
                      - "${pool_member_1}"
                      - "${pool_member_2}"
EOF

# Add licensing if necessary
if [ "${bigipLicenseType}" != "PAYG" ]; then
  echo "bigip_ready_enabled:\n  - name: licensing\n    type: inline\n    commands:\n      - tmsh install sys license registration-key ${bigipLicense}\n" >> /config/cloud/runtime-init-conf.yaml
fi

# Download the f5-bigip-runtime-init package
# 30 attempts, 5 second timeout and 10 second pause between attempts
for i in {1..30}; do
    curl -fv --retry 1 --connect-timeout 5 -L https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v1.2.1/dist/f5-bigip-runtime-init-1.2.1-1.gz.run -o /var/config/rest/downloads/f5-bigip-runtime-init-1.2.1-1.gz.run && break || sleep 10
done

# Execute the installer
bash /var/config/rest/downloads/f5-bigip-runtime-init-1.2.1-1.gz.run -- "--cloud aws"

# Runtime Init execution on configuration file created above
f5-bigip-runtime-init --config-file /config/cloud/runtime-init-conf.yaml  