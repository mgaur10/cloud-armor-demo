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




# VPC for OWASP Cloud Armor WAF Demo
resource "google_compute_network" "armor_owasp_waf_demo" {
  name                    = "armor-owasp-waf-network"
  provider                = google-beta
  auto_create_subnetworks = false
  project                 = var.demo_project_id
  depends_on = [
    google_project_organization_policy.external_ip_access,
    time_sleep.wait_enable_service_api_armor,
  ]

}

# Backend subnet
resource "google_compute_subnetwork" "armor_owasp_waf_subnetwork" {
  name          = "${var.base_network_region}-waf-owasp"
  provider      = google-beta
  ip_cidr_range = "10.0.1.0/24"
  region        = var.base_network_region
  network       = google_compute_network.armor_owasp_waf_demo.id
  project       = var.demo_project_id
  depends_on = [
    google_compute_network.armor_owasp_waf_demo,
  ]
}


# Create a CloudRouter
resource "google_compute_router" "armor_owasp_waf_router" {
  project = var.demo_project_id
  name    = "${var.base_network_region}-waf-owasp-router"
  region  = google_compute_subnetwork.armor_owasp_waf_subnetwork.region
  network = google_compute_network.armor_owasp_waf_demo.id

  bgp {
    asn = 64514
  }

  depends_on = [google_compute_subnetwork.armor_owasp_waf_subnetwork]
}


# Configure a CloudNAT
resource "google_compute_router_nat" "armor_owasp_waf_router_nat" {
  project                            = var.demo_project_id
  name                               = "${var.base_network_region}-waf-owasp-router-nat"
  router                             = google_compute_router.armor_owasp_waf_router.name
  region                             = google_compute_router.armor_owasp_waf_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
  depends_on = [google_compute_router.armor_owasp_waf_router]
}


# Create FW to allow all IPs to access the external IP of the test application's website on port 3000.
resource "google_compute_firewall" "allow_js_site" {
  name      = "allow-js-site"
  network   = google_compute_network.armor_owasp_waf_demo.self_link
  project   = var.demo_project_id
  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }
  source_ranges = ["0.0.0.0/0"]

  depends_on = [
    google_compute_subnetwork.armor_owasp_waf_subnetwork,
  ]
}



# Create FW rules to allow health-checks 
resource "google_compute_firewall" "allow_healt_check" {
  project = var.demo_project_id

  name          = "allow-health-check-armor-waf"
  provider      = google-beta
  direction     = "INGRESS"
  network       = google_compute_network.armor_owasp_waf_demo.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  allow {
    protocol = "tcp"
  }
  target_tags = ["allow-healthcheck"]
  depends_on = [
    google_compute_subnetwork.armor_owasp_waf_subnetwork,
  ]
}


# Getting VM instance with container image
resource "null_resource" "juice_shop_conatiner" {

  triggers = {
    network            = google_compute_subnetwork.armor_owasp_waf_subnetwork.id
    local_network_zone = var.base_network_zone
    project            = var.demo_project_id
  }
  provisioner "local-exec" {
    command     = <<EOT
    gcloud compute instances create-with-container owasp-juice-shop-app --container-image bkimminich/juice-shop --network-interface=subnet=${google_compute_subnetwork.armor_owasp_waf_subnetwork.name},no-address --machine-type n1-standard-2 --zone ${var.base_network_zone} --tags allow-healthcheck --project ${var.demo_project_id} --scopes=https://www.googleapis.com/auth/cloud-platform --container-restart-policy=always --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring
    EOT
    working_dir = path.module
  }


  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
    gcloud -q compute instances delete owasp-juice-shop-app --zone ${self.triggers.local_network_zone} --project ${self.triggers.project}
    EOT
  }

  depends_on = [
    google_compute_subnetwork.armor_owasp_waf_subnetwork,
    google_compute_router_nat.armor_owasp_waf_router_nat,
  ]
}


resource "google_compute_instance_group" "juice_shop" {
  name        = "juice-shop-instance-group"
  description = "Juice Shop Instance Group"
  project     = var.demo_project_id
  instances = [
    "projects/${var.demo_project_id}/zones/${var.base_network_zone}/instances/owasp-juice-shop-app",
  ]
  named_port {
    name = "http"
    port = "3000"
  }

  zone = var.base_network_zone

  depends_on = [
    null_resource.juice_shop_conatiner,
  ]
}


