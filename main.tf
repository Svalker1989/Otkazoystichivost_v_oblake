#Блок подключения к yandex cloud через terraform provider
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}
#Указываем параметры подключения к облаку. Получил эти параметры через yc init
provider "yandex" {
  token     = ""
  cloud_id  = ""
  folder_id = ""
  zone      = "ru-central1-b"
}

#Создаем саму группу размещения
resource "yandex_compute_placement_group" "str-group1" {
  name = "str-pg1"
}

#создаем ВМ в количестве 2 шт
resource "yandex_compute_instance" "vm" {
  count = 2
  name = "vm${count.index}"

  resources {
    core_fraction = 20
    cores  = 2
    memory = 2
  }

#Определяем политику размещения ВМ в группе
placement_policy {
  placement_group_id = "${yandex_compute_placement_group.str-group1.id}"
}

  boot_disk {
    initialize_params {
      image_id = "fd87q4jvf0vdho41nnvr"
      size = 20
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = true
  }

#файл для выполнения директив cloud init. Выполняется 1 раз в момент создания ВМ  
  metadata = {
    user-data = "${file("./metadata.yaml")}"
  }

}
#Создаем целевую группу для балансировщика и включаем в неё ранее созданные ВМ для балансировки между ними
resource "yandex_lb_target_group" "str-tg" {
  name           = "str-tg"

  target {
    subnet_id    = yandex_vpc_subnet.subnet-1.id
    address   = yandex_compute_instance.vm[0].network_interface.0.ip_address
  }
  target {
    subnet_id    = yandex_vpc_subnet.subnet-1.id
    address   = yandex_compute_instance.vm[1].network_interface.0.ip_address
  }
}

#Создаем балансировщик, который работает на 80 порту и указываем какую целевую группу использовать для балансировки
resource "yandex_lb_network_load_balancer" "str-lb" {
  name = "str-lb"
  listener {
    name = "str-lb-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }
  attached_target_group {
    target_group_id = yandex_lb_target_group.str-tg.id
    healthcheck {
      name = "http-check"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

resource "yandex_vpc_network" "network-1" {
  name = "network1"
}

resource "yandex_vpc_subnet" "subnet-1" {
  name           = "subnet1"
  zone           = "ru-central1-b"
  network_id     = "${yandex_vpc_network.network-1.id}"
  v4_cidr_blocks = ["192.168.10.0/24"]
}

#Вывести внешние и внутренние ip созданных ВМ
output "internal_ip_address_vm_1" {
  value = yandex_compute_instance.vm[0].network_interface.0.ip_address
}
output "external_ip_address_vm_1" {
  value = yandex_compute_instance.vm[0].network_interface.0.nat_ip_address
}

output "internal_ip_address_vm_2" {
  value = yandex_compute_instance.vm[1].network_interface.0.ip_address
}
output "external_ip_address_vm_2" {
  value = yandex_compute_instance.vm[1].network_interface.0.nat_ip_address
}
