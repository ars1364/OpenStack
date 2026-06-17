FROM docker.cloudinative.com/openstackmagnum/heat-container-agent:wallaby-stable-1
COPY ca-bundle.crt /opt/ca-bundle-cloudinative.crt
RUN printf "%s\n" "#!/bin/bash" "mkdir -p /etc/pki/tls/certs /etc/sysconfig" "cp /opt/ca-bundle-cloudinative.crt /etc/pki/tls/certs/ca-bundle.crt" "touch /etc/sysconfig/docker" "echo \"OPTIONS=\\"\\"\" >> /etc/sysconfig/docker" "echo \"[cloudinative] installed ca-bundle.crt and /etc/sysconfig/docker\"" "/opt/heat-container-agent/configure_container_agent.sh" "export LC_ALL=C" "exec os-collect-config --debug" > /usr/bin/start-heat-container-agent && chmod +x /usr/bin/start-heat-container-agent
RUN cat /usr/bin/start-heat-container-agent
