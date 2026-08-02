###############################################################################
# Application Load Balancer fronting the FastAPI service.
#
# WHY THIS EXISTS: with no NAT gateway the tasks sit in public subnets, and a
# Fargate task's public IP is ephemeral -- it changes on every deployment and
# every crash restart. The frontend cannot be pointed at a moving IP, so the ALB
# supplies the one stable DNS name for the API. It also terminates TLS, which a
# bare task cannot do without shipping certificates into the container.
#
# COST: ~$16/mo for the load balancer hour plus LCU charges. It is the single
# largest line item in this stack. Set enable_alb = false in the root module if
# you are only smoke-testing the service and can live with reading the task's
# current public IP out of the ECS console.
#
# target_type = "ip" is required for awsvpc/Fargate: targets are ENI addresses,
# not instance IDs.
###############################################################################

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = [var.security_group_id]

  idle_timeout               = var.idle_timeout
  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "this" {
  # name_prefix, not name. Any change that forces replacement (port, target_type,
  # vpc_id) has to create the new target group before destroying the old one --
  # the listener references it by ARN, so a destroy-first replacement fails with
  # "target group is currently in use by a listener". Create-before-destroy with a
  # fixed name would instead collide on the name. AWS caps this prefix at 6
  # characters and appends a generated suffix.
  name_prefix = var.target_group_name_prefix
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  # Backtests run off the request path (POST /runs returns 202), so requests are
  # short and the default deregistration delay is longer than it needs to be.
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # The listener references the target group by ARN; replacing the group without
  # creating the replacement first would break that reference mid-apply.
  lifecycle {
    create_before_destroy = true

    # Both listeners are conditional -- HTTP on enable_http_listener, HTTPS on a
    # non-null certificate. Turning off the first without supplying the second
    # builds a load balancer with NO listeners, leaving this target group
    # attached to nothing. Terraform reports success, and the failure surfaces
    # one resource later when the ECS service tries to register:
    #   InvalidParameterException: The target group with targetGroupArn ... does
    #   not have an associated load balancer
    # Fail at plan time with an explanation instead.
    precondition {
      condition     = var.enable_http_listener || var.certificate_arn != null
      error_message = "The ALB would have no listeners: enable_http_listener is false and certificate_arn is null. Set certificate_arn to serve HTTPS, re-enable the HTTP listener, or set enable_alb = false to drop the load balancer entirely."
    }
  }
}

###############################################################################
# Listeners.
#
# With no certificate: a single HTTP:80 listener forwards to the tasks. This is
# the default because ACM needs a domain you own, and the stack has to be usable
# before DNS exists.
#
# With certificate_arn set: HTTPS:443 forwards, and HTTP:80 (if still enabled)
# redirects to it rather than serving plaintext.
###############################################################################

resource "aws_lb_listener" "http" {
  count = var.enable_http_listener ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this.arn
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [] : [1]
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count = var.certificate_arn == null ? 0 : 1

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
