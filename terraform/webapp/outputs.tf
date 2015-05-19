output "elb_dns_name" {
    value = "${aws_elb.elb-mywebapp.dns_name}"
}
