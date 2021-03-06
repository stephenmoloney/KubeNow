# Cluster settings
variable cluster_prefix {}

variable boot_image {}

variable bootstrap_script {
  default = "bootstrap/bootstrap-default.sh"
}

variable inventory_template {
  default = "inventory-template"
}

variable kubeadm_token {
  default = ""
}

variable ssh_user {
  default = "ubuntu"
}

variable ssh_key {
  default = "ssh_key.pub"
}

# Google credentials
variable gce_project {}

variable gce_zone {}

variable gce_credentials_file {
  default = "service-account.json"
}

# Master settings
variable master_count {
  default = 1
}

variable master_flavor {}
variable master_disk_size {}

variable master_as_edge {
  default = "true"
}

# Nodes settings
variable node_count {}

variable node_flavor {}
variable node_disk_size {}

# Edges settings
variable edge_count {
  default = 0
}

variable edge_flavor {
  default = "nothing"
}

variable edge_disk_size {
  default = "nothing"
}

# Glusternode settings
variable glusternode_count {
  default = 0
}

variable glusternode_flavor {
  default = "nothing"
}

variable glusternode_disk_size {
  default = "nothing"
}

variable glusternode_extra_disk_size {
  default = "200"
}

variable gluster_volumetype {
  default = "none:1"
}

# Cloudflare settings
variable use_cloudflare {
  default = "false"
}

variable cloudflare_email {
  default = "nothing"
}

variable cloudflare_token {
  default = "nothing"
}

variable cloudflare_domain {
  default = ""
}

variable cloudflare_subdomain {
  default = ""
}

variable cloudflare_proxied {
  default = "false"
}

variable cloudflare_record_texts {
  type    = "list"
  default = ["*"]
}

# Provider
provider "google" {
  credentials = "${file("${var.gce_credentials_file}")}"
  project     = "${var.gce_project}"
  region      = "${var.gce_zone}"
}

# Network (here would be nice with condition)
module "network" {
  source       = "./network"
  network_name = "${var.cluster_prefix}"
}

module "master" {
  # Core settings
  source      = "./node"
  count       = "1"
  name_prefix = "${var.cluster_prefix}-master"
  flavor_name = "${var.master_flavor}"
  image_name  = "${var.boot_image}"
  zone        = "${var.gce_zone}"

  # SSH settings
  ssh_user = "${var.ssh_user}"
  ssh_key  = "${var.ssh_key}"

  # Network settings
  network_name = "${module.network.network_name}"

  # Disk settings
  disk_size = "${var.master_disk_size}"

  # Bootstrap settings
  bootstrap_file = "${var.bootstrap_script}"
  kubeadm_token  = "${var.kubeadm_token}"
  node_labels    = "${split(",", var.master_as_edge == "true" ? "role=master,role=edge" : "role=master")}"
  node_taints    = [""]
  master_ip      = ""
}

module "node" {
  # Core settings
  source      = "./node"
  count       = "${var.node_count}"
  name_prefix = "${var.cluster_prefix}-node"
  flavor_name = "${var.node_flavor}"
  image_name  = "${var.boot_image}"
  zone        = "${var.gce_zone}"

  # SSH settings
  ssh_user = "${var.ssh_user}"
  ssh_key  = "${var.ssh_key}"

  # Network settings
  network_name = "${module.network.network_name}"

  # Disk settings
  disk_size = "${var.node_disk_size}"

  # Bootstrap settings
  bootstrap_file = "${var.bootstrap_script}"
  kubeadm_token  = "${var.kubeadm_token}"
  node_labels    = ["role=node"]
  node_taints    = [""]
  master_ip      = "${element(module.master.local_ip_v4, 0)}"
}

module "edge" {
  # Core settings
  source      = "./node"
  count       = "${var.edge_count}"
  name_prefix = "${var.cluster_prefix}-edge"
  flavor_name = "${var.edge_flavor}"
  image_name  = "${var.boot_image}"
  zone        = "${var.gce_zone}"

  # SSH settings
  ssh_user = "${var.ssh_user}"
  ssh_key  = "${var.ssh_key}"

  # Network settings
  network_name = "${module.network.network_name}"

