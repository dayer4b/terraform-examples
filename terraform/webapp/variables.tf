variable "environment" {}
variable "access_key" {}
variable "secret_key" {}
variable "secret_bucket" {}
variable "subnets" {}
variable "collector_cert" {}
variable "webapp_cert" {}
variable "ssh_key_file" {
    default = {
        us-west-2 = "my-ssh-key.pem"
    }
}
variable "region" {
    default = "us-west-2"
}
variable "ssh_key_name" {
    default = {
        us-west-2 = "my-ssh-key-name"
    }
}
variable "base_ami" {
    default = {
        us-west-2 = "ami-51604e61"
    }
}
variable "elb_master_web_sg_id" {
    default = "sg-2dbfb048"
}
# NOTE - this deletes EBS devices, only change it for testing purposes!
variable "del_on_term" {
    default = "false"
}
