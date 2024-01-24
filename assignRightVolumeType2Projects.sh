#!/bin/bash
export OS_PROJECT_DOMAIN_NAME='Default'
export OS_USER_DOMAIN_NAME='Default'
export OS_PROJECT_NAME='admin'
export OS_TENANT_NAME='admin'
export OS_USERNAME='admin'
export OS_PASSWORD='pass'
export OS_AUTH_URL='http://<Vlan Internal API-vrrp>:5000'
export OS_INTERFACE='internal'
export OS_ENDPOINT_TYPE='internalURL'
export OS_IDENTITY_API_VERSION='3'
export OS_REGION_NAME='region1'
export OS_AUTH_PLUGIN='password'
volumeTypeLst=("business_class" "vip_class" "economy_class")

extract_prjIds() {
    local data="$1"
    local result=$(echo "$data" | grep access_project_ids | awk -F'|' '{print $3}' | tr -d ' ' | tr ',' '\n')
    echo "$result"
}

for volTypeName in "${volumeTypeLst[@]}"; do
    rawData=$(openstack volume type show $volTypeName)
    prjIdLstToSetVolTp=$(extract_prjIds "$rawData")
    if [ -n "$prjIdLstToSetVolTp" ]; then
        for prjId in $prjIdLstToSetVolTp; do
            echo "prjId--> $prjId"
            echo "volTypeName--> $volTypeName"
            cinder default-type-set $volTypeName $prjId
        done
    else
        echo "No project IDs found for volume type $volTypeName."
    fi
done
