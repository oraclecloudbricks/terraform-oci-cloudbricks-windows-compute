# Copyright (c) 2021 Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# datasource.tf
#
# Purpose: The following script contains the logic to do lookup of pre-created or yet-to-be-created resources inside the tenancy

/********** Compartment and CF Accessors **********/
data "oci_identity_compartments" "COMPARTMENTS" {
  compartment_id            = var.tenancy_ocid
  compartment_id_in_subtree = true
  filter {
    name   = "name"
    values = [var.windows_compute_instance_compartment_name]
  }
}

data "oci_identity_compartments" "NWCOMPARTMENTS" {
  compartment_id            = var.tenancy_ocid
  compartment_id_in_subtree = true
  filter {
    name   = "name"
    values = [var.windows_compute_network_compartment_name]
  }
}

data "oci_core_vcns" "VCN" {
  compartment_id = local.nw_compartment_id
  filter {
    name   = "display_name"
    values = [var.vcn_display_name]
  }
}


/********** Subnet Accessors **********/

data "oci_core_subnets" "SUBNET" {
  compartment_id = local.nw_compartment_id
  vcn_id         = local.vcn_id
  filter {
    name   = "display_name"
    values = [var.network_subnet_name]
  }
}

/********** Backup Policy Accessors **********/

data "oci_core_volume_backup_policies" "BACKUPPOLICYBOOTVOL" {
  filter {
    name = "display_name"

    values = [var.bkp_policy_boot_volume]
  }
}

data "oci_core_network_security_groups" "NSG" {
  compartment_id = local.nw_compartment_id
  vcn_id         = local.vcn_id


  filter {
    name   = "display_name"
    values = ["${var.compute_nsg_name}"]
  }

}

/************ Windows WINRM enablement Datasources *****************/
# Use the cloudinit.ps1 as a template and pass the instance name, user and password as variables to same
data "template_file" "cloudinit_ps1" {
  count = var.num_instances
  vars = {
    instance_user     = var.os_user
    instance_password = "${random_string.instance_password.result}"
    instance_name     = count.index < "10" ? "${var.compute_display_name_base}${var.label_zs[0]}${count.index + 1}" : "${var.compute_display_name_base}${var.label_zs[1]}${count.index + 1}"
  }
  template = file("${path.module}/${var.userdata}/${var.cloudinit_ps1}")
}

data "template_cloudinit_config" "cloudinit_config" {
  count         = var.num_instances
  gzip          = false
  base64_encode = true

  # The cloudinit.ps1 uses the #ps1_sysnative to update the instance password and configure winrm for https traffic
  part {
    filename     = var.cloudinit_ps1
    content_type = "text/x-shellscript"
    content      = data.template_file.cloudinit_ps1[count.index].rendered
  }

  # The cloudinit.yml uses the #cloud-config to write files remotely into the instance, this is executed as part of instance setup
  part {
    filename     = var.cloudinit_config
    content_type = "text/cloud-config"
    content      = file("${path.module}/${var.userdata}/${var.cloudinit_config}")
  }
}


data "oci_core_instance_credentials" "InstanceCredentials" {
  count       = var.num_instances
  instance_id = oci_core_instance.Compute[count.index].id
}

/************ Windows WINRM enablement Datasources *****************/
locals {

  # Subnet OCID local accessors 
  subnet_ocid = length(data.oci_core_subnets.SUBNET.subnets) > 0 ? data.oci_core_subnets.SUBNET.subnets[0].id : null

  # Compartment OCID Local Accessor
  compartment_id    = lookup(data.oci_identity_compartments.COMPARTMENTS.compartments[0], "id")
  nw_compartment_id = lookup(data.oci_identity_compartments.NWCOMPARTMENTS.compartments[0], "id")
  # VCN OCID Local Accessor
  vcn_id = lookup(data.oci_core_vcns.VCN.virtual_networks[0], "id")
  # Backup policies retrieval by tfvars volume-specifc values 
  backup_policy_bootvolume_disk_id = data.oci_core_volume_backup_policies.BACKUPPOLICYBOOTVOL.volume_backup_policies[0].id

  # NSG OCID Local Accessor 
  nsg_id = length(data.oci_core_network_security_groups.NSG.network_security_groups) > 0 ? data.oci_core_network_security_groups.NSG.network_security_groups[0].id : ""

  # Local accessor for powershell executor
  powershell             = "powershell.exe"
}