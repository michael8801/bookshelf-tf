# subnetwork
resource "google_compute_subnetwork" "bookshelf-subnet-tf-eu-central2" {
  name          = "bookshelf-subnet-tf-eu-central2"
  ip_cidr_range = "10.37.3.0/24"
  region        = "europe-central2"
  network       = google_compute_network.bookshelf-vpc-tf.id #implicit dependency

}

# vpc
resource "google_compute_network" "bookshelf-vpc-tf" {
  name                    = "bookshelf-vpc-tf"
  auto_create_subnetworks = false # When set to true, the network is created in "auto subnet mode". When set to false, the network is created in "custom subnet mode".
  mtu                     = 1460
}

# router for cloud nat
resource "google_compute_router" "router-bookshelf" {
  name    = "router-bookshelf"
  region  = google_compute_subnetwork.bookshelf-subnet-tf-eu-central2.region
  network = google_compute_network.bookshelf-vpc-tf.id

}

# cloud nat
resource "google_compute_router_nat" "nat" { # lets certain resources without external IP addresses create outbound connections to the internet.
  name                               = "my-router-nat"
  router                             = google_compute_router.router-bookshelf.name
  region                             = google_compute_router.router-bookshelf.region
  nat_ip_allocate_option             = "AUTO_ONLY"                     # for only allowing NAT IPs allocated by Google Cloud Platform
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES" #  all of the IP ranges in every Subnetwork are allowed to Nat


}

# firewall ssh rule
resource "google_compute_firewall" "ssh-rule" {
  project       = var.project
  name          = "bookshelf-allow-ssh-tf"
  network       = google_compute_network.bookshelf-vpc-tf.self_link
  description   = "Creates firewall rule with ssh tag"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }


  target_tags = ["ssh"]
}

# firewall http rule
resource "google_compute_firewall" "http-rule" {
  project       = var.project
  name          = "bookshelf-allow-http-tf"
  network       = google_compute_network.bookshelf-vpc-tf.self_link
  description   = "Creates firewall rule with web tag"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }


  target_tags = ["web"]
}

# a block of private IP addresses
resource "google_compute_global_address" "private_ip_block" {
  name          = "private-ip-block"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  ip_version    = "IPV4"
  prefix_length = 20
  network       = google_compute_network.bookshelf-vpc-tf.self_link
}

# private connection between VPSs
resource "google_service_networking_connection" "private_vpc_connection" { # allows our instances to communicate exclusively using Google’s internal network
  # Private services access is implemented as a VPC peering connection between your VPC network and the underlying Google Cloud VPC network where your Cloud SQL instance resides    
  network                 = google_compute_network.bookshelf-vpc-tf.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_block.name]
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

# sql instance
/*resource "google_sql_database_instance" "bookshelf-db-instance" {
  name                = "bookshelf-db-tf-${random_id.db_name_suffix.hex}"
  database_version    = var.db-version
  region              = var.region
  depends_on          = [google_service_networking_connection.private_vpc_connection]
  deletion_protection = false

  settings {
    tier      = "db-f1-micro"
    disk_size = 10
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.bookshelf-vpc-tf.id
    }
  }

  # sql db
}
resource "google_sql_database" "bookshelf-db" {
  name      = var.name
  instance  = google_sql_database_instance.bookshelf-db-instance.name
  charset   = "utf8"
  collation = "utf8_general_ci"

}

# users for db
resource "google_sql_user" "users" {
  name     = var.name
  instance = google_sql_database_instance.bookshelf-db-instance.name
  password = var.password
}



# bucket for app content
resource "google_storage_bucket" "bookshelf-content" {
  name          = "bookshelf-py-content"
  location      = "EU"
  force_destroy = true # When deleting a bucket, this boolean option will delete all contained objects

  uniform_bucket_level_access = true #  Enables Uniform bucket-level access access to a bucket.

  versioning {
    enabled = true # versioning is fully enabled for this bucket.
  }
}
*/

# service account
data "google_service_account" "bookshelf-sa" {
  account_id = var.account_id
}

# instance template
resource "google_compute_instance_template" "bookshelf-template" {
  name = "bookshelf-template"

  tags = ["ssh", "web"]


  machine_type   = var.machine_type
  can_ip_forward = false # to restrict sending and receiving of packets with non-matching source or destination IPs

  scheduling {
    automatic_restart = true # the instance should be automatically restarted if it is terminated by Compute Engine
  }

  // Create a new boot disk from an image
  disk {
    source_image = "debian-cloud/debian-10"
    auto_delete  = true
    boot         = true
  }

  /*metadata = {
    startup-script = <<-EOF1
      #! /bin/bash
    EOF1
  }*/

  network_interface {
    subnetwork = google_compute_subnetwork.bookshelf-subnet-tf-eu-central2.self_link
  }


  service_account {
    email  = data.google_service_account.bookshelf-sa.email
    scopes = ["cloud-platform"]
  }
}

# MIG
resource "google_compute_instance_group_manager" "mig-bookshelf-tf" {
  name = "mig-bookshelf-tf"

  base_instance_name = "bookshelf"
  zone               = var.zone

  version {
    instance_template = google_compute_instance_template.bookshelf-template.id
  }

  target_size = 1 # number of running instances

  auto_healing_policies {
    health_check      = google_compute_health_check.bookshelf-autohealing.id
    initial_delay_sec = 300
  }
}

# autoscaler for mig 
resource "google_compute_autoscaler" "bookshelf" {

  name   = "bookshelf-autoscaler"
  zone   = var.zone
  target = google_compute_instance_group_manager.mig-bookshelf-tf.id

  autoscaling_policy {
    max_replicas    = 2
    min_replicas    = 1
    cooldown_period = 60


    cpu_utilization {
      target = 0.7 # 70%
    }

  }
}

# health check
resource "google_compute_health_check" "bookshelf-autohealing" {
  name                = "bookshelf-autohealing-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10

  tcp_health_check {
    # request_path = "/healthz"
    port = "8080"
  }
}

# reserved IP address
resource "google_compute_global_address" "static-ip-bookshelf" {
  name = "static-ip-bookshelf"
}

# forwarding rule
resource "google_compute_global_forwarding_rule" "bookshelf-fr" {
  name                  = "bookshelf-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.bookshelf-target-http-proxy.id
  ip_address            = google_compute_global_address.static-ip-bookshelf.id
}

# http proxy 80, 8080
resource "google_compute_target_http_proxy" "bookshelf-target-http-proxy" {
  name    = "bookshelf-target-http-proxy"
  url_map = google_compute_url_map.bookshelf-url-map.id
}

# url map
resource "google_compute_url_map" "bookshelf-url-map" {
  name            = "bookshelf-url-map"
  default_service = google_compute_backend_service.bookshelf-backend-service.id
}

# backend service
resource "google_compute_backend_service" "bookshelf-backend-service" {
  name                  = "bookshelf-backend-service"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.bookshelf-autohealing.id]
  backend {
    group           = google_compute_instance_group_manager.mig-bookshelf-tf.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