# health check
resource "google_compute_health_check" "juice_shop_health_check" {
  project = var.demo_project_id

  name     = "juice-shop-health-check"
  provider = google-beta
  #  http_health_check {
  #    port_specification = "USE_SERVING_PORT"
  #  }

  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  tcp_health_check {
    port = "3000"
  }

  log_config {
    enable = true
  }

  depends_on = [
    time_sleep.wait_enable_service_api_armor,
  ]

}


# backend service with custom request and response headers
resource "google_compute_backend_service" "waf_backend" {
  name    = "juice-shop-backend"
  project = var.demo_project_id

  provider      = google-beta
  protocol      = "HTTP"
  port_name     = "http"
  timeout_sec   = 10
  enable_cdn    = false
  health_checks = [google_compute_health_check.juice_shop_health_check.id]


  backend {
    group                 = google_compute_instance_group.juice_shop.id
    balancing_mode        = "RATE"
    capacity_scaler       = 0.7
    max_rate_per_instance = 0.2
    #   port = 80
  }

  log_config {
    enable      = true
    sample_rate = 1
  }
  depends_on = [
    google_compute_instance_group.juice_shop,

  ]

}



# url map
resource "google_compute_url_map" "juice_shop_url_map" {
  name            = "juice-shop-loadbalancer"
  provider        = google-beta
  default_service = google_compute_backend_service.waf_backend.id
  project         = var.demo_project_id
  depends_on = [
    google_compute_backend_service.waf_backend,
  ]
}

# http proxy
resource "google_compute_target_http_proxy" "juice_shop_proxy" {
  name     = "juice-shop-proxy"
  provider = google-beta
  url_map  = google_compute_url_map.juice_shop_url_map.id
  project  = var.demo_project_id
  depends_on = [
    google_compute_url_map.juice_shop_url_map,
  ]
}


# reserved IP address
resource "google_compute_global_address" "juice_shop" {
  provider     = google-beta
  name         = "juice-shop-external-ip"
  project      = var.demo_project_id
  address_type = "EXTERNAL"
  depends_on = [
    time_sleep.wait_enable_service_api_armor,
  ]
}


# forwarding rule
resource "google_compute_global_forwarding_rule" "juice_shop_rule" {
  name        = "juice-shop-rule"
  provider    = google-beta
  ip_protocol = "TCP"
  port_range  = "80"
  target      = google_compute_target_http_proxy.juice_shop_proxy.id
  ip_address  = google_compute_global_address.juice_shop.id
  project     = var.demo_project_id
  depends_on = [
    google_compute_global_address.juice_shop,
    google_compute_target_http_proxy.juice_shop_proxy,
  ]
}


# Enable SSH through IAP to access compute instance
resource "google_compute_firewall" "waf_iap_proxy" {
  name      = "allow-ssh"
  network   = google_compute_network.armor_owasp_waf_demo.self_link
  project   = var.demo_project_id
  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]

  depends_on = [
    google_compute_subnetwork.armor_owasp_waf_subnetwork,
  ]
}


# Cloud Armor Security Policy
resource "google_compute_security_policy" "block_modsec_crs" {
  name        = "block-owasp-vulnerabilities"
  project     = var.demo_project_id
  description = "Block OWASP Application Vulnerabilities"

  rule {
    action   = "deny(403)"
    priority = "8000"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('cve-canary', {'sensitivity': 2})"
      }
    }
    description = "block Log4j vulnerability attack"
  }

  rule {
    action   = "deny(403)"
    priority = "9000"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "block sql injection attack"
  }

  rule {
    action   = "deny(403)"
    priority = "9001"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('lfi-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "block local file inclusion"
  }

  rule {
    action   = "deny(403)"
    priority = "9002"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('rce-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "block remote code execution attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "9003"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('protocolattack-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "block http protocol attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "9004"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sessionfixation-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "block session fixation attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "9005"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "block cross-site scripting attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "9006"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('rfi-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "block remote file inclusion attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "9007"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('methodenforcement-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "block method enforcement	attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "9008"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('php-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "block PHP injection attack attacks"
  }

  rule {
    action   = "deny(403)"
    priority = "9009"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('scannerdetection-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "block scanner detection"
  }

  rule {
    action   = "deny(403)"
    priority = "9010"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('json-sqli-canary', {'sensitivity': 1})"
      }
    }
    description = "block JSON-based SQL injection bypass vulnerability attack"
  }

  rule {
    action   = "allow"
    priority = "10000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["0.0.0.0"]
      }
    }

    description = "allow traffic from GCP Cloud shell and my IP"
  }

  rule {
    action   = "deny(403)"
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

