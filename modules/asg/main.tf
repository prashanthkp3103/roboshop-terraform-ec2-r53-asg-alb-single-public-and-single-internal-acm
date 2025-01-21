
##this is for App components where it will 22 from default vpc bastion and
resource "aws_security_group" "main" {
  #this lb should be created when asg is created
  #count = var.asg ? 1 : 0  #if var.asg is false then 0(create) else 1(dont create)
  name        = "${var.name}-${var.env}-sg"
  description = "${var.name}-${var.env}-sg"
  vpc_id      = var.vpc_id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks =  var.bastion_node
    #below condition is if var.name = frontend then public other wise have var.allow_lb_sg_cidr
    #cidr_blocks = var.name == "frontend" ? ["0.0.0.0/0"] : var.allow_lb_sg_cidr
  }

  ingress {
    from_port   = var.allow_port
    to_port     = var.allow_port
    protocol    = "TCP"
    cidr_blocks = var.allow_sg_cidr
  }
  tags = {
    Name = "${var.name}-${var.env}-asg-sg"
  }
}


#this requires for Auto scaling
#creates launch template based asg variable true or false
#this create all the ec2 instances
resource "aws_launch_template" "main" {
  #count   = var.asg ? 1 : 0  #if var.asg creation is true then 1(create) else 0(dont create)
  name = "${var.name}-${var.env}"
  image_id      = data.aws_ami.ami.id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.main.id]
  #this is to choose spot instance
  instance_market_options {
    market_type = "spot"
  }

  user_data   = base64encode(templatefile("${path.module}/userdata.sh", {
    env       = var.env
    role_name       = var.name
    app_name       = var.name
    vault_token   = var.vault_token

  }))

  tags = {
    Name  = "${var.name}-${var.env}"
  }
}


#this requires for Auto scaling
resource "aws_autoscaling_group" "main" {
  #count   = var.asg ? 1 : 0  #if var.asg is true then 1(create) else 0(dont create)
  name = "${var.name}-${var.env}-asg"
  desired_capacity   = var.capacity["desired"]
  max_size           = var.capacity["max"]
  min_size           = var.capacity["min"]
  vpc_zone_identifier = var.subnet_ids
  #below 1 property is  of LB for asg tg
  # Here we are loading Lb, and we can also load Target groups as well
  #target_group_arns = [aws_lb_target_group.main.*.arn[count.index]]
  target_group_arns = [aws_lb_target_group.main.arn]


  launch_template {
    #aws_launch_template.main.*.id[0] = meaning first one from the list
    id      = aws_launch_template.main.*.id[0]
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = "${var.name}-${var.env}"
  }
}



##This ASG target group to have LB for ASG
#LB target group - target group will have list of instances
#created multiple instances would be part of target group
resource "aws_lb_target_group" "main" {
  #this lb should be created when asg is created
  #count = var.asg ? 1 : 0  #if var.asg creation is false then 0(create) else 1(dont create)
  name        = "${var.name}-${var.env}-tg"
  port        = var.allow_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  health_check {
    enabled = true
    healthy_threshold = 2 #health is good
    unhealthy_threshold = 2 #health is bad
    interval = 5 #seconds
    path = "/health"  #path we are checking is /health
    timeout = 3 #i hit /health i will wait for 3sec and say it is healthy or not healthy
  }
}

#all the lb dns will be created
resource "aws_route53_record" "lb" {
  zone_id = var.zone_id
  name    = "${var.name}.${var.env}"
  type    = "CNAME"
  ttl     = 10
  records = [var.dns_name]
}

#all the lb cnames will be this listener condition host header and forwarded to ASG target group
resource "aws_lb_listener_rule" "listener-rule" {
  listener_arn = var.listener_arn
  priority     = var.lb_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    host_header {
      values = [aws_route53_record.lb.fqdn]
    }
  }
}

#any request is coming with 80 port sending the traffic to target group
#creates multiple listeners based asg variable true or false
#below is for frontend
# resource "aws_lb_listener" "internal-http" {
#   #this lb should be created when asg is created
#   count = var.internal ? 1 : 0  #if var.internal is true then 1(create) else 0(dont create)
#   #load_balancer_arn = aws_lb.lb.*.arn[count.index]
#   load_balancer_arn = aws_lb.lb.arn
#   port              = "80"
#   protocol          = "HTTP"
#
#   #below is for sending the traffic to lb target groups
#   default_action {
#     type             = "forward"
#     #target_group_arn = aws_lb_target_group.main.*.arn[count.index]
#     target_group_arn = aws_lb_target_group.main.arn
#   }
# }
#
# # resource "aws_lb_listener" "public-http" {
# #   #this lb should be created when asg is created
# #   count = var.internal ? 0 : 1  #if var.internal is true then 0(dont create) else 1 (create)
# #   #load_balancer_arn = aws_lb.lb.*.arn[count.index]
# #   load_balancer_arn = aws_lb.lb.arn
# #   port              = "80"
# #   protocol          = "HTTP"
# #
# #   #below is for sending the traffic to lb target groups
# #   default_action {
# #     type             = "redirect"
# #     #target_group_arn = aws_lb_target_group.main.*.arn[count.index]
# #     redirect {
# #       port = "443"
# #       protocol = "HTTPS"
# #       status_code = "HTTP_301"
# #     }
# #   }
# # }
# #

# # #creates multiple records based asg variable true or false
# # #cname is alias name for lb
# # #it will create alias names for all the load balancers (internal and external)
# # #based on this only frontend gets started
# # resource "aws_route53_record" "lb" {
# #   #count = var.asg ? 1 : 0 #create if var.asg is true(created) then 1(create) else 0(dont create) - 0 false -1 true
# #   zone_id = var.zone_id
# #   name    = "${var.name}.${var.env}"
# #   type    = "CNAME"
# #   ttl     = 10
# #   #records = [aws_lb.lb.*.dns_name[count.index]]
# #   records = [aws_lb.lb.dns_name]
# # }

