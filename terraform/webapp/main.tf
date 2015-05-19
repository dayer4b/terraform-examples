provider "aws" {
    region = "${var.region}"
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
}

resource "aws_security_group" "ec2-mywebapp-sg" {
    name = "ec2-mywebapp-${var.environment}-sg"
    description = "Security group for my web app"
    ingress {
        from_port = "22"
        to_port = "22"
        protocol = "tcp"
        cidr_blocks = [
            "0.0.0.0/0"
        ]
    }
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = [
            "${var.elb_master_web_sg_id}"
        ]
    }
    lifecycle {
        create_before_destroy = true
    }
    tags {
        Environment = "${var.environment}"
        role = "mywebappapp"
        project = "myproject"
    }
}

resource "aws_elb" "elb-mywebapp" {
    name = "elb-${var.environment}-mywebapp"
    availability_zones = [
        "${var.region}a",
        "${var.region}b",
        "${var.region}c"
    ]
    listener {
        instance_port = 80
        instance_protocol = "http"
        lb_port = 80
        lb_protocol = "http"
    }
    listener {
        instance_port = 80
        instance_protocol = "http"
        lb_port = 443
        lb_protocol = "https"
        ssl_certificate_id = "${var.webapp_cert}"
    }
    health_check {
      healthy_threshold = 2
      unhealthy_threshold = 2
      timeout = 3
      target = "TCP:80"
      interval = 12
    }
    security_groups = [
        "${var.elb_master_web_sg_id}"
    ]
    tags {
        Environment = "${var.environment}"
        role = "mywebappapp"
        project = "myproject"
    }
    cross_zone_load_balancing = true
}

resource "aws_launch_configuration" "lc-mywebapp" {
    user_data = "${file(\"userdata.sh\")} webapp ${var.secret_bucket} ${var.environment}"
    image_id = "${lookup(var.base_ami, var.region)}"
    instance_type = "t2.micro"
    key_name = "${lookup(var.ssh_key_name, var.region)}"
    iam_instance_profile = "generic"
    associate_public_ip_address = true
    security_groups = [
        "${aws_security_group.ec2-mywebapp-sg.id}"
    ]
    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_autoscaling_group" "as-mywebapp" {
    name = "as-${var.environment}-mywebapp"
    vpc_zone_identifier = ["${split(",", var.subnets)}"]
    availability_zones = [
        "${var.region}a",
        "${var.region}b",
        "${var.region}c"
    ]
    depends_on = [
        "aws_launch_configuration.lc-mywebapp"
    ]
    launch_configuration = "${aws_launch_configuration.lc-mywebapp.id}"
    max_size = 10
    min_size = 1
    desired_capacity = 1
    load_balancers = [
        "elb-${var.environment}-mywebapp"
    ]
    tag {
      key = "Environment"
      value = "${var.environment}"
      propagate_at_launch = true
    }
    tag {
      key = "role"
      value = "mywebapp"
      propagate_at_launch = true
    }
    tag {
      key = "project"
      value = "myproject"
      propagate_at_launch = true
    }
}
