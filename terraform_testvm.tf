resource "google_compute_instance" "terraform-testvm" {
    name         = "${var.global_params["prefix"]}-terraform-testvm"

    machine_type = "n1-standard-1"
    zone         = "europe-west1-b"

    boot_disk {
        initialize_params {
            image = "centos-cloud/centos-8"
        }
    }

    network_interface {
        network = "default"

        access_config {
            // Ephemeral IP
        }
    }

    service_account {
        scopes = ["service-control", "service-management", "logging-write", "monitoring-write", "trace-append"]
    }
}
