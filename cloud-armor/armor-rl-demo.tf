##  Copyright 2023 Google LLC
##  
##  Licensed under the Apache License, Version 2.0 (the "License");
##  you may not use this file except in compliance with the License.
##  You may obtain a copy of the License at
##  
##      https://www.apache.org/licenses/LICENSE-2.0
##  
##  Unless required by applicable law or agreed to in writing, software
##  distributed under the License is distributed on an "AS IS" BASIS,
##  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##  See the License for the specific language governing permissions and
##  limitations under the License.


##  This code creates PoC demo environment for Cloud Armor
##  This demo code is not built for production workload ##


# Enable the necessary API services
resource "google_project_service" "armor_api_service" {
  for_each = toset([
    #    "servicenetworking.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "compute.googleapis.com",
  ])

  service = each.key

  project                    = var.demo_project_id
  disable_on_destroy         = true
  disable_dependent_services = true

}


# Enable this if external IP access is needed 
resource "google_project_organization_policy" "external_ip_access" {
  project    = var.demo_project_id
  constraint = "constraints/compute.vmExternalIpAccess"
  list_policy {
    allow {
      all = true
    }
  }

}



# Wait delay after enabling APIs
resource "time_sleep" "wait_enable_service_api_armor" {
  depends_on       = [google_project_service.armor_api_service]
  create_duration  = "45s"
  destroy_duration = "45s"
}



# VPC
resource "google_compute_network" "base_network" {
  name                    = "demo-network"
  provider                = google-beta
  auto_create_subnetworks = false
  project                 = var.demo_project_id
  depends_on = [
    google_project_organization_policy.external_ip_access,
    time_sleep.wait_enable_service_api_armor,
  ]

}



#Create the service Account for compute instances
resource "google_service_account" "def_ser_acc" {
  project      = var.demo_project_id
  account_id   = "demo-service-account"
  display_name = "Armor Project Service Account"
  depends_on = [
    time_sleep.wait_enable_service_api_armor,
  ]
}


# backend subnet
resource "google_compute_subnetwork" "base_subnetwork" {
  name          = "${var.base_network_region}-subnet"
  provider      = google-beta
  ip_cidr_range = "10.0.1.0/24"
  region        = var.base_network_region
  network       = google_compute_network.base_network.id
  project       = var.demo_project_id
  depends_on = [
    google_compute_network.base_network,
  ]
}



# Create a CloudRouter
resource "google_compute_router" "base_region_router" {
  project = var.demo_project_id
  name    = "${var.base_network_region}-subnet-router"
  region  = google_compute_subnetwork.base_subnetwork.region
  network = google_compute_network.base_network.id

  bgp {
    asn = 64514
  }
}


# Configure a CloudNAT
resource "google_compute_router_nat" "base_router_nat" {
  project                            = var.demo_project_id
  name                               = "${var.base_network_region}-router-nat"
  router                             = google_compute_router.base_region_router.name
  region                             = google_compute_router.base_region_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
  depends_on = [google_compute_router.base_region_router]
}


# instance template
resource "google_compute_instance_template" "base_instance_template" {
  name    = "${var.base_network_region}-instance-template"
  project = var.demo_project_id

  provider = google-beta
  tags     = ["http-server"]
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  network_interface {
    network    = google_compute_network.base_network.id
    subnetwork = google_compute_subnetwork.base_subnetwork.id
    #  access_config {
    # add external ip to fetch packages
    #   }
  }
  instance_description = "Basic compute instances"
  machine_type         = "n1-standard-1"
  can_ip_forward       = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }
  // Create a new boot disk from an image
  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true

  }

  # install apache server and serve a simple web page
  metadata_startup_script = file("${path.module}/scripts/startup.sh")
  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.def_ser_acc.email
    scopes = ["cloud-platform"]
  }
  depends_on = [
    google_compute_subnetwork.base_subnetwork,
    google_compute_router_nat.base_router_nat,
  ]
}



# MIG
resource "google_compute_instance_group_manager" "base_ic_manager" {
  project = var.demo_project_id

  name     = "${var.base_network_region}-instance-group-manager"
  provider = google-beta
  zone     = var.base_network_zone
  named_port {
    name = "http"
    port = 80
  }
  version {
    instance_template = google_compute_instance_template.base_instance_template.id
    name              = "primary"
  }
  base_instance_name = "vm-${var.base_network_region}"
  target_size        = 1


  auto_healing_policies {
    health_check      = google_compute_health_check.default.id
    initial_delay_sec = 300
  }
  depends_on = [
    google_compute_instance_template.base_instance_template,
  ]
}


## Create Instance auto scaler
resource "google_compute_autoscaler" "base_auto_scale" {
  provider = google-beta
  project  = var.demo_project_id

  name   = "autoscaler"
  zone   = var.base_network_zone
  target = google_compute_instance_group_manager.base_ic_manager.id

  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 1
    cooldown_period = 45

    cpu_utilization {
      target = 0.1
    }
  }
  depends_on = [
    google_compute_instance_group_manager.base_ic_manager,
  ]

}