  # Disk settings
  disk_size = "${var.edge_disk_size}"

  # Bootstrap settings
  bootstrap_file = "${var.bootstrap_script}"
  kubeadm_token  = "${var.kubeadm_token}"
  node_labels    = ["role=edge"]
  node_taints    = [""]
  master_ip      = "${element(module.master.local_ip_v4, 0)}"
}

module "glusternode" {
  # Core settings
  source      = "./node-extra-disk"
  count       = "${var.glusternode_count}"
  name_prefix = "${var.cluster_prefix}-glusternode"
  flavor_name = "${var.glusternode_flavor}"
  image_name  = "${var.boot_image}"
  zone        = "${var.gce_zone}"

  # SSH settings
  ssh_user = "${var.ssh_user}"
  ssh_key  = "${var.ssh_key}"

  # Network settings
  network_name = "${module.network.network_name}"

  # Disk settings
  disk_size       = "${var.glusternode_disk_size}"
  extra_disk_size = "${var.glusternode_extra_disk_size}"

  # Bootstrap settings
  bootstrap_file = "${var.bootstrap_script}"
  kubeadm_token  = "${var.kubeadm_token}"
  node_labels    = ["storagenode=glusterfs"]
  node_taints    = [""]
  master_ip      = "${element(module.master.local_ip_v4, 0)}"
}

# The code below (from here to end) should be identical for all cloud providers

# set cloudflare record (optional)
module "cloudflare" {
  # count values can not be dynamically computed, that's why we are using var.edge_count and not length(iplist)
  record_count         = "${var.use_cloudflare != true ? 0 : var.master_as_edge == true ? (var.edge_count + var.master_count) * length(var.cloudflare_record_texts) : var.edge_count * length(var.cloudflare_record_texts)}"
  source               = "../common/cloudflare"
  cloudflare_email     = "${var.cloudflare_email}"
  cloudflare_token     = "${var.cloudflare_token}"
  cloudflare_domain    = "${var.cloudflare_domain}"
  cloudflare_subdomain = "${var.cloudflare_subdomain}"

  # add optional subdomain to record names
  # terraform interpolation is limited and can not return list in conditionals, workaround: first join to string, then split
  record_names = "${split(",", var.cloudflare_subdomain != "" ? join(",", formatlist("%s.%s", var.cloudflare_record_texts, var.cloudflare_subdomain)) : join(",", var.cloudflare_record_texts ) )}"

  # terraform interpolation is limited and can not return list in conditionals, workaround: first join to string, then split
  iplist  = "${split(",", var.master_as_edge == true ? join(",", concat(module.edge.public_ip, module.master.public_ip) ) : join(",", module.edge.public_ip) )}"
  proxied = "${var.cloudflare_proxied}"
}

# Generate Ansible inventory (identical for each cloud provider)
module "generate-inventory" {
  source                 = "../common/inventory"
  cluster_prefix         = "${var.cluster_prefix}"
  domain                 = "${var.use_cloudflare == true ? module.cloudflare.domain_and_subdomain : format("%s.nip.io", element(concat(module.edge.public_ip, module.master.public_ip, list("")), 0))}"
  ssh_user               = "${var.ssh_user}"
  master_hostnames       = "${module.master.hostnames}"
  master_public_ip       = "${module.master.public_ip}"
  master_private_ip      = "${module.master.local_ip_v4}"
  master_as_edge         = "${var.master_as_edge}"
  edge_count             = "${var.edge_count}"
  edge_hostnames         = "${module.edge.hostnames}"
  edge_public_ip         = "${module.edge.public_ip}"
  edge_private_ip        = "${module.edge.local_ip_v4}"
  node_count             = "${var.node_count}"
  node_hostnames         = "${module.node.hostnames}"
  node_public_ip         = "${module.node.public_ip}"
  node_private_ip        = "${module.node.local_ip_v4}"
  glusternode_count      = "${var.glusternode_count}"
  gluster_volumetype     = "${var.gluster_volumetype}"
  gluster_extra_disk_dev = "${element(concat(module.glusternode.extra_disk_device, list("")),0)}"
  inventory_template     = "${var.inventory_template}"
}
