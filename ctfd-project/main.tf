# main.tf

# Providers
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "docker" {
  # Local Docker daemon on the hypervisor host. No extra config needed.
}

# VARIABLES

# Student Name Variable
variable "student_name" {
  type        = string
  description = "Your student identifier (e.g., jsmith, mgarcia)"

  validation {
    condition     = can(regex("^[a-z]{2,10}$", var.student_name))
    error_message = "Student name must be 2-10 lowercase letters."
  }
}

# Port for ctfd web interface
variable "ctfd_port" {
  description = "Host port for the CTFd web interface"
  type        = number
  default     = 8000
}

# DB Root Password
variable "db_root_password" {
  description = "MariaDB root password"
  type        = string
  sensitive   = true
}

# DB Password
variable "db_password" {
  description = "MariaDB password for the ctfd user"
  type        = string
  sensitive   = true
}

# SECRET KEY
# CTFd signs sessions with SECRET-KEY, I want Terraform to generate a random one.
resource "random_password" "secret_key" {
  length  = 64
  special = false
}

# NETWORKS
# Public Network
resource "docker_network" "public" {
  name   = "${var.student_name}-ctfd-net"
  driver = "bridge"
}

# Internal Network
resource "docker_network" "internal" {
  name     = "${var.student_name}-ctfd-internal"
  driver   = "bridge"
  internal = true
}

# VOLUMES
# MYSQL - .data/mysql:/var/lib/mysql
resource "docker_volume" "mysql" {
  name = "${var.student_name}-ctfd-mysql"
}

# Redis - .data/redis:/data 
resource "docker_volume" "redis" {
  name = "${var.student_name}-ctfd-redis"
}

# Uploads - .data/CTFd/uploads:/var/uploads 
resource "docker_volume" "uploads" {
  name = "${var.student_name}-ctfd-uploads"
}

# Logs - .data/CTFd/logs:/var/log/CTFd
resource "docker_volume" "logs" {
  name = "${var.student_name}-ctfd-logs"
}

# IMAGES
resource "docker_image" "ctfd" {
  name = "ctfd/ctfd:latest"
}

resource "docker_image" "mariadb" {
  name = "mariadb:10.11"
}

resource "docker_image" "redis" {
  name = "redis:4"
}

#DATABASE
resource "docker_container" "db" {
  name    = "${var.student_name}-ctfd-db"
  image   = docker_image.mariadb.image_id
  restart = "unless-stopped"

  env = [
    "MARIADB_ROOT_PASSWORD=${var.db_root_password}",
    "MARIADB_USER=ctfd",
    "MARIADB_PASSWORD=${var.db_password}",
    "MARIADB_DATABASE=ctfd",
    "MARIADB_AUTO_UPGRADE=1",
  ]

  # Required MariaDB defaults from compose file
  command = [
    "mysqld",
    "--character-set-server=utf8mb4",
    "--collation-server=utf8mb4_unicode_ci",
    "--wait_timeout=28800",
    "--log-warnings=0",
  ]

  volumes {
    volume_name    = docker_volume.mysql.name
    container_path = "/var/lib/mysql"
  }

  # The alias keeps the compose hostname db
  networks_advanced {
    name    = docker_network.internal.name
    aliases = ["db"]
  }
}

# CACHE
resource "docker_container" "cache" {
  name    = "${var.student_name}-ctfd-cache"
  image   = docker_image.redis.image_id
  restart = "unless-stopped"

  volumes {
    volume_name    = docker_volume.redis.name
    container_path = "/data"
  }

  networks_advanced {
    name    = docker_network.internal.name
    aliases = ["cache"]
  }
}

# Ctfd Container
resource "docker_container" "ctfd" {
  name    = "${var.student_name}-ctfd"
  image   = docker_image.ctfd.image_id
  restart = "unless-stopped"

  ports {
    internal = 8000
    external = var.ctfd_port
  }

  env = [
    "SECRET_KEY=${random_password.secret_key.result}",
    "UPLOAD_FOLDER=/var/uploads",
    "LOG_FOLDER=/var/log/CTFd",
    "DATABASE_URL=mysql+pymysql://ctfd:${var.db_password}@db/ctfd",
    "REDIS_URL=redis://cache:6379",
    "WORKERS=1",
    "ACCESS_LOG=-",
    "ERROR_LOG=-",
  ]

  volumes {
    volume_name    = docker_volume.uploads.name
    container_path = "/var/uploads"
  }

  volumes {
    volume_name    = docker_volume.logs.name
    container_path = "/var/log/CTFd"
  }

  # Public network for the published port, internal network to reach db/cache
  networks_advanced {
    name = docker_network.public.name
  }

  networks_advanced {
    name = docker_network.internal.name
  }

  depends_on = [docker_container.db, docker_container.cache]
}

# OUTPUTS
output "ctfd_url" {
  description = "Link to CTFd Setup"
  value       = "http://<server-ip>:${var.ctfd_port}"
}

output "containers" {
  value = [
    docker_container.ctfd.name,
    docker_container.db.name,
    docker_container.cache.name,
  ]
}