# health check
resource "google_compute_health_check" "default" {
  project = var.demo_project_id

  name                = "health-check"
  provider            = google-beta
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  tcp_health_check {
    port = "80"
  }

  log_config {
    enable = true
  }

  depends_on = [
    time_sleep.wait_enable_service_api_armor,
  ]

}

# backend service with custom request and response headers
resource "google_compute_backend_service" "lb_backend_service" {
  name      = "backend-service"
  project   = var.demo_project_id
  provider  = google-beta
  protocol  = "HTTP"
  port_name = "http"
  #  load_balancing_scheme   = "EXTERNAL_MANAGED"
  timeout_sec   = 10
  enable_cdn    = false
  health_checks = [google_compute_health_check.default.id]


  # Adding backend for base region
  backend {
    group                 = google_compute_instance_group_manager.base_ic_manager.instance_group
    balancing_mode        = "RATE"
    capacity_scaler       = 0.7
    max_rate_per_instance = 0.2
    #   port = 80
  }

  # Adding backend for region-a
  backend {
    group                 = google_compute_instance_group_manager.ic_manager_region_a.instance_group
    balancing_mode        = "RATE"
    capacity_scaler       = 0.7
    max_rate_per_instance = 0.2
    #   port = 80
  }

  log_config {
    enable      = true
    sample_rate = 1
  }
  # security_policy = google_compute_security_policy.rate_limit.self_link

  depends_on = [
    google_compute_instance_group_manager.ic_manager_region_a,
    google_compute_instance_group_manager.base_ic_manager,
  ]
}


# url map
resource "google_compute_url_map" "default" {
  name            = "demo-loadbalancer"
  provider        = google-beta
  default_service = google_compute_backend_service.lb_backend_service.id
  project         = var.demo_project_id
  depends_on = [
    google_compute_backend_service.lb_backend_service,
  ]
}


# http proxy
resource "google_compute_target_http_proxy" "default" {
  name     = "target-http-proxy"
  provider = google-beta
  url_map  = google_compute_url_map.default.id
  project  = var.demo_project_id
  depends_on = [
    google_compute_url_map.default,
  ]
}


# reserved IP address
resource "google_compute_global_address" "default" {
  provider     = google-beta
  name         = "demo-static-ip"
  project      = var.demo_project_id
  address_type = "EXTERNAL"
  depends_on = [
    google_compute_url_map.default,
  ]
}


# forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
  name        = "forwarding-rule"
  provider    = google-beta
  ip_protocol = "TCP"
  #  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range = "80"
  target     = google_compute_target_http_proxy.default.id
  ip_address = google_compute_global_address.default.id
  project    = var.demo_project_id
  depends_on = [
    google_compute_global_address.default,
  ]
}


# allow access from health check ranges
resource "google_compute_firewall" "default" {
  project = var.demo_project_id

  name          = "default-allow-health-check"
  provider      = google-beta
  direction     = "INGRESS"
  network       = google_compute_network.base_network.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  target_tags = ["http-server"]
  depends_on = [
    google_compute_subnetwork.base_subnetwork,
  ]
}

# Enable SSH through IAP
resource "google_compute_firewall" "armor_allow_iap_proxy" {
  name      = "allow-iap-proxy"
  network   = google_compute_network.base_network.self_link
  project   = var.demo_project_id
  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
  depends_on = [
    google_compute_subnetwork.base_subnetwork,
  ]
}


# backend subnet for region-a
resource "google_compute_subnetwork" "subnetwork_region_a" {
  name          = "${var.network_region_a}-subnet"
  provider      = google-beta
  ip_cidr_range = "10.0.2.0/24"
  region        = var.network_region_a
  network       = google_compute_network.base_network.id
  project       = var.demo_project_id
  depends_on = [
    google_compute_network.base_network,
  ]
}


# Create a CloudRouter for region-a
resource "google_compute_router" "router_region_a" {
  project = var.demo_project_id
  name    = "${var.network_region_a}-subnet-router"
  region  = google_compute_subnetwork.subnetwork_region_a.region
  network = google_compute_network.base_network.id
  bgp {
    asn = 64514
  }
}


# Configure a CloudNAT
resource "google_compute_router_nat" "nats_region_a" {
  project                            = var.demo_project_id
  name                               = "${var.network_region_a}-router-nat"
  router                             = google_compute_router.router_region_a.name
  region                             = google_compute_router.router_region_a.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
  depends_on = [google_compute_router.router_region_a]
}


# instance template
resource "google_compute_instance_template" "region_a_instance_template" {
  name     = "eu-instance-template"
  project  = var.demo_project_id
  provider = google-beta
  tags     = ["http-server"]
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  network_interface {
    network    = google_compute_network.base_network.id
    subnetwork = google_compute_subnetwork.subnetwork_region_a.id
    #    access_config {
    # add external ip to fetch packages
    #    }
  }
  instance_description = "description assigned to instances"
  machine_type         = "n1-standard-1"
  can_ip_forward       = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  // Create a new boot disk from an image
  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true

  }

  # install nginx and serve a simple web page
  metadata_startup_script = file("${path.module}/scripts/startup.sh")
  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.def_ser_acc.email
    scopes = ["cloud-platform"]
  }
  depends_on = [
    google_compute_subnetwork.subnetwork_region_a,
    google_compute_router_nat.nats_region_a,
  ]
}



