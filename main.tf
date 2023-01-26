resource "google_compute_subnetwork" "bookshelf-subnet-tf-eu-central2" {
  name          = "bookshelf-subnet-tf-eu-central2"
  ip_cidr_range = "10.37.3.0/24"
  region        = "europe-central2"
  network       = google_compute_network.bookshelf-vpc-tf.id #implicit dependency

}

resource "google_compute_network" "bookshelf-vpc-tf" {
  name                    = "bookshelf-vpc-tf"
  auto_create_subnetworks = false #When set to true, the network is created in "auto subnet mode". When set to false, the network is created in "custom subnet mode".
  mtu                     = 1460
}


resource "google_compute_router" "router-bookshelf" { # just router for our NAT
  name    = "router-bookshelf"
  region  = google_compute_subnetwork.bookshelf-subnet-tf-eu-central2.region
  network = google_compute_network.bookshelf-vpc-tf.id

}

resource "google_compute_router_nat" "nat" { # lets certain resources without external IP addresses create outbound connections to the internet.
  name                               = "my-router-nat"
  router                             = google_compute_router.router-bookshelf.name
  region                             = google_compute_router.router-bookshelf.region
  nat_ip_allocate_option             = "AUTO_ONLY"                     # for only allowing NAT IPs allocated by Google Cloud Platform
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES" #  all of the IP ranges in every Subnetwork are allowed to Nat


}

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

resource "google_compute_global_address" "private_ip_block" { #  a block of private IP addresses.
  name          = "private-ip-block"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  ip_version    = "IPV4"
  prefix_length = 20
  network       = google_compute_network.bookshelf-vpc-tf.self_link
}

resource "google_service_networking_connection" "private_vpc_connection" { # allows our instances to communicate exclusively using Google’s internal network
  # Private services access is implemented as a VPC peering connection between your VPC network and the underlying Google Cloud VPC network where your Cloud SQL instance resides    
  network                 = google_compute_network.bookshelf-vpc-tf.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_block.name]
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "bookshelf-db-instance" {
  name                = "petclinic-db-tf-${random_id.db_name_suffix.hex}"
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

}
resource "google_sql_database" "bookshelf-db" {
  name      = var.name
  instance  = google_sql_database_instance.bookshelf-db-instance.name
  charset   = "utf8"
  collation = "utf8_general_ci"

}
resource "google_sql_user" "users" {
  name     = var.name
  instance = google_sql_database_instance.bookshelf-db-instance.name
  password = var.password
}

data "google_service_account" "bookshelf-sa" {
  account_id = var.account_id
}

resource "google_storage_bucket" "bookshelf-content" {
  name          = "bookshelf-py-content"
  location      = "EU"
  force_destroy = true # When deleting a bucket, this boolean option will delete all contained objects

  uniform_bucket_level_access = true #  Enables Uniform bucket-level access access to a bucket.

  versioning {
    enabled = true # versioning is fully enabled for this bucket.
  }
}


