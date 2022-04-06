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
  - name: MGMT_IP
    type: metadata
    metadataProvider: 
      environment: aws
      type: network
      field: local-ipv4s
      index: 0
  - name: MGMT_GATEWAY
    type: metadata
    metadataProvider:
      environment: aws
      type: network
      field: local-ipv4s
      index: 0
      ipcalc: first
  - name: DATAPLANE_IP
    type: metadata
    metadataProvider: 
      environment: aws
      type: network
      field: local-ipv4s
      index: 1
  - name: DATAPLANE_GATEWAY
    type: metadata
    metadataProvider:
      environment: aws
      type: network
      field: local-ipv4s
      index: 1
      ipcalc: first
extension_packages:
  install_operations:
    - extensionType: do
      extensionVersion: ${f5_do_version}
    - extensionType: as3
      extensionVersion: ${f5_as3_version}
    - extensionType: ts
      extensionVersion: ${f5_ts_version}
    - extensionType: cf
      extensionVersion: ${f5_cf_version}
extension_services:
  service_operations:
    - extensionType: do
      type: inline
      value: 
        schemaVersion: ${f5_do_schema_version}
        class: Device
        async: true
        label: F5 BIG-IP Onboarding
        Common:
          class: Tenant
          systemConfig:
            class: System
            autoCheck: false
            autoPhonehome: false
            cliInactivityTimeout: 3600
            consoleInactivityTimeout: 3600
            hostname: ${cm_self_hostname}
          sshdConfig:
            class: SSHD
            inactivityTimeout: 3600
            protocol: 2
          customDbVars:
            class: DbVariables
            provision.extramb: 1000
            restjavad.useextramb: true
            ui.system.preferences.recordsperscreen: 250
            ui.system.preferences.advancedselection: advanced
            ui.advisory.enabled: true
            ui.advisory.color: blue
            ui.advisory.text: "F5 AWS Firewall"
            tm.fastl4_ack_mirror: disable
            tm.fw.defaultaction: drop
            tm.rejectunmatched: false
            icrd.timeout: 120
            restjavad.timeout: 120
            restnoded.timeout: 120
          ntpConfiguration:
            class: NTP
            servers:
              - 169.254.169.123
              - 0.pool.ntp.org
              - 1.pool.ntp.org
              - 2.pool.ntp.org
            timezone: EST
          Provisioning:
            class: Provision
            ltm: nominal
            afm: nominal
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
            mtu: 1500
          data-self:
            class: SelfIp
            address: "{{{ DATAPLANE_IP }}}"
            vlan: data-vlan
            allowService: all
            trafficGroup: traffic-group-local-only
          data-default-route:
            class: Route
            gw: "{{{ DATAPLANE_GATEWAY }}}"
            network: default
            mtu: 1500
          configSync:
            class: ConfigSync
            configsyncIp: /Common/data-self/address
          failoverAddress:
            class: FailoverUnicast
            address: /Common/data-self/address
          failoverGroup:
            class: DeviceGroup
            type: sync-failover
            members:
              - ${cm_primary_hostname}
              - ${cm_secondary_hostname}
            owner: /Common/failoverGroup/members/0
            autoSync: true
            saveOnAutoSync: false
            networkFailover: true
            fullLoadOnSync: false
            asmSync: false
          trust:
            class: DeviceTrust
            localUsername: admin
            localPassword: ${bigipAdminPassword}
            remoteHost: ${cm_peer_ip}
            remoteUsername: admin
            remotePassword: ${bigipAdminPassword}
    - extensionType: as3
      type: inline
      value:
        class: AS3
        action: deploy
        persist: true
        declaration:
            class: ADC
            schemaVersion: ${f5_as3_schema_version}
            label: F5 AWS HA Testing
            remark: Tested with 16.1
            Health_Monitor:
                class: Tenant
                Health_Monitoring:
                    class: Application
                    health_monitoring_http:
                        class: Service_HTTP
                        virtualAddresses:
                            - ${monitoring_address}
                        profileHTTP: basic
                        virtualType: standard
                        virtualPort: 443
                        iRules:
                            - Monitoring_iRule
                    Monitoring_iRule:
                        class: iRule
                        iRule: |-
                            when HTTP_REQUEST {
                            HTTP::respond 200 content "OK"
                            }
            IP-Forwarding:
                class: Tenant
                default_forwarding_ipv4:
                    class: Application
                    default_forwarder_ipv4:
                        class: Service_Forwarding
                        virtualAddresses:
                            - 0.0.0.0/0
                        virtualPort:
                            - '0'
                        forwardingType: ip
                        layer4: any
                        profileL4: basic
                        snat: none
                default_forwarding_ipv6:
                    class: Application
                    default_forwarder_ipv6:
                        class: Service_Forwarding
                        virtualAddresses:
                            - '::/0'
                        virtualPort:
                            - '0'
                        forwardingType: ip
                        layer4: any
                        profileL4: basic
                        snat: none
    - extensionType: cf
      type: inline
      value:
        class: Cloud_Failover
        environment: aws
        controls:
          class: Controls
          logLevel: silly
        externalStorage:
          scopingName: '${s3_bucket}'
        failoverAddresses:
          enabled: false
          scopingTags:
            f5_cloud_failover_label: '${f5_cloud_failover_label}'
        failoverRoutes:
          enabled: true
          scopingTags:
            f5_cloud_failover_label: '${f5_cloud_failover_label}'
          scopingAddressRanges:
            - range: '${client_subnet_cidr_ipv4}'
            - range: '${server_subnet_cidr_ipv4}'
          defaultNextHopAddresses:
            discoveryType: static
            items:
              - '${primary_data_ip}'
              - '${secondary_data_ip}'
post_onboard_enabled:
  - name: trigger_failover
    type: inline
    commands:
    - $(nohup bash /config/failover/tgactive &>/dev/null &)
    - $(nohup tmsh modify cm device-group failoverGroup devices modify { ${cm_secondary_hostname} { set-sync-leader } } &>/dev/null &)
    - tmsh save sys config
EOF

# Add licensing if necessary
if [ "${bigipLicenseType}" != "PAYG" ]; then
  echo "bigip_ready_enabled:\n  - name: licensing\n    type: inline\n    commands:\n      - tmsh install sys license registration-key ${bigipLicense}\n" >> /config/cloud/runtime-init-conf.yaml
fi

# Download the f5-bigip-runtime-init package
# 30 attempts, 5 second timeout and 10 second pause between attempts
for i in {1..30}; do
    curl -fv --retry 1 --connect-timeout 5 -L https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v1.3.2/dist/f5-bigip-runtime-init-1.3.2-1.gz.run -o /var/config/rest/downloads/f5-bigip-runtime-init-1.3.2-1.gz.run && break || sleep 10
done

# Execute the installer
bash /var/config/rest/downloads/f5-bigip-runtime-init-1.3.2-1.gz.run -- "--cloud aws"

# Runtime Init execution on configuration file created above
f5-bigip-runtime-init --config-file /config/cloud/runtime-init-conf.yaml --skip-telemetry