# Create Managed instance Group
resource "google_compute_instance_group_manager" "ic_manager_region_a" {
  project = var.demo_project_id

  name     = "${var.network_region_a}-instance-group-manager"
  provider = google-beta
  zone     = var.network_zone_a
  named_port {
    name = "http"
    port = 80
  }
  version {
    instance_template = google_compute_instance_template.region_a_instance_template.id
    name              = "primary"
  }
  base_instance_name = "vm-${var.network_region_a}"
  target_size        = 1


  auto_healing_policies {
    health_check      = google_compute_health_check.default.id
    initial_delay_sec = 300
  }
  depends_on = [
    google_compute_instance_template.region_a_instance_template,
  ]
}


## Create Instance auto scaler
resource "google_compute_autoscaler" "region_a_auto_scale" {
  provider = google-beta
  project  = var.demo_project_id

  name   = "${var.network_region_a}-autoscaler"
  zone   = var.network_zone_a
  target = google_compute_instance_group_manager.ic_manager_region_a.id

  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 1
    cooldown_period = 45

    cpu_utilization {
      target = 0.1
    }
  }
  depends_on = [
    google_compute_instance_group_manager.ic_manager_region_a,
  ]

}

# Load test subnet
resource "google_compute_subnetwork" "subnetwork_region_b" {
  name          = "${var.network_region_b}-subnet"
  provider      = google-beta
  ip_cidr_range = "10.0.3.0/24"
  region        = var.network_region_b
  network       = google_compute_network.base_network.id
  project       = var.demo_project_id
  depends_on = [
    google_compute_network.base_network,
  ]
}



# Create load testing Instance Asia
resource "google_compute_instance" "region_b_test_machine" {
  project      = var.demo_project_id
  name         = "test-machine-${var.network_region_b}"
  machine_type = "e2-standard-2"
  zone         = var.network_zone_b
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    network    = google_compute_network.base_network.self_link
    subnetwork = google_compute_subnetwork.subnetwork_region_b.self_link
    access_config {
      # add external ip to fetch packages
    }
  }

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.def_ser_acc.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = file("${path.module}/scripts/startup-siege.sh")
  metadata = {
    TARGET_IP = "${google_compute_global_address.default.address}"
  }
  tags = ["http-server"]
  depends_on = [
    google_compute_subnetwork.subnetwork_region_b,
    #   google_compute_router_nat.nats_region_b,
    google_project_organization_policy.external_ip_access,
    google_compute_global_address.default,
  ]

}


# Create load testing Instance EU
resource "google_compute_instance" "region_a_test_machine" {
  project      = var.demo_project_id
  name         = "test-machine-${var.network_region_a}"
  machine_type = "e2-standard-2"
  zone         = var.network_zone_a
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    network    = google_compute_network.base_network.self_link
    subnetwork = google_compute_subnetwork.subnetwork_region_a.self_link
    access_config {
      # add external ip to fetch packages
    }
  }

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.def_ser_acc.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = file("${path.module}/scripts/startup-siege.sh")
  metadata = {
    TARGET_IP = "${google_compute_global_address.default.address}"
  }
  tags = ["http-server"]

  depends_on = [
    google_compute_subnetwork.subnetwork_region_a,
    google_project_organization_policy.external_ip_access,
    google_compute_global_address.default,
  ]
}


# Create load testing Instance US
resource "google_compute_instance" "base_region_test_machine" {
  project      = var.demo_project_id
  name         = "test-machine-${var.base_network_region}"
  machine_type = "e2-standard-2"
  zone         = var.base_network_zone
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }


  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    network    = google_compute_network.base_network.id
    subnetwork = google_compute_subnetwork.base_subnetwork.id
    access_config {
      #add external ip to fetch packages
    }
  }
  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.def_ser_acc.email
    scopes = ["cloud-platform"]
  }

  tags                    = ["http-server"]
  metadata_startup_script = file("${path.module}/scripts/startup-siege.sh")
  metadata = {
    TARGET_IP = "${google_compute_global_address.default.address}"
  }

  depends_on = [
    google_compute_subnetwork.base_subnetwork,
    google_project_organization_policy.external_ip_access,
    google_compute_global_address.default,
  ]
}



# Cloud Armor Security Policy
resource "google_compute_security_policy" "rate_limit" {
  name    = "rate-limit"
  project = var.demo_project_id

  rule {
    action   = "rate_based_ban"
    priority = "1000"

    rate_limit_options {
      rate_limit_threshold {
        count        = 50
        interval_sec = 120
      }

      ban_duration_sec = 300
      conform_action   = "allow"
      enforce_on_key   = "IP"
      exceed_action    = "deny(429)"

    }

    match {
      expr {
        expression = "true"
      }
    }
    description = "policy for rate limiting"
  }

  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "default rule"
  }
  depends_on = [
    time_sleep.wait_enable_service_api_armor,
  ]
}